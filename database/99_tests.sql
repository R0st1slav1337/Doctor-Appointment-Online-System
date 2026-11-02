-- Smoke tests. Run on a database that has 01..04 applied. Prints PASS/FAIL lines; changes are rolled back.
\set ON_ERROR_STOP off
BEGIN;
CREATE TEMP TABLE results(name text, ok boolean);
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_name text, p_sql text, p_state text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  BEGIN EXECUTE p_sql; INSERT INTO results VALUES (p_name, false);
  EXCEPTION WHEN OTHERS THEN INSERT INTO results VALUES (p_name, SQLSTATE = p_state OR p_state IS NULL); END;
END $f$;

SELECT pg_temp.expect_error('double booking is rejected',
  'SELECT book_appointment(4,(SELECT slot_id FROM appointments WHERE status=''booked'' LIMIT 1))','23505');
SELECT pg_temp.expect_error('unknown patient is rejected (FK)',
  'SELECT book_appointment(999,(SELECT min(slot_id) FROM v_free_slots))','23503');
SELECT pg_temp.expect_error('unknown slot is rejected','SELECT book_appointment(1,999999)','P0002');
SELECT pg_temp.expect_error('bad status is rejected',
  'UPDATE appointments SET status=''maybe'' WHERE appointment_id=1','23514');
SELECT pg_temp.expect_error('end before start is rejected',
  'INSERT INTO time_slots(doctor_id,slot_date,start_time,end_time) VALUES (1,CURRENT_DATE+30,''10:00'',''09:00'')','23514');
SELECT pg_temp.expect_error('overlapping slots are rejected',
  'INSERT INTO time_slots(doctor_id,slot_date,start_time,end_time) SELECT doctor_id,slot_date,start_time+interval ''10 minutes'',end_time FROM time_slots LIMIT 1','23P01');
SELECT pg_temp.expect_error('duplicate e-mail (any case) is rejected',
  'INSERT INTO patients(full_name,email,phone,birth_date,password_hash) VALUES (''x'',''A@MAIL.TEST'',''+77010000009'',''2000-01-01'',''h'')','23505');
SELECT pg_temp.expect_error('bad phone is rejected',
  'INSERT INTO patients(full_name,email,phone,birth_date,password_hash) VALUES (''x'',''z@mail.test'',''abc'',''2000-01-01'',''h'')','23514');
SELECT pg_temp.expect_error('future birth date is rejected',
  'INSERT INTO patients(full_name,email,phone,birth_date,password_hash) VALUES (''x'',''y@mail.test'',''+77010000008'',CURRENT_DATE+1,''h'')','23514');
SELECT pg_temp.expect_error('negative fee is rejected',
  'INSERT INTO doctors(specialty_id,full_name,email,consultation_fee_kzt) VALUES (1,''n'',''n@x.test'',-5)','23514');
SELECT pg_temp.expect_error('deleting a patient with appointments is rejected',
  'DELETE FROM patients WHERE patient_id=1','23503');

-- cancel then rebook the same slot
SELECT cancel_appointment(1,1);
INSERT INTO results SELECT 'slot can be booked again after cancellation', book_appointment(4,(SELECT slot_id FROM time_slots t ORDER BY slot_id LIMIT 1),'again') IS NOT NULL;

-- reschedule: new slot taken -> old appointment must stay booked
SAVEPOINT s1;
DO $$ DECLARE a integer; taken integer;
BEGIN
  SELECT appointment_id INTO a FROM appointments WHERE patient_id=2 AND status='booked' LIMIT 1;
  SELECT slot_id INTO taken FROM appointments WHERE patient_id=3 AND status='booked' LIMIT 1;
  BEGIN PERFORM reschedule_appointment(a,2,taken); EXCEPTION WHEN OTHERS THEN NULL; END;
  INSERT INTO results SELECT 'failed reschedule keeps the old appointment', status='booked' FROM appointments WHERE appointment_id=a;
END $$;
-- reschedule to a free slot works
DO $$ DECLARE a integer; f integer; n integer;
BEGIN
  SELECT appointment_id INTO a FROM appointments WHERE patient_id=2 AND status='booked' LIMIT 1;
  SELECT slot_id INTO f FROM v_free_slots ORDER BY slot_id DESC LIMIT 1;
  n := reschedule_appointment(a,2,f);
  INSERT INTO results SELECT 'reschedule to a free slot works', (SELECT status FROM appointments WHERE appointment_id=a)='cancelled' AND n IS NOT NULL;
END $$;

INSERT INTO results SELECT 'v_free_slots has no booked slot', NOT EXISTS (SELECT 1 FROM v_free_slots f JOIN appointments a ON a.slot_id=f.slot_id AND a.status='booked');

SELECT CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, name FROM results ORDER BY ok, name;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM results;
ROLLBACK;
