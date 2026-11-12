import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { shareReplay } from 'rxjs';

export interface PhoneCountry {
  country_code: string;
  name: string;
  dial_code: string;
  min_digits: number;
  max_digits: number;
  example_mask: string | null;
}

@Injectable({ providedIn: 'root' })
export class PhoneService {
  private http = inject(HttpClient);

 
  readonly countries$ = this.http
    .get<PhoneCountry[]>('http://127.0.0.1:8000/api/phone-countries/')
    .pipe(shareReplay(1));


  flag(code: string | null | undefined): string {
    if (!code || code.length !== 2) {
      return '';
    }
    return String.fromCodePoint(...[...code.toUpperCase()].map((c) => 0x1f1a5 + c.charCodeAt(0)));
  }

  digits(value: string | null | undefined): string {
    return (value ?? '').replace(/\D/g, '');
  }

  lengthText(c: PhoneCountry): string {
    return c.min_digits === c.max_digits ? `${c.min_digits}` : `${c.min_digits}-${c.max_digits}`;
  }

  isValidLength(c: PhoneCountry | undefined, national: string): boolean {
    const n = this.digits(national).length;
    return !!c && n >= c.min_digits && n <= c.max_digits;
  }

  format(c: PhoneCountry | undefined, national: string): string {
    const d = this.digits(national);
    if (!c) {
      return d;
    }
    const prefix = '+' + c.dial_code;
    const mask = c.example_mask ?? '';
    const tail = mask.startsWith(prefix) ? mask.slice(prefix.length) : '';
    const slots = tail.replace(/\D/g, '').length;
    if (!tail || slots !== d.length) {
      return d ? `${prefix} ${d}` : prefix;
    }
    let i = 0;
    return prefix + tail.replace(/\d/g, () => d[i++]);
  }

  formatStored(c: PhoneCountry | undefined, e164: string): string {
    if (!c || !e164.startsWith('+' + c.dial_code)) {
      return e164;
    }
    return this.format(c, e164.slice(c.dial_code.length + 1));
  }
}
