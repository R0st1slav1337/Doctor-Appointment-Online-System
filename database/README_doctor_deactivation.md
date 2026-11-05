# Zhanerke — Data & Database: doctor deactivation

Run `05_doctor_deactivation_zhanerke.sql` after `01_schema.sql` and `02_functions_views.sql` (and other project migrations). Run `05_doctor_deactivation_tests_zhanerke.sql` on a PostgreSQL test database. The test rolls back its data.

When `doctors.is_active` changes from true to false, a trigger cancels future booked appointments and creates replacement bookings with a different active doctor of the **same specialty**. It chooses the earliest available slot no earlier than the original appointment, preferring the closest time on the same date. If no eligible slot exists, the old booking is cancelled with no replacement. Completed and past appointments remain unchanged. New bookings with inactive doctors are rejected by `book_appointment`.

**Limitations:** This database-only change does not send notifications to patients or display replacement details in the frontend. Automatic reassignment assumes patients accept a later slot with another doctor. The clinic should review that policy before production use. Run the tests against your actual PostgreSQL installation; they have not been executed in this environment.

Upload the three files into `database/` on a feature branch, then open a pull request. Do not overwrite the team's other files.
