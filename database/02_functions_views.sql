-- Business logic that the application calls. Keeps multi-step rules inside ONE transaction.
-- Note on transactions: a PostgreSQL function runs inside the caller's transaction and cannot
-- contain COMMIT/ROLLBACK itself. If the function finishes, the caller's COMMIT saves everything;
-- if any statement raises an error, everything the function did is rolled back automatically.

-- Free slots: future slots of active doctors that have no active appointment.
CREATE OR REPLACE VIEW v_free_slots AS
SELECT t.slot_id, t.doctor_id, d.full_name AS doctor_name, s.specialty_id, s.name AS specialty,
       d.consultation_fee_kzt, t.slot_date, t.start_time, t.end_time
FROM time_slots t
JOIN doctors d     ON d.doctor_id = t.doctor_id AND d.is_active
JOIN specialties s ON s.specialty_id = d.specialty_id AND s.is_active
WHERE (t.slot_date + t.start_time) > now()
  AND NOT EXISTS (SELECT 1 FROM appointments a
                  WHERE a.slot_id = t.slot_id AND a.status IN ('booked', 'completed'));

-- Doctor load: active bookings per doctor per day (for the manager's decision).
CREATE OR REPLACE VIEW v_doctor_load AS
SELECT d.doctor_id, d.full_name AS doctor_name, t.slot_date,
       count(*) FILTER (WHERE a.status = 'booked') AS booked_appointments,
       count(DISTINCT t.slot_id)                   AS total_slots
FROM doctors d
JOIN time_slots t ON t.doctor_id = d.doctor_id
LEFT JOIN appointments a ON a.slot_id = t.slot_id
GROUP BY d.doctor_id, d.full_name, t.slot_date;

-- Book a slot. Raises a clear error if the slot is missing, in the past, or already taken.
CREATE OR REPLACE FUNCTION book_appointment(p_patient_id integer, p_slot_id integer, p_reason varchar DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
    v_start timestamp;
    v_id    integer;
BEGIN
    -- lock the slot row so two parallel requests are handled one after another
    SELECT slot_date + start_time INTO v_start FROM time_slots WHERE slot_id = p_slot_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Slot % does not exist', p_slot_id USING ERRCODE = 'P0002';
    END IF;
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

-- Cancel an appointment (only the owner patient can cancel a booked one).
CREATE OR REPLACE FUNCTION cancel_appointment(p_appointment_id integer, p_patient_id integer)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE appointments SET status = 'cancelled'
    WHERE appointment_id = p_appointment_id AND patient_id = p_patient_id AND status = 'booked';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booked appointment % of patient % not found', p_appointment_id, p_patient_id
              USING ERRCODE = 'P0002';
    END IF;
END $$;

-- Reschedule = cancel old + book new, all or nothing.
-- If the new slot is taken, the whole function fails and the old appointment stays booked.
CREATE OR REPLACE FUNCTION reschedule_appointment(p_appointment_id integer, p_patient_id integer, p_new_slot_id integer)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
    v_reason varchar;
BEGIN
    SELECT reason INTO v_reason FROM appointments
    WHERE appointment_id = p_appointment_id AND patient_id = p_patient_id AND status = 'booked' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booked appointment % of patient % not found', p_appointment_id, p_patient_id
              USING ERRCODE = 'P0002';
    END IF;
    PERFORM cancel_appointment(p_appointment_id, p_patient_id);      -- step 1
    RETURN book_appointment(p_patient_id, p_new_slot_id, v_reason);   -- step 2 (error here undoes step 1)
END $$;
