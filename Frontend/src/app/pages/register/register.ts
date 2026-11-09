import { Component, inject, OnInit, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../services/AuthService';

interface PhoneCountry {
  country_code: string;
  name: string;
  dial_code: string;
  min_digits: number;
  max_digits: number;
  example_mask: string | null;
}

@Component({
  selector: 'app-register',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './register.html',
  styleUrl: '../login/login.css'
})
export class Register implements OnInit {
  private http = inject(HttpClient);
  private auth = inject(AuthService);
  private router = inject(Router);

  countries = signal<PhoneCountry[]>([]);
  fullName = '';
  email = '';
  birthDate = '';
  phoneCountry = 'KZ';
  phone = ''; // the number WITHOUT the country code; the server adds "+" and the dial code
  password = '';
  password2 = '';
  today = new Date().toISOString().slice(0, 10); // the latest possible date of birth (max of the date input)
  errorMessage = signal('');
  loading = signal(false);

  ngOnInit(): void {
    this.http.get<PhoneCountry[]>('http://127.0.0.1:8000/api/phone-countries/').subscribe({
      next: (list) => this.countries.set(list),
      error: () => this.errorMessage.set('Failed to load the list of countries.')
    });
  }

  selectedCountry(): PhoneCountry | undefined {
    return this.countries().find((c) => c.country_code === this.phoneCountry);
  }

  submit() {
    this.errorMessage.set('');
    // the repeated password is checked only here: the server receives one password
    if (this.password !== this.password2) {
      this.errorMessage.set('Passwords do not match.');
      return;
    }
    this.loading.set(true);
    this.auth
      .register({
        full_name: this.fullName,
        email: this.email,
        birth_date: this.birthDate,
        phone_country: this.phoneCountry,
        phone: this.phone,
        password: this.password
      })
      .subscribe({
        next: () => {
          this.loading.set(false);
          this.router.navigate(['/']);
        },
        error: (err) => {
          this.loading.set(false);
          this.errorMessage.set(err.error?.detail ?? 'Failed to connect to the server.');
        }
      });
  }
}