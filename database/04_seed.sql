
-- Fictional test data for development only.
-- Task 10: Weekly doctor schedules and automatic slot generation.

INSERT INTO specialties(name, description) VALUES
 ('Therapist','General practice'),
 ('Cardiologist','Heart and vessels'),
 ('Dermatologist','Skin');

INSERT INTO doctors(specialty_id, full_name, email, room_number, consultation_fee_kzt) VALUES
 (1,'Dr. Aigerim Nurtaeva','a.nurtaeva@clinic.test','101',8000),
 (2,'Dr. Marat Sadykov','m.sadykov@clinic.test','204',12000),
 (3,'Dr. Dana Omarova','d.omarova@clinic.test','305',10000);

-- password_hash below is a placeholder, NOT a real hash
INSERT INTO patients(full_name, email, phone, birth_date, password_hash) VALUES
 ('Test Patient A','a@mail.test','+77010000001','2001-03-14','placeholder'),
 ('Test Patient B','b@mail.test','+77010000002','1995-07-02','placeholder'),
 ('Test Patient C','c@mail.test','+77010000003','1988-11-23','placeholder'),
 ('Test Patient D','d@mail.test','+77010000004','2003-01-30','placeholder');

-- patients with a non-Kazakhstan phone (country is chosen in the phone input)
INSERT INTO patients(full_name, email, phone_country, phone, birth_date, password_hash) VALUES
 ('Test Patient E','e@mail.test','UZ','+998901234567','1999-05-10','placeholder'),
 ('Test Patient F','f@mail.test','KG','+996555123456','1992-09-18','placeholder');

-- Task 10 - Gulsezim
-- Weekly schedules for three doctors.
-- Monday = 1, Friday = 5.
-- Working hours: 09:00-18:00.
-- Lunch break: 13:00-14:00.

INSERT INTO weekly_schedules (
    doctor_id,
    day_of_week,
    start_time,
    end_time,
    lunch_start,
    lunch_end,
    is_active
)
SELECT
    d.doctor_id,
    days.day_of_week,
    TIME '09:00',
    TIME '18:00',
    TIME '13:00',
    TIME '14:00',
    true
FROM doctors d
CROSS JOIN generate_series(1, 5) AS days(day_of_week);

-- Task 11 - Gulsezim
-- Test absences for three doctors.
-- The next Monday is always in the future.

-- Doctor 1: sick leave on the next Monday.
INSERT INTO doctor_unavailability (
    doctor_id, start_date, end_date, reason
)
SELECT
    1,
    CURRENT_DATE + (8 - EXTRACT(ISODOW FROM CURRENT_DATE)::integer),
    CURRENT_DATE + (8 - EXTRACT(ISODOW FROM CURRENT_DATE)::integer),
    'sick_leave';

-- Doctor 2: vacation on Tuesday and Wednesday.
INSERT INTO doctor_unavailability (
    doctor_id, start_date, end_date, reason
)
SELECT
    2,
    CURRENT_DATE + (9 - EXTRACT(ISODOW FROM CURRENT_DATE)::integer),
    CURRENT_DATE + (10 - EXTRACT(ISODOW FROM CURRENT_DATE)::integer),
    'vacation';

-- Doctor 3: extra day off on Friday.
INSERT INTO doctor_unavailability (
    doctor_id, start_date, end_date, reason
)
SELECT
    3,
    CURRENT_DATE + (12 - EXTRACT(ISODOW FROM CURRENT_DATE)::integer),
    CURRENT_DATE + (12 - EXTRACT(ISODOW FROM CURRENT_DATE)::integer),
    'day_off';

-- Automatically generate 30-minute appointment slots
-- for the next 14 days, starting tomorrow.
-- Weekends, lunch breaks and doctor absences are excluded.

SELECT generate_slots(
    CURRENT_DATE + 1,
    CURRENT_DATE + 14,
    30
);

-- Some bookings (go through the same function the application will use)
SELECT book_appointment(
    1,
    (SELECT slot_id
     FROM time_slots
     WHERE doctor_id = 1
     ORDER BY slot_date, start_time
     LIMIT 1),
    'Headache'
);

SELECT book_appointment(
    2,
    (SELECT slot_id
     FROM time_slots
     WHERE doctor_id = 1
     ORDER BY slot_date, start_time
     OFFSET 1 LIMIT 1),
    'Check-up'
);

SELECT book_appointment(
    3,
    (SELECT slot_id
     FROM time_slots
     WHERE doctor_id = 2
     ORDER BY slot_date, start_time
     LIMIT 1),
    'Chest pain'
);
