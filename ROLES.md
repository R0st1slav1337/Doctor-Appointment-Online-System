# Roles

Based on our Task 7 document.

| Role | What they do in the system |
|---|---|
| Guest | Sees doctors and free slots, can register |
| Patient | Books an appointment, writes the reason for the visit, cancels or reschedules own appointments, sees own appointments |
| Doctor | Sees own daily list of patients and the reason notes, works with own schedule together with the administrator |
| Clinic Administrator | Creates and updates doctor profiles and schedules, changes or cancels any appointment, deactivates doctors, fixes wrong records (data owner of Appointment Bookings) |
| Manager | Read-only reports: number of appointments, doctor load, cancellations |
| System | The booking application: creates the appointment after the patient confirms, marks the slot as busy, sends confirmation and reminder |

| Action | Guest | Patient | Doctor | Administrator | Manager |
|---|---|---|---|---|---|
| See doctors and free slots | yes | yes | yes | yes | yes |
| Register an account | yes | - | - | - | - |
| Book an appointment | - | yes | - | yes (for a patient) | - |
| Cancel or reschedule an appointment | - | own only | - | any | - |
| See appointments | - | own | own patients | all | statistics only |
| See the reason note | - | own | own patients | yes | no |
| Edit doctor schedule | - | - | own hours | yes | - |
| Create or deactivate doctors | - | - | - | yes | - |
| See reports | - | - | - | yes | yes |

Rules:
- An appointment is created or changed only by the booking application (after the patient confirms) or by an administrator with a personal login.
- The status of an appointment is changed only by the system or an administrator, and every change is logged.
- Before saving, the system checks that Patient ID, Doctor ID and Slot start are filled and valid, the slot is free, and there is no duplicate.
- Nothing is deleted: doctors are deactivated, appointments get the status `cancelled`.
- The role is checked in the backend on every request.


## How accounts are created
| Role | How the account is created |
|---|---|
| Patient | Registers on the site. The role is set by the server and cannot be chosen. |
| Doctor | Added by the administrator on the site ("Manage doctors"); the doctor gets a default weekly schedule. |
| Administrator, Manager | Only by the server administrator in the console: `python manage.py create_staff <email> <admin or manager>`. There is no way to create them from the site or the API. |

Limits (checked in the backend on every request, covered by `python manage.py test`):
- Patient, doctor and manager cannot use administrator functions (403); a visitor without login gets 401.
- Manager is read-only: sees the doctor load report (numbers only, no patient data and no reasons for the visit) and nothing that changes data.
- The role is assigned only by the server: a registration request with a `role` field is ignored.