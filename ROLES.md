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