
-- Task 10 - Gulsezim
-- Weekly working schedules for doctors

CREATE TABLE weekly_schedules (
    schedule_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id integer NOT NULL REFERENCES doctors(doctor_id),
    day_of_week integer NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_time time NOT NULL,
    end_time time NOT NULL,
    is_active boolean NOT NULL DEFAULT true,

    CONSTRAINT weekly_schedule_time_order
        CHECK (end_time > start_time),

    CONSTRAINT weekly_schedule_unique_day
        UNIQUE (doctor_id, day_of_week)
);

-- Monday = 1, Sunday = 7
-- One weekly working period per doctor per day
