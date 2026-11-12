-- Task 10 - Amina: demo for the defense (DataGrip).
-- Run ONE statement at a time: put the cursor on it and press Ctrl+Enter.
-- Steps 3, 4 and 6 are SUPPOSED to fail - that is the point of the demo.
-- Step 9 removes everything the demo added.

-- 1. Countries for the phone dropdown
SELECT country_code, name, '+' || dial_code AS code, min_digits, max_digits, example_mask
FROM phone_countries
ORDER BY sort_order;

-- 2. Patients: phone stored as '+' and digits, with the country next to it
SELECT patient_id, full_name, phone_country, phone
FROM patients
ORDER BY patient_id;

-- 3. ERROR expected: Uzbekistan selected, but the number is Kazakh (+7)
INSERT INTO patients(full_name, email, phone_country, phone, birth_date)
VALUES ('Demo Wrong Code', 'demo1@mail.test', 'UZ', '+77011234567', '2000-01-01');

-- 4. ERROR expected: Kazakhstan selected, but only 9 digits after +7 (need 10)
INSERT INTO patients(full_name, email, phone_country, phone, birth_date)
VALUES ('Demo Short', 'demo2@mail.test', 'KZ', '+7701123456', '2000-01-01');

-- 5. OK: correct Uzbek number
INSERT INTO patients(full_name, email, phone_country, phone, birth_date)
VALUES ('Demo Uzbek', 'demo3@mail.test', 'UZ', '+998901112233', '2000-01-01')
RETURNING patient_id, phone_country, phone;

-- 6. ERROR expected: reason longer than 1000 characters
SELECT book_appointment(
    (SELECT patient_id FROM patients WHERE email = 'demo3@mail.test'),
    (SELECT min(slot_id) FROM v_free_slots),
    repeat('a', 1001));

-- 7. OK: long reason (600 characters) - before the change max was 255
SELECT book_appointment(
    (SELECT patient_id FROM patients WHERE email = 'demo3@mail.test'),
    (SELECT min(slot_id) FROM v_free_slots),
    repeat('Болит голова, температура 38. ', 20));

-- 8. Check the saved reason length
SELECT a.appointment_id, p.full_name, char_length(a.reason) AS reason_length
FROM appointments a JOIN patients p ON p.patient_id = a.patient_id
WHERE p.email = 'demo3@mail.test';

-- 9. Cleanup: remove the demo data
DELETE FROM appointments WHERE patient_id IN (SELECT patient_id FROM patients WHERE email LIKE 'demo_@mail.test');
DELETE FROM patients WHERE email LIKE 'demo_@mail.test';

-- 10. Task 11: passwords. Run AFTER "python manage.py setup_roles" (it creates the login accounts).
-- Only Argon2 hashes, each with its own random salt - the same demo password gives different hashes.
SELECT username, left(password, 40) || '...' AS password_hash
FROM auth_user
ORDER BY id;

-- 11. Task 11: no clinic table has a password column (the hash is kept in one place only). Must return 0 rows.
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name ILIKE '%password%'
  AND table_name NOT LIKE 'auth\_%';
