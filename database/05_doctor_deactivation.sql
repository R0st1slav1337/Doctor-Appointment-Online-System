-- Task 10 - Zhanerke: preserve history when deactivating a doctor.
-- Apply AFTER 01_schema.sql and 02_functions_views.sql.
-- Policy: cancel only future booked appointments; keep past/completed records.
CREATE OR REPLACE FUNCTION cancel_future_bookings_on_deactivation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    old_booking record;
    replacement_slot integer;
BEGIN
    IF OLD.is_active AND NOT NEW.is_active THEN
        -- Preserve original appointment rows as cancelled history.
        -- Find another ACTIVE doctor with the SAME specialty, preferably
        -- on the same day and close to the original time; then later slots.
        FOR old_booking IN
            SELECT a.appointment_id, a.patient_id, a.reason, t.slot_id,
                   t.slot_date, t.start_time
            FROM appointments a
            JOIN time_slots t ON t.slot_id = a.slot_id
            WHERE t.doctor_id = NEW.doctor_id
              AND a.status = 'booked'
              AND (t.slot_date + t.start_time) > LOCALTIMESTAMP
            ORDER BY t.slot_date, t.start_time, a.appointment_id
            FOR UPDATE OF a
        LOOP
            replacement_slot := NULL;
            SELECT candidate.slot_id INTO replacement_slot
            FROM time_slots candidate
            JOIN doctors other_doctor ON other_doctor.doctor_id = candidate.doctor_id
            JOIN specialties sp ON sp.specialty_id = other_doctor.specialty_id
            WHERE other_doctor.doctor_id <> NEW.doctor_id
              AND other_doctor.is_active
              AND sp.is_active
              AND other_doctor.specialty_id = NEW.specialty_id
              AND (candidate.slot_date + candidate.start_time) > LOCALTIMESTAMP
              AND (candidate.slot_date + candidate.start_time) >=
                  (old_booking.slot_date + old_booking.start_time)
              AND NOT EXISTS (
                  SELECT 1 FROM appointments existing
                  WHERE existing.slot_id = candidate.slot_id
                    AND existing.status IN ('booked','completed')
              )
            ORDER BY candidate.slot_date, 
                     CASE WHEN candidate.slot_date = old_booking.slot_date THEN 0 ELSE 1 END,
                     ABS(EXTRACT(EPOCH FROM (candidate.start_time - old_booking.start_time))),
                     candidate.start_time, candidate.slot_id
            LIMIT 1
            FOR UPDATE OF candidate SKIP LOCKED;

            UPDATE appointments SET status = 'cancelled'
            WHERE appointment_id = old_booking.appointment_id;

            IF replacement_slot IS NOT NULL THEN
                -- Insert in the same transaction: failure rolls back deactivation.
                INSERT INTO appointments (patient_id, slot_id, status, reason)
                VALUES (old_booking.patient_id, replacement_slot, 'booked', old_booking.reason);
            END IF;
            -- No suitable slot: old booking remains cancelled, no invented replacement.
        END LOOP;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_cancel_future_bookings_on_deactivation ON doctors;
CREATE TRIGGER trg_cancel_future_bookings_on_deactivation
AFTER UPDATE OF is_active ON doctors
FOR EACH ROW EXECUTE FUNCTION cancel_future_bookings_on_deactivation();

-- Enforce the same policy even when an application calls the booking function directly.
-- Row lock on doctors serializes booking with deactivation.
CREATE OR REPLACE FUNCTION book_appointment(p_patient_id integer, p_slot_id integer, p_reason varchar DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
    v_start timestamp;
    v_doctor_id integer;
    v_active boolean;
    v_id integer;
BEGIN
    SELECT doctor_id INTO v_doctor_id FROM time_slots WHERE slot_id = p_slot_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Slot % does not exist', p_slot_id USING ERRCODE = 'P0002';
    END IF;
    SELECT is_active INTO v_active FROM doctors WHERE doctor_id = v_doctor_id FOR UPDATE;
    IF NOT v_active THEN
        RAISE EXCEPTION 'Doctor % is inactive', v_doctor_id USING ERRCODE = 'P0001';
    END IF;
    SELECT slot_date + start_time INTO v_start FROM time_slots WHERE slot_id = p_slot_id FOR UPDATE;
    IF v_start <= now() THEN
        RAISE EXCEPTION 'Slot % is in the past', p_slot_id USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM appointments WHERE slot_id = p_slot_id AND status IN ('booked','completed')) THEN
        RAISE EXCEPTION 'Slot % is already taken', p_slot_id USING ERRCODE = '23505';
    END IF;
    INSERT INTO appointments(patient_id, slot_id, reason)
    VALUES (p_patient_id, p_slot_id, p_reason)
    RETURNING appointment_id INTO v_id;
    RETURN v_id;
END $$;
