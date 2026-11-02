# Online Doctor Appointment System

Angular (frontend) + Django REST Framework (backend) + PostgreSQL.

## Requirements
Python 3.12+, Node.js 20+, Angular CLI (`npm install -g @angular/cli`), PostgreSQL, Git.

## 1. Database
1. Create an empty database `clinic` (DataGrip or `psql -U postgres -c "CREATE DATABASE clinic"`).
2. Run in `clinic`, in this order: `database/01_schema.sql`, `database/02_functions_views.sql`, `database/04_seed.sql`.
   (`03_roles.sql` is not used, we connect as `postgres`.)

## 2. Backend
```
cd Backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
$env:DB_PASSWORD="your_postgres_password" # replace with YOUR PostgreSQL password (the one you use in DataGrip)
python manage.py migrate
python manage.py runserver
```
Check: http://127.0.0.1:8000/api/doctors/

## 3. Frontend (second terminal)
```
cd Frontend
npm install
ng serve
```
Open http://localhost:4200 - you should see the list of doctors.

## Rules
- Do not commit passwords. Use `$env:DB_PASSWORD`.
- Models use `managed = False`: the database is created by the SQL files in `database/`, not by Django.
  To change a table, change the SQL and tell the team.
- Work in a branch (`git checkout -b feature/name`) and open a Pull Request into `main`.