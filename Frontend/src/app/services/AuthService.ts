import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpInterceptorFn } from '@angular/common/http';
import { CanActivateFn, Router } from '@angular/router';
import { tap } from 'rxjs';

const API = 'http://127.0.0.1:8000/api';

export interface Session {
  token: string;
  email: string;
  role: string;
}

export interface RegisterForm {
  full_name: string;
  email: string;
  birth_date: string;
  phone_country: string;
  phone: string;
  password: string;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);

  token = signal<string | null>(localStorage.getItem('token'));
  email = signal<string | null>(localStorage.getItem('email'));
  role = signal<string | null>(localStorage.getItem('role'));

  isLoggedIn() {
    return this.token() !== null;
  }

  private saveSession(res: Session) {
    localStorage.setItem('token', res.token);
    localStorage.setItem('email', res.email);
    localStorage.setItem('role', res.role);
    this.token.set(res.token);
    this.email.set(res.email);
    this.role.set(res.role);
  }

  login(email: string, password: string) {
    return this.http
      .post<Session>(`${API}/login/`, { email, password })
      .pipe(tap((res) => this.saveSession(res)));
  }

  register(form: RegisterForm) {
    return this.http
      .post<Session>(`${API}/register/`, form)
      .pipe(tap((res) => this.saveSession(res)));
  }

  logout() {
    const token = this.token();
    if (token) {
      this.http
        .post(`${API}/logout/`, {}, { headers: { Authorization: `Token ${token}` } })
        .subscribe({ error: () => {} });
    }
    this.clearSession();
  }

  changePassword(oldPassword: string, newPassword: string) {
    return this.http
      .post<Session>(`${API}/me/password/`, { old_password: oldPassword, new_password: newPassword })
      .pipe(tap((res) => this.saveSession(res)));
  }

  clearSession() {
    localStorage.removeItem('token');
    localStorage.removeItem('email');
    localStorage.removeItem('role');
    this.token.set(null);
    this.email.set(null);
    this.role.set(null);
  }
}

// Adds "Authorization: Token ..." to every request to our API, so later pages do not need to care about it.
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const token = localStorage.getItem('token');
  if (token && req.url.startsWith(API)) {
    req = req.clone({ setHeaders: { Authorization: `Token ${token}` } });
  }
  return next(req);
};

// Closes a page for everybody except the listed roles. The backend still checks the role too.
export function roleGuard(...roles: string[]): CanActivateFn {
  return () => {
    const auth = inject(AuthService);
    const router = inject(Router);
    if (!auth.isLoggedIn()) {
      return router.createUrlTree(['/login']);
    }
    if (!roles.includes(auth.role() ?? '')) {
      return router.createUrlTree(['/']);
    }
    return true;
  };
}