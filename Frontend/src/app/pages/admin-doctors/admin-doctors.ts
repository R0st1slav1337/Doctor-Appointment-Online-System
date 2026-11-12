import { Component, inject, OnInit, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';

const API = 'http://127.0.0.1:8000/api';

interface Specialty {
  specialty_id: number;
  name: string;
}

interface AdminDoctor {
  doctor_id: number;
  full_name: string;
  email: string;
  specialty: string;
  room_number: string | null;
  consultation_fee_kzt: number;
  is_active: boolean;
}

interface AdminAppointment {
  appointment_id: number;
  patient_name: string;
  doctor_name: string;
  specialty: string;
  slot_date: string;
  start_time: string;
  end_time: string;
  reason: string | null;
}

@Component({
  selector: 'app-admin-doctors',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './admin-doctors.html',
  styleUrl: './admin-doctors.css'
})
export class AdminDoctors implements OnInit {
  private http = inject(HttpClient);

  specialties = signal<Specialty[]>([]);
  doctors = signal<AdminDoctor[]>([]);
  appointments = signal<AdminAppointment[]>([]);
  errorMessage = signal('');
  successMessage = signal('');
  loading = signal(false);

  fullName = '';
  email = '';
  specialtyId: number | null = null;
  room = '';
  fee: number | null = null;
  password = '';

  ngOnInit(): void {
    this.http.get<Specialty[]>(`${API}/specialties/`).subscribe({
      next: (list) => this.specialties.set(list),
      error: () => this.errorMessage.set('Failed to load specialties.')
    });
    this.loadDoctors();
    this.loadAppointments();
  }

  loadDoctors() {
    this.http.get<AdminDoctor[]>(`${API}/admin/doctors/`).subscribe({
      next: (list) => this.doctors.set(list),
      error: () => this.errorMessage.set('Failed to load doctors.')
    });
  }

  loadAppointments() {
    this.http.get<AdminAppointment[]>(`${API}/admin/appointments/`).subscribe({
      next: (list) => this.appointments.set(list),
      error: () => this.errorMessage.set('Failed to load appointments.')
    });
  }

  cancelAppointment(appointmentId: number) {
    if (!window.confirm('Cancel this appointment?')) return;
    this.errorMessage.set('');
    this.successMessage.set('');
    this.http.post(`${API}/admin/appointments/`, { appointment_id: appointmentId }).subscribe({
      next: () => {
        this.successMessage.set('Appointment cancelled by administrator.');
        this.loadAppointments();
      },
      error: (err) => this.errorMessage.set(err.error?.detail ?? 'Failed to cancel appointment.')
    });
  }

  submit() {
    this.errorMessage.set('');
    this.successMessage.set('');
    this.loading.set(true);
    this.http
      .post<{ doctor_id: number; email: string; slots_created: number }>(`${API}/admin/doctors/`, {
        full_name: this.fullName,
        email: this.email,
        specialty_id: this.specialtyId,
        room_number: this.room,
        consultation_fee_kzt: this.fee,
        password: this.password
      })
      .subscribe({
        next: (res) => {
          this.loading.set(false);
          this.successMessage.set(
            `Doctor added. Login: ${res.email}. Schedule: Mon-Fri 09:00-18:00, lunch 13:00-14:00, ${res.slots_created} slots for the next 14 days.`
          );
          this.fullName = '';
          this.email = '';
          this.specialtyId = null;
          this.room = '';
          this.fee = null;
          this.password = '';
          this.loadDoctors();
        },
        error: (err) => {
          this.loading.set(false);
          this.errorMessage.set(
            err.status === 403
              ? 'Only the administrator can add doctors.'
              : err.error?.detail ?? 'Failed to connect to the server.'
          );
        }
      });
  }
}
