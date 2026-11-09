-- Migration: phone with country selection + longer appointment reason.
-- For databases that were ALREADY created from the old 01_schema.sql.
-- A NEW database does not need this file: 01_schema.sql and 02_functions_views.sql already contain everything.
-- Safe to run twice. Runs in one transaction: on any error nothing changes.
BEGIN;
SET search_path = public, extensions;

-- 1. Countries table
CREATE TABLE IF NOT EXISTS phone_countries (
    country_code char(2)     PRIMARY KEY CHECK (country_code ~ '^[A-Z]{2}$'),  -- ISO 3166-1 alpha-2
    name         varchar(60) NOT NULL,
    dial_code    varchar(4)  NOT NULL CHECK (dial_code ~ '^[1-9][0-9]{0,3}$'),
    min_digits   smallint    NOT NULL CHECK (min_digits BETWEEN 4 AND 14),
    max_digits   smallint    NOT NULL CHECK (max_digits BETWEEN 4 AND 14),
    example_mask varchar(25),
    sort_order   smallint    NOT NULL DEFAULT 100,
    is_active    boolean     NOT NULL DEFAULT true,
    CONSTRAINT phone_countries_digits_order CHECK (max_digits >= min_digits),
    CONSTRAINT phone_countries_total_len    CHECK (length(dial_code) + max_digits <= 15)  -- E.164 limit
);

-- Reference data (needed by the app, so it is here and not in 04_seed.sql)
INSERT INTO phone_countries(country_code, name, dial_code, min_digits, max_digits, example_mask, sort_order) VALUES
 ('KZ','Kazakhstan',     '7',   10, 10, '+7 (701) 123-45-67',   1),
 ('RU','Russia',         '7',   10, 10, '+7 (912) 345-67-89',   2),
 ('UZ','Uzbekistan',     '998',  9,  9, '+998 90 123-45-67',    3),
 ('KG','Kyrgyzstan',     '996',  9,  9, '+996 555 123-456',     4),
 ('TJ','Tajikistan',     '992',  9,  9, '+992 93 123-4567',     5),
 ('TM','Turkmenistan',   '993',  8,  8, '+993 6 123-4567',      6),
 ('AZ','Azerbaijan',     '994',  9,  9, '+994 50 123-45-67',    7),
 ('AM','Armenia',        '374',  8,  8, '+374 77 123-456',      8),
 ('GE','Georgia',        '995',  9,  9, '+995 555 12-34-56',    9),
 ('BY','Belarus',        '375',  9,  9, '+375 29 123-45-67',   10),
 ('UA','Ukraine',        '380',  9,  9, '+380 50 123-4567',    11),
 ('TR','Turkey',         '90',  10, 10, '+90 532 123-4567',    12),
 ('CN','China',          '86',   7, 11, '+86 131 2345-6789',   13),
 ('KR','South Korea',    '82',   8, 10, '+82 10 1234-5678',    14),
 ('AE','UAE',            '971',  8,  9, '+971 50 123-4567',    15),
 ('IN','India',          '91',  10, 10, '+91 98765 43210',     16),
 ('DE','Germany',        '49',   6, 11, '+49 151 23456789',    17),
 ('GB','United Kingdom', '44',   9, 10, '+44 7400 123456',     18),
 ('US','United States',  '1',   10, 10, '+1 (201) 555-0123',   19)
ON CONFLICT (country_code) DO NOTHING;

-- 2. patients: country column + E.164 phone
ALTER TABLE patients ADD COLUMN IF NOT EXISTS phone_country char(2) NOT NULL DEFAULT 'KZ'
    REFERENCES phone_countries(country_code);
DROP TRIGGER IF EXISTS trg_patients_phone ON patients;   -- re-created in step 4
ALTER TABLE patients DROP CONSTRAINT IF EXISTS patients_phone_check;
-- old numbers could be stored without '+': add it
UPDATE patients SET phone = '+' || phone WHERE phone !~ '^\+';
ALTER TABLE patients ALTER COLUMN phone TYPE varchar(16);
ALTER TABLE patients ADD CONSTRAINT patients_phone_check CHECK (phone ~ '^\+[1-9][0-9]{6,14}$');
CREATE INDEX IF NOT EXISTS ix_patients_phone_country ON patients(phone_country);

-- 3. appointments.reason: varchar(255) -> text up to 1000 characters
ALTER TABLE appointments ALTER COLUMN reason TYPE text;
ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_reason_check;
ALTER TABLE appointments ADD CONSTRAINT appointments_reason_check
    CHECK (reason IS NULL OR char_length(reason) <= 1000);

-- 4. Trigger for phone length by country
-- Phone check: the number must start with '+<dial_code>' of the selected country
-- and the national part must have the right length for that country.
-- The frontend sends phone already normalized: '+' and digits only (+77011234567).
CREATE OR REPLACE FUNCTION check_patient_phone()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    c        phone_countries%ROWTYPE;
    national text;
BEGIN
    SELECT * INTO c FROM phone_countries WHERE country_code = NEW.phone_country;
    IF NOT FOUND OR NOT c.is_active THEN
        RAISE EXCEPTION 'Страна % недоступна для номера телефона', NEW.phone_country
              USING ERRCODE = '23514';
    END IF;

    IF NEW.phone NOT LIKE '+' || c.dial_code || '%' THEN
        RAISE EXCEPTION 'Номер % должен начинаться с +% (%)', NEW.phone, c.dial_code, c.name
              USING ERRCODE = '23514';
    END IF;

    national := substr(NEW.phone, length(c.dial_code) + 2);
    IF length(national) NOT BETWEEN c.min_digits AND c.max_digits THEN
        RAISE EXCEPTION 'Для страны % номер без кода должен содержать от % до % цифр, получено %',
              c.name, c.min_digits, c.max_digits, length(national)
              USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_patients_phone ON patients;
CREATE TRIGGER trg_patients_phone
    BEFORE INSERT OR UPDATE OF phone, phone_country ON patients
    FOR EACH ROW EXECUTE FUNCTION check_patient_phone();

-- 5. Access (only if roles from 03_roles.sql exist)
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinic_app') THEN
        GRANT SELECT ON phone_countries TO clinic_app;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinic_report') THEN
        GRANT SELECT ON phone_countries TO clinic_report;
    END IF;
END $$;

COMMIT;

-- Check after migration: existing patients whose phone does not match their country
-- (the trigger checks only new INSERT/UPDATE). Must return 0 rows; fix those rows if not.
SELECT p.patient_id, p.phone, p.phone_country
FROM patients p JOIN phone_countries c ON c.country_code = p.phone_country
WHERE p.phone NOT LIKE '+' || c.dial_code || '%'
   OR length(p.phone) - 1 - length(c.dial_code) NOT BETWEEN c.min_digits AND c.max_digits;

CREATE UNIQUE INDEX IF NOT EXISTS ux_patients_phone ON patients(phone);