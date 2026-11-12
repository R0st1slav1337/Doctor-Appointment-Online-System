
-- Online Doctor Appointment System - schema (PostgreSQL 14+)
-- Run order: 01_schema.sql, 02_functions_views.sql, 03_roles.sql, 04_seed.sql (optional)
-- Safe to run on an EMPTY database. Use 00_reset.sql first to start over in development.

-- Extensions live in their own schema so that "public" shows only OUR objects.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS citext     SCHEMA extensions;  -- case-insensitive e-mail
CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA extensions;  -- lets us forbid overlapping slots

-- Make the extension types/operators visible for every connection to this database
DO $$ BEGIN
    EXECUTE format('ALTER DATABASE %I SET search_path = public, extensions', current_database());
END $$;
SET search_path = public, extensions;   -- same for the rest of this script

CREATE TABLE specialties (
    specialty_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         varchar(80)  NOT NULL UNIQUE,
    description  varchar(255),
    is_active    boolean      NOT NULL DEFAULT true
);

CREATE TABLE doctors (
    doctor_id            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    specialty_id         integer      NOT NULL REFERENCES specialties(specialty_id),
    full_name            varchar(120) NOT NULL CHECK (length(btrim(full_name)) > 0),
    email                citext       NOT NULL UNIQUE,
    room_number          varchar(10),
    consultation_fee_kzt integer      NOT NULL CHECK (consultation_fee_kzt BETWEEN 0 AND 200000),
    is_active            boolean      NOT NULL DEFAULT true
);

-- Task 10 - Amina: phone with country selection and longer appointment reason (see check_patient_phone in 02)
-- Countries for the phone input (dropdown on the frontend).
-- dial_code = country calling code without '+'; min/max_digits = length of the national
-- number WITHOUT the country code. example_mask is a hint for the input placeholder.
CREATE TABLE phone_countries (
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
 ('KZ','Kazakhstan',      '7',   10, 10, '+7 (701) 123-45-67',   1),
 ('RU','Russia',          '7',   10, 10, '+7 (912) 345-67-89',   2),
 ('UZ','Uzbekistan',      '998',  9,  9, '+998 90 123-45-67',    3),
 ('KG','Kyrgyzstan',      '996',  9,  9, '+996 555 123-456',     4),
 ('TJ','Tajikistan',      '992',  9,  9, '+992 93 123-4567',     5),
 ('TM','Turkmenistan',    '993',  8,  8, '+993 6 123-4567',      6),
 ('AZ','Azerbaijan',      '994',  9,  9, '+994 50 123-45-67',    7),
 ('AM','Armenia',         '374',  8,  8, '+374 77 123-456',      8),
 ('GE','Georgia',         '995',  9,  9, '+995 555 12-34-56',    9),
 ('BY','Belarus',         '375',  9,  9, '+375 29 123-45-67',   10),
 ('UA','Ukraine',         '380',  9,  9, '+380 50 123-4567',    11),
 ('TR','Turkey',          '90',  10, 10, '+90 532 123-4567',    12),
 ('CN','China',           '86',   7, 11, '+86 131 2345-6789',   13),
 ('KR','South Korea',     '82',   8, 10, '+82 10 1234-5678',    14),
 ('AE','UAE',             '971',  8,  9, '+971 50 123-4567',    15),
 ('IN','India',           '91',  10, 10, '+91 98765 43210',     16),
 ('DE','Germany',         '49',   6, 11, '+49 151 23456789',    17),
 ('GB','Great Britain',   '44',   9, 10, '+44 7400 123456',     18),
 ('US','United States',   '1',   10, 10, '+1 (201) 555-0123',   19);

CREATE TABLE patients (
    patient_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     varchar(120) NOT NULL CHECK (length(btrim(full_name)) > 0),
    email         citext       NOT NULL UNIQUE,
    phone_country char(2)      NOT NULL DEFAULT 'KZ' REFERENCES phone_countries(country_code),
    -- stored in E.164 format: '+' + country code + national number, digits only, e.g. +77011234567
    -- the length for the selected country is checked by trigger trg_patients_phone (02_functions_views.sql)
    phone         varchar(16)  NOT NULL CHECK (phone ~ '^\+[1-9][0-9]{6,14}$'),
    birth_date    date         NOT NULL CHECK (birth_date >= DATE '1900-01-01' AND birth_date <= CURRENT_DATE),
    -- No password here. Task 10/11 - Amina: the password hash is kept in ONE place only - the Django login
    -- account (auth_user.password, Argon2). The patient is linked to it by email.
    created_at    timestamptz  NOT NULL DEFAULT now()
);

-- one person = one account: a phone number can be registered only once
CREATE UNIQUE INDEX ux_patients_phone ON patients(phone);

CREATE TABLE time_slots (
    slot_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id  integer NOT NULL REFERENCES doctors(doctor_id),
    slot_date  date    NOT NULL,
    start_time time    NOT NULL,
    end_time   time    NOT NULL,
    CONSTRAINT slot_time_order CHECK (end_time > start_time),
    CONSTRAINT slot_unique_start UNIQUE (doctor_id, slot_date, start_time),
    -- a doctor cannot have two overlapping slots
    CONSTRAINT slot_no_overlap EXCLUDE USING gist (
        doctor_id WITH =,
        tsrange(slot_date + start_time, slot_date + end_time) WITH &&
    )
);

-- Task 10 - Gulsezim
-- Weekly working schedule for each doctor.
-- One working period and one optional lunch break per day.

CREATE TABLE weekly_schedules (
    schedule_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id integer NOT NULL REFERENCES doctors(doctor_id),
    day_of_week integer NOT NULL
        CHECK (day_of_week BETWEEN 1 AND 7),
    start_time time NOT NULL,
    end_time time NOT NULL,
    lunch_start time,
    lunch_end time,
    is_active boolean NOT NULL DEFAULT true,

    CONSTRAINT weekly_schedule_time_order
        CHECK (end_time > start_time),

    CONSTRAINT weekly_schedule_lunch_pair
        CHECK (
            (lunch_start IS NULL AND lunch_end IS NULL)
            OR
            (lunch_start IS NOT NULL AND lunch_end IS NOT NULL)
        ),

    CONSTRAINT weekly_schedule_lunch_time
        CHECK (
            lunch_start IS NULL
            OR lunch_end > lunch_start
        ),

    CONSTRAINT weekly_schedule_lunch_inside
        CHECK (
            lunch_start IS NULL
            OR (
                lunch_start >= start_time
                AND lunch_end <= end_time
            )
        ),

    CONSTRAINT weekly_schedule_unique_day
        UNIQUE (doctor_id, day_of_week)
);

CREATE TABLE appointments (
    appointment_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id     integer      NOT NULL REFERENCES patients(patient_id),
    slot_id        integer      NOT NULL REFERENCES time_slots(slot_id),
    status         varchar(15)  NOT NULL DEFAULT 'booked'
                   CHECK (status IN ('booked', 'cancelled', 'completed')),
    -- free text from the patient; up to 1000 characters (was varchar(255) - too short)
    reason         text         CHECK (reason IS NULL OR char_length(reason) <= 1000),
    created_at     timestamptz  NOT NULL DEFAULT now()
);

-- Core rule: one slot can have only ONE active appointment (no double booking).
-- A cancelled appointment stays as history and the slot can be booked again.
CREATE UNIQUE INDEX ux_one_active_booking_per_slot
    ON appointments(slot_id) WHERE status IN ('booked', 'completed');

-- Indexes for foreign keys and common searches
CREATE INDEX ix_doctors_specialty     ON doctors(specialty_id);
CREATE INDEX ix_slots_doctor_date     ON time_slots(doctor_id, slot_date);
CREATE INDEX ix_appointments_patient  ON appointments(patient_id, status);
CREATE INDEX ix_appointments_slot     ON appointments(slot_id);
CREATE INDEX ix_patients_phone_country ON patients(phone_country);