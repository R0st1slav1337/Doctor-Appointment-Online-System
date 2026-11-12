# Online Doctor Appointment System

Angular (frontend) + Django REST Framework (backend) + PostgreSQL.

## Requirements
Python 3.12+, Node.js 20+, Angular CLI (`npm install -g @angular/cli`), PostgreSQL, Git.

## 1. Database
1. Create an empty database `clinic` (DataGrip or `psql -U postgres -c "CREATE DATABASE clinic"`).
2. Run in `clinic`, strictly in this order (each file as a whole script):
   `database/01_schema.sql`, `database/02_functions_views.sql`, `database/03_roles.sql` (optional), `database/04_seed.sql`.
   The app connects as `postgres`, so `03_roles.sql` is not required, but it must run after `02` if you use it.
3. Check: run `database/99_tests.sql`. It must end with `failed = 0`. Test data is rolled back.
4. For an existing database, preserve its records and apply the upgrade scripts that match its age:
   `database/05_migration_phone_reason.sql`, `database/06_migration_passwords.sql`, then
   `database/07_migration_weekly_schedules.sql`. These scripts are safe to re-run. A brand-new database
   should use steps 1-3 instead.

What the database does by itself:
- **Weekly schedules:** `weekly_schedules` holds one working period and an optional lunch break per doctor and weekday
  (Monday = 1 ... Sunday = 7). `generate_slots(from, to, slot_minutes)` creates `time_slots` from it; it skips lunch,
  inactive doctors and slots that already exist, so it is safe to run again.
- **Doctor deactivation:** doctors are never deleted, `is_active` is set to false. A trigger then cancels the doctor's
  future booked appointments and moves each patient to another active doctor of the same specialty (earliest slot, not
  earlier than the original one). If there is no such slot, the old booking stays cancelled. Past and completed
  appointments are kept. Booking an inactive doctor is rejected. Patients are not notified yet.
- **Phone:** stored as `+` and digits (E.164); the country is chosen from `phone_countries` and the length is checked per country.
- **Passwords:** never stored in the clinic tables. The only copy is a salted Argon2id hash in the Django login account
  (`auth_user.password`). Login: max 5 attempts per minute per IP (429 after that). Log out deletes the token on the server.

## 2. Backend
```
cd Backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
$env:DB_PASSWORD="your_postgres_password" # replace with YOUR PostgreSQL password (the one you use in DataGrip)
python manage.py migrate
python manage.py setup_roles
python manage.py runserver
```
Check: http://127.0.0.1:8000/api/doctors/
Demo logins (password `Clinic12345`): `a@mail.test` (patient), `a.nurtaeva@clinic.test` (doctor), `admin@clinic.test` (admin), `manager@clinic.test` (manager). Development only.
To create a new admin or manager, run `python manage.py create_staff`.

## 3. Frontend (second terminal)
```
cd Frontend
npm install
ng serve
```
Open http://localhost:4200 - you should see the list of doctors.

## Task 10: who did what
- Weekly doctor schedules with lunch break and slot generation (`weekly_schedules`, `generate_slots`) - Gulsezim
- Doctor deactivation with automatic rebooking - Zhanerke
- Phone with country selection and longer appointment reason - Amina
- Automatic refresh of the doctors list and free slots (every 30 seconds) - Altynai
- Role rules, README, merge of the above into one schema - Rostislav

## Task 11: who did what
- Password storage and account security (Argon2, one place for the hash, login attempt limit, server logout,
  password change), phone country on the frontend, profile with contacts and own appointments with the reason - Amina
  (`api/throttles.py`, `services/PhoneService.ts`, `pages/me`, `database/06_migration_passwords.sql`)

## Rules
- Do not commit passwords. Use `$env:DB_PASSWORD`.
- Models use `managed = False`: the database is created by the SQL files in `database/`, not by Django.
  To change a table, change the SQL and tell the team.
- Work in a branch (`git checkout -b feature/name`) and open a Pull Request into `main`.
- Roles of the system: see [ROLES.md](ROLES.md).
