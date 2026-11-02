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

CREATE TABLE patients (
    patient_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     varchar(120) NOT NULL CHECK (length(btrim(full_name)) > 0),
    email         citext       NOT NULL UNIQUE,
    phone         varchar(20)  NOT NULL CHECK (phone ~ '^\+?[0-9]{10,15}$'),
    birth_date    date         NOT NULL CHECK (birth_date >= DATE '1900-01-01' AND birth_date <= CURRENT_DATE),
    password_hash varchar(255) NOT NULL,   -- will store a bcrypt/argon2 hash, never the password
    created_at    timestamptz  NOT NULL DEFAULT now()
);

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

CREATE TABLE appointments (
    appointment_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id     integer      NOT NULL REFERENCES patients(patient_id),
    slot_id        integer      NOT NULL REFERENCES time_slots(slot_id),
    status         varchar(15)  NOT NULL DEFAULT 'booked'
                   CHECK (status IN ('booked', 'cancelled', 'completed')),
    reason         varchar(255),
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
