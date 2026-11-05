-- Run AFTER 05_doctor_deactivation_zhanerke.sql in a test database.
-- Test data is rolled back at the end.
BEGIN;
DO $$
DECLARE
 sp_id integer; d1 integer; d2 integer; d3 integer; p integer;
 old_slot integer; new_slot integer; booked_id integer; new_id integer;
BEGIN
 INSERT INTO specialties(name) VALUES ('Zhanerke test specialty ' || txid_current()) RETURNING specialty_id INTO sp_id;
 INSERT INTO doctors(specialty_id,full_name,email,consultation_fee_kzt)
 VALUES (sp_id,'Old doctor','old'||txid_current()||'@example.test',0) RETURNING doctor_id INTO d1;
 INSERT INTO doctors(specialty_id,full_name,email,consultation_fee_kzt)
 VALUES (sp_id,'New doctor','new'||txid_current()||'@example.test',0) RETURNING doctor_id INTO d2;
 INSERT INTO doctors(specialty_id,full_name,email,consultation_fee_kzt)
 VALUES (sp_id,'Inactive doctor','inactive'||txid_current()||'@example.test',0) RETURNING doctor_id INTO d3;
 UPDATE doctors SET is_active=false WHERE doctor_id=d3;
 INSERT INTO patients(full_name,email,phone,birth_date,password_hash)
 VALUES ('Test patient','patient'||txid_current()||'@example.test','+77001234567','2000-01-01','test-hash') RETURNING patient_id INTO p;
 INSERT INTO time_slots(doctor_id,slot_date,start_time,end_time)
 VALUES(d1,CURRENT_DATE+30,'10:00','10:30') RETURNING slot_id INTO old_slot;
 INSERT INTO time_slots(doctor_id,slot_date,start_time,end_time)
 VALUES(d2,CURRENT_DATE+30,'10:00','10:30') RETURNING slot_id INTO new_slot;
 booked_id := book_appointment(p,old_slot,'test reason');
 UPDATE doctors SET is_active=false WHERE doctor_id=d1;
 IF (SELECT status FROM appointments WHERE appointment_id=booked_id) <> 'cancelled' THEN
  RAISE EXCEPTION 'FAIL: old booking not cancelled'; END IF;
 SELECT appointment_id INTO new_id FROM appointments WHERE patient_id=p AND slot_id=new_slot AND status='booked';
 IF new_id IS NULL THEN RAISE EXCEPTION 'FAIL: automatic replacement missing'; END IF;
 IF (SELECT reason FROM appointments WHERE appointment_id=new_id) <> 'test reason' THEN
  RAISE EXCEPTION 'FAIL: reason not preserved'; END IF;
 BEGIN
  PERFORM book_appointment(p,old_slot);
  RAISE EXCEPTION 'FAIL: inactive doctor accepted booking';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN NULL;
 END;
 RAISE NOTICE 'PASS: cancellation, replacement, history, reason, inactive doctor rejection';
END $$;
ROLLBACK;
