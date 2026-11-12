-- Task 11 - Amina: migration for databases created BEFORE the password storage change.
-- A NEW database does not need this file: 01_schema.sql already has no password column.
--
-- What changes: patients.password_hash is removed. The password hash is kept in ONE place only -
-- the Django login account (auth_user.password, Argon2). Two copies of the same hash get out of sync
-- (for example after a password change) and double the places where a hash can leak.
-- Safe to run twice.
BEGIN;
ALTER TABLE patients DROP COLUMN IF EXISTS password_hash;
COMMIT;

-- Check: must return 0 rows
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name ILIKE '%password%'
  AND table_name IN ('patients', 'doctors', 'appointments');
