-- Database roles (least privilege). Change the passwords before real use!
-- The application connects as clinic_app. Analysts / managers use clinic_report.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinic_app') THEN
        CREATE ROLE clinic_app LOGIN PASSWORD 'change_me_app';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinic_report') THEN
        CREATE ROLE clinic_report LOGIN PASSWORD 'change_me_report';
    END IF;
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM clinic_app, clinic_report;
GRANT USAGE ON SCHEMA public, extensions TO clinic_app, clinic_report;

-- Application: read and write what it needs, but no DELETE and no schema changes.
GRANT SELECT, INSERT, UPDATE ON patients, doctors, specialties, time_slots, appointments, weekly_schedules TO clinic_app;
GRANT SELECT ON v_free_slots, v_doctor_load TO clinic_app;
GRANT SELECT ON phone_countries TO clinic_app, clinic_report;
GRANT EXECUTE ON FUNCTION book_appointment(integer, integer, varchar),
                          cancel_appointment(integer, integer),
                          reschedule_appointment(integer, integer, integer),
                          generate_slots(date, date, integer) TO clinic_app;

-- Reporting: read-only, without password_hash and without the health 'reason' text.
GRANT SELECT ON specialties, doctors, time_slots, weekly_schedules TO clinic_report;
GRANT SELECT (patient_id, created_at) ON patients TO clinic_report;
GRANT SELECT (appointment_id, patient_id, slot_id, status, created_at) ON appointments TO clinic_report;
GRANT SELECT ON v_doctor_load TO clinic_report;
