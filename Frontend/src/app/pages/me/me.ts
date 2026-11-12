import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../services/AuthService';
import { PhoneCountry, PhoneService } from '../../services/PhoneService';

const API = 'http://127.0.0.1:8000/api';

interface Contacts {
  full_name: string;
  email: string;
  phone: string; // E.164: +77011234567
  phone_country: PhoneCountry;
  birth_date: string;
}

interface Profile {
  email: string;
  role: string;
  contacts?: Contacts; // only for a patient
  doctor?: { full_name: string; specialty: string; room_number: string | null };
}

interface Appointment {
  appointment_id: number;
  status: string;
  reason: string | null;
  slot_date: string;
  start_time: string;
  end_time: string;
  doctor_name: string;
  specialty: string;
  room_number: string | null;
}

@Component({
  selector: 'app-me',
  standalone: true,
  imports: [FormsModule, DatePipe],
  templateUrl: './me.html',
  styleUrl: './me.css'
})
export class Me implements OnInit {
  private http = inject(HttpClient);
  private auth = inject(AuthService);
  private router = inject(Router);
  phones = inject(PhoneService);

  profile = signal<Profile | null>(null);
  profileLoading = signal(true);
  profileError = signal('');
  appointments = signal<Appointment[]>([]);
  appointmentNotice = signal('');
  appointmentError = signal('');
  cancellingAppointmentId = signal<number | null>(null);
  countries = signal<PhoneCountry[]>([]);

  // edit phone
  editingPhone = signal(false);
  editCountry = 'KZ';
  editPhone = '';
  phoneError = signal('');
  phoneSaved = signal(false);

  // change password
  oldPassword = '';
  newPassword = '';
  newPassword2 = '';
  passwordError = signal('');
  passwordSaved = signal(false);
  savingPassword = signal(false);

  contacts = computed(() => this.profile()?.contacts);

  ngOnInit(): void {
    this.loadProfile();
  }

  loadProfile(): void {
    this.profileLoading.set(true);
    this.profileError.set('');
    this.http.get<Profile>(`${API}/me/profile/`).subscribe({
      next: (p) => {
        this.profileLoading.set(false);
        this.profile.set(p);
        if (p.role === 'patient') {
          this.loadAppointments();
          this.phones.countries$.subscribe((list) => this.countries.set(list));
        }
      },
      error: (error) => {
        this.profileLoading.set(false);
        if (error.status === 401) {
          this.auth.clearSession();
          this.router.navigate(['/login']);
          return;
        }
        this.profileError.set(
          error.status === 0
            ? 'Cannot reach the server. Your login is still saved; check that the backend is running and retry.'
            : 'Could not load your profile. Your login is still saved; please retry.'
        );
      }
    });
  }

  private loadAppointments() {
    this.http.get<Appointment[]>(`${API}/me/appointments/`).subscribe((list) => this.appointments.set(list));
  }

  cancelAppointment(appointmentId: number) {
    if (!window.confirm('Cancel this appointment?')) return;
    this.appointmentNotice.set('');
    this.appointmentError.set('');
    this.cancellingAppointmentId.set(appointmentId);
    this.http.post(`${API}/me/appointments/cancel/`, { appointment_id: appointmentId }).subscribe({
      next: () => {
        this.cancellingAppointmentId.set(null);
        this.appointmentNotice.set('Your appointment was cancelled.');
        this.loadAppointments();
      },
      error: (err) => {
        this.cancellingAppointmentId.set(null);
        this.appointmentError.set(err.error?.detail ?? 'Failed to cancel the appointment.');
      }
    });
  }

  phoneText(c: Contacts): string {
    return this.phones.formatStored(c.phone_country, c.phone);
  }

  editCountryObj(): PhoneCountry | undefined {
    return this.countries().find((c) => c.country_code === this.editCountry);
  }

  startEditPhone() {
    const c = this.contacts();
    if (!c) {
      return;
    }
    this.editCountry = c.phone_country.country_code;
    this.editPhone = c.phone.slice(c.phone_country.dial_code.length + 1); // without "+" and the code
    this.phoneError.set('');
    this.phoneSaved.set(false);
    this.editingPhone.set(true);
  }

  savePhone() {
    const c = this.editCountryObj();
    if (c && !this.phones.isValidLength(c, this.editPhone)) {
      this.phoneError.set(`For ${c.name} enter ${this.phones.lengthText(c)} digits without the country code.`);
      return;
    }
    this.http
      .patch<Profile>(`${API}/me/profile/`, { phone_country: this.editCountry, phone: this.editPhone })
      .subscribe({
        next: (p) => {
          this.profile.set(p);
          this.editingPhone.set(false);
          this.phoneSaved.set(true);
        },
        error: (err) => this.phoneError.set(err.error?.detail ?? 'Failed to save the phone.')
      });
  }

  changePassword() {
    this.passwordError.set('');
    this.passwordSaved.set(false);
    if (this.newPassword !== this.newPassword2) {
      this.passwordError.set('New passwords do not match.');
      return;
    }
    this.savingPassword.set(true);
    this.auth.changePassword(this.oldPassword, this.newPassword).subscribe({
      next: () => {
        this.savingPassword.set(false);
        this.passwordSaved.set(true);
        this.oldPassword = this.newPassword = this.newPassword2 = '';
      },
      error: (err) => {
        this.savingPassword.set(false);
        this.passwordError.set(err.error?.detail ?? 'Failed to change the password.');
      }
    });
  }
}
