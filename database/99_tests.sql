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
-- Task 10 - Amina: phone country and reason length tests
SELECT pg_temp.expect_error('phone without + is rejected',
  'INSERT INTO patients(full_name,email,phone,birth_date,password_hash) VALUES (''x'',''p1@mail.test'',''77010000011'',''2000-01-01'',''h'')','23514');
SELECT pg_temp.expect_error('KZ phone with wrong length is rejected',
  'INSERT INTO patients(full_name,email,phone_country,phone,birth_date,password_hash) VALUES (''x'',''p2@mail.test'',''KZ'',''+770100000'',''2000-01-01'',''h'')','23514');
SELECT pg_temp.expect_error('phone code not matching country is rejected',
  'INSERT INTO patients(full_name,email,phone_country,phone,birth_date,password_hash) VALUES (''x'',''p3@mail.test'',''UZ'',''+77010000012'',''2000-01-01'',''h'')','23514');
SELECT pg_temp.expect_error('unknown phone country is rejected',
  'INSERT INTO patients(full_name,email,phone_country,phone,birth_date,password_hash) VALUES (''x'',''p4@mail.test'',''XX'',''+77010000013'',''2000-01-01'',''h'')',NULL);
SELECT pg_temp.expect_error('reason longer than 1000 chars is rejected',
  'UPDATE appointments SET reason=repeat(''a'',1001) WHERE appointment_id=1','23514');
DO $$ BEGIN
  INSERT INTO patients(full_name,email,phone_country,phone,birth_date,password_hash)
  VALUES ('x','p5@mail.test','UZ','+998935554433','2000-01-01','h');
  INSERT INTO results VALUES ('Uzbek phone with UZ country is accepted', true);
EXCEPTION WHEN OTHERS THEN INSERT INTO results VALUES ('Uzbek phone with UZ country is accepted', false);
END $$;
DO $$ BEGIN
  UPDATE appointments SET reason=repeat('a',1000) WHERE appointment_id=1;
  INSERT INTO results VALUES ('reason of 1000 chars is accepted', FOUND);
EXCEPTION WHEN OTHERS THEN INSERT INTO results VALUES ('reason of 1000 chars is accepted', false);
END $$;
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

-- Task 10 - Gulsezim: weekly schedule tests
-- weekly schedules (a Monday far in the future is used so seed slots do not interfere)
SELECT pg_temp.expect_error('day_of_week 8 is rejected',
  'INSERT INTO weekly_schedules(doctor_id,day_of_week,start_time,end_time) VALUES (1,8,''09:00'',''12:00'')','23514');
SELECT pg_temp.expect_error('schedule end before start is rejected',
  'INSERT INTO weekly_schedules(doctor_id,day_of_week,start_time,end_time) VALUES (1,6,''12:00'',''09:00'')','23514');
SELECT pg_temp.expect_error('second schedule for the same doctor and day is rejected',
  'INSERT INTO weekly_schedules(doctor_id,day_of_week,start_time,end_time) VALUES (1,1,''09:00'',''12:00'')','23505');
SELECT pg_temp.expect_error('schedule for unknown doctor is rejected (FK)',
  'INSERT INTO weekly_schedules(doctor_id,day_of_week,start_time,end_time) VALUES (999,6,''09:00'',''12:00'')','23503');
SELECT pg_temp.expect_error('lunch with only one time is rejected',
  'INSERT INTO weekly_schedules(doctor_id,day_of_week,start_time,end_time,lunch_start) VALUES (1,6,''09:00'',''18:00'',''13:00'')','23514');
SELECT pg_temp.expect_error('lunch outside working hours is rejected',
  'INSERT INTO weekly_schedules(doctor_id,day_of_week,start_time,end_time,lunch_start,lunch_end) VALUES (1,6,''09:00'',''12:00'',''13:00'',''14:00'')','23514');
SELECT pg_temp.expect_error('lunch end before start is rejected',
  'INSERT INTO weekly_schedules(doctor_id,day_of_week,start_time,end_time,lunch_start,lunch_end) VALUES (1,6,''09:00'',''18:00'',''14:00'',''13:00'')','23514');
SELECT pg_temp.expect_error('slot length 0 is rejected','SELECT generate_slots(CURRENT_DATE+60, CURRENT_DATE+61, 0)',NULL);

DO $$
DECLARE
  d  date := CURRENT_DATE + 365 + ((8 - extract(isodow FROM CURRENT_DATE + 365)::int) % 7);  -- a Monday
  n1 integer; n2 integer;
BEGIN
  n1 := generate_slots(d, d, 30);   -- 3 doctors x (09-13 and 14-18 = 8 hours = 16 slots)
  n2 := generate_slots(d, d, 30);   -- second run must create nothing
  INSERT INTO results VALUES ('generate_slots creates 16 slots per doctor (lunch excluded)', n1 = 48);
  INSERT INTO results VALUES ('generate_slots is safe to run twice', n2 = 0);
  INSERT INTO results SELECT 'no slot is created during lunch 13:00-14:00',
    NOT EXISTS (SELECT 1 FROM time_slots WHERE slot_date = d AND start_time >= '13:00' AND start_time < '14:00');
  INSERT INTO results VALUES ('generate_slots skips weekends (Sunday)', generate_slots(d + 6, d + 6, 30) = 0);
  UPDATE doctors SET is_active = false WHERE doctor_id = 3;   -- no bookings, nothing to move
  INSERT INTO results VALUES ('generate_slots skips inactive doctors', generate_slots(d + 7, d + 7, 30) = 32);
END $$;

-- Task 10 - Zhanerke: doctor deactivation test
-- (adapted from her 05_doctor_deactivation_tests.sql into the PASS/FAIL list of this file)
-- A future booking is cancelled and the patient is moved to another doctor of the same specialty.
DO $$
DECLARE
  sp integer; d1 integer; d2 integer; old_slot integer; new_slot integer; booked_id integer;
BEGIN
  INSERT INTO specialties(name) VALUES ('Deactivation test') RETURNING specialty_id INTO sp;
  INSERT INTO doctors(specialty_id, full_name, email, consultation_fee_kzt)
    VALUES (sp, 'Old doctor', 'old@deact.test', 0) RETURNING doctor_id INTO d1;
  INSERT INTO doctors(specialty_id, full_name, email, consultation_fee_kzt)
    VALUES (sp, 'New doctor', 'new@deact.test', 0) RETURNING doctor_id INTO d2;
  INSERT INTO time_slots(doctor_id, slot_date, start_time, end_time)
    VALUES (d1, CURRENT_DATE + 30, '10:00', '10:30') RETURNING slot_id INTO old_slot;
  INSERT INTO time_slots(doctor_id, slot_date, start_time, end_time)
    VALUES (d2, CURRENT_DATE + 30, '10:00', '10:30') RETURNING slot_id INTO new_slot;
  booked_id := book_appointment(1, old_slot, 'test reason');
  UPDATE doctors SET is_active = false WHERE doctor_id = d1;
  INSERT INTO results VALUES ('deactivation cancels the old booking',
    (SELECT status FROM appointments WHERE appointment_id = booked_id) = 'cancelled');
  INSERT INTO results VALUES ('deactivation moves the patient to another doctor, reason is kept',
    EXISTS (SELECT 1 FROM appointments WHERE patient_id = 1 AND slot_id = new_slot AND status = 'booked' AND reason = 'test reason'));
  BEGIN
    PERFORM book_appointment(1, old_slot);
    INSERT INTO results VALUES ('inactive doctor cannot be booked', false);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    INSERT INTO results VALUES ('inactive doctor cannot be booked', true);
  END;
END $$;

SELECT CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, name FROM results ORDER BY ok, name;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM results;
ROLLBACK;