-- Upgrade databases created before weekly schedules were added.
-- Safe to re-run. Existing doctor, appointment and slot rows are preserved.
BEGIN;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA extensions;
SET search_path = public, extensions;

CREATE TABLE IF NOT EXISTS weekly_schedules (
    schedule_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id integer NOT NULL REFERENCES doctors(doctor_id),
    day_of_week integer NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_time time NOT NULL,
    end_time time NOT NULL,
    lunch_start time,
    lunch_end time,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT weekly_schedule_time_order CHECK (end_time > start_time),
    CONSTRAINT weekly_schedule_lunch_pair CHECK (
        (lunch_start IS NULL AND lunch_end IS NULL)
        OR (lunch_start IS NOT NULL AND lunch_end IS NOT NULL)
    ),
    CONSTRAINT weekly_schedule_lunch_time CHECK (
        lunch_start IS NULL OR lunch_end > lunch_start
    ),
    CONSTRAINT weekly_schedule_lunch_inside CHECK (
        lunch_start IS NULL OR (lunch_start >= start_time AND lunch_end <= end_time)
    ),
    CONSTRAINT weekly_schedule_unique_day UNIQUE (doctor_id, day_of_week)
);

CREATE TABLE IF NOT EXISTS doctor_unavailability (
    unavailability_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id integer NOT NULL REFERENCES doctors(doctor_id),
    start_date date NOT NULL,
    end_date date NOT NULL,
    reason varchar(20) NOT NULL CHECK (reason IN ('vacation', 'sick_leave', 'day_off')),
    CONSTRAINT doctor_unavailability_date_order CHECK (end_date >= start_date),
    CONSTRAINT doctor_unavailability_no_overlap EXCLUDE USING gist (
        doctor_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    )
);

-- Existing doctors receive the same default schedule used by the administrator's add-doctor flow.
INSERT INTO weekly_schedules
    (doctor_id, day_of_week, start_time, end_time, lunch_start, lunch_end, is_active)
SELECT d.doctor_id, weekdays.day_of_week,
       TIME '09:00', TIME '18:00', TIME '13:00', TIME '14:00', true
FROM doctors d
CROSS JOIN generate_series(1, 5) AS weekdays(day_of_week)
WHERE d.is_active
ON CONFLICT (doctor_id, day_of_week) DO NOTHING;

CREATE OR REPLACE FUNCTION generate_slots(
    p_start_date date,
    p_end_date date,
    p_slot_minutes integer DEFAULT 30
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_schedule record;
    v_date date;
    v_start timestamp;
    v_end timestamp;
    v_lunch_start timestamp;
    v_lunch_end timestamp;
    v_created integer := 0;
    v_inserted integer;
BEGIN
    IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
        RAISE EXCEPTION 'Invalid date range';
    END IF;
    IF p_slot_minutes IS NULL OR p_slot_minutes <= 0 THEN
        RAISE EXCEPTION 'Slot duration must be positive';
    END IF;

    FOR v_schedule IN
        SELECT ws.*
        FROM weekly_schedules ws
        JOIN doctors d ON d.doctor_id = ws.doctor_id
        WHERE ws.is_active AND d.is_active
    LOOP
        FOR v_date IN
            SELECT generate_series(p_start_date::timestamp, p_end_date::timestamp, interval '1 day')::date
        LOOP
            IF EXTRACT(ISODOW FROM v_date) = v_schedule.day_of_week
               AND NOT EXISTS (
                   SELECT 1 FROM doctor_unavailability du
                   WHERE du.doctor_id = v_schedule.doctor_id
                     AND v_date BETWEEN du.start_date AND du.end_date
               )
            THEN
                v_start := v_date + v_schedule.start_time;
                v_end := v_date + v_schedule.end_time;
                IF v_schedule.lunch_start IS NOT NULL THEN
                    v_lunch_start := v_date + v_schedule.lunch_start;
                    v_lunch_end := v_date + v_schedule.lunch_end;
                ELSE
                    v_lunch_start := NULL;
                    v_lunch_end := NULL;
                END IF;

                WHILE v_start + make_interval(mins => p_slot_minutes) <= v_end LOOP
                    IF v_lunch_start IS NULL OR (
                        v_start + make_interval(mins => p_slot_minutes) <= v_lunch_start
                        OR v_start >= v_lunch_end
                    ) THEN
                        INSERT INTO time_slots (doctor_id, slot_date, start_time, end_time)
                        VALUES (
                            v_schedule.doctor_id,
                            v_date,
                            v_start::time,
                            (v_start + make_interval(mins => p_slot_minutes))::time
                        )
                        ON CONFLICT DO NOTHING;
                        GET DIAGNOSTICS v_inserted = ROW_COUNT;
                        v_created := v_created + v_inserted;
                    END IF;
                    v_start := v_start + make_interval(mins => p_slot_minutes);
                END LOOP;
            END IF;
        END LOOP;
    END LOOP;
    RETURN v_created;
END;
$$;

CREATE OR REPLACE VIEW v_free_slots AS
SELECT t.slot_id, t.doctor_id, d.full_name AS doctor_name, s.specialty_id,
       s.name AS specialty, d.consultation_fee_kzt, t.slot_date, t.start_time, t.end_time
FROM time_slots t
JOIN doctors d ON d.doctor_id = t.doctor_id AND d.is_active
JOIN specialties s ON s.specialty_id = d.specialty_id AND s.is_active
WHERE (t.slot_date + t.start_time) > now()
  AND NOT EXISTS (
      SELECT 1 FROM appointments a
      WHERE a.slot_id = t.slot_id AND a.status IN ('booked', 'completed')
  )
  AND NOT EXISTS (
      SELECT 1 FROM doctor_unavailability du
      WHERE du.doctor_id = t.doctor_id
        AND t.slot_date BETWEEN du.start_date AND du.end_date
  );

SELECT generate_slots(CURRENT_DATE + 1, CURRENT_DATE + 14, 30);
COMMIT;
