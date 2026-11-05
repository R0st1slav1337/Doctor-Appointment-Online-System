import { Component, inject, OnInit, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { AuthService } from '../../services/AuthService';

@Component({
  selector: 'app-me',
  standalone: true,
  template: `
    <h1>My Profile</h1>
    @if (profile(); as p) {
      <p>Email: {{ p.email }}</p>
      <p>Role: {{ p.role }}</p>
    } @else {
      <p>Loading...</p>
    }
  `
})
export class Me implements OnInit {
  private http = inject(HttpClient);
  private auth = inject(AuthService);
  private router = inject(Router);

  profile = signal<{ email: string; role: string } | null>(null);

  ngOnInit(): void {
    this.http.get<{ email: string; role: string }>('http://127.0.0.1:8000/api/me/').subscribe({
      next: (p) => this.profile.set(p),
      // token is not valid any more (for example the database was recreated): log in again
      error: () => {
        this.auth.logout();
        this.router.navigate(['/login']);
      }
    });
  }
}