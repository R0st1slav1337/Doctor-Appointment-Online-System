import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../services/AuthService';
import { PhoneCountry, PhoneService } from '../../services/PhoneService';

@Component({
  selector: 'app-register',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './register.html',
  styleUrls: ['../login/login.css', './register.css']
})
export class Register implements OnInit {
  phones = inject(PhoneService);
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
  showPassword = signal(false);

  ngOnInit(): void {
    this.phones.countries$.subscribe({
      next: (list) => this.countries.set(list),
      error: () => this.errorMessage.set('Failed to load the list of countries.')
    });
  }

  selectedCountry(): PhoneCountry | undefined {
    return this.countries().find((c) => c.country_code === this.phoneCountry);
  }

  phoneOk(): boolean {
    return this.phones.isValidLength(this.selectedCountry(), this.phone);
  }

  // the example number of the country without its code, e.g. "(701) 123-45-67"
  placeholder(): string {
    const c = this.selectedCountry();
    if (!c?.example_mask) {
      return '';
    }
    return c.example_mask.replace('+' + c.dial_code, '').trim();
  }

  submit() {
    this.errorMessage.set('');
    // the same length check as on the server - just to show the error earlier
    const c = this.selectedCountry();
    if (c && !this.phoneOk()) {
      this.errorMessage.set(`For ${c.name} enter ${this.phones.lengthText(c)} digits without the country code.`);
      return;
    }
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