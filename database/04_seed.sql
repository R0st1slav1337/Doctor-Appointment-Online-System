-- Fictional test data for development only. Dates are relative to today, so slots are always in the future.
INSERT INTO specialties(name, description) VALUES
 ('Therapist','General practice'),('Cardiologist','Heart and vessels'),('Dermatologist','Skin');

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

-- 4 half-hour slots per doctor for each of the next 5 days, starting 09:00
INSERT INTO time_slots(doctor_id, slot_date, start_time, end_time)
SELECT d.doctor_id, CURRENT_DATE + day, TIME '09:00' + n * INTERVAL '30 minutes', TIME '09:30' + n * INTERVAL '30 minutes'
FROM doctors d, generate_series(1,5) AS day, generate_series(0,3) AS n;

-- Some bookings (go through the same function the application will use)
SELECT book_appointment(1, (SELECT slot_id FROM time_slots WHERE doctor_id=1 ORDER BY slot_date, start_time LIMIT 1), 'Headache');
SELECT book_appointment(2, (SELECT slot_id FROM time_slots WHERE doctor_id=1 ORDER BY slot_date, start_time OFFSET 1 LIMIT 1), 'Check-up');
SELECT book_appointment(3, (SELECT slot_id FROM time_slots WHERE doctor_id=2 ORDER BY slot_date, start_time LIMIT 1), 'Chest pain');
