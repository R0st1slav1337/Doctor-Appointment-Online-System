import { Component, inject, OnInit, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';

interface LoadRow {
  doctor_id: number;
  doctor_name: string;
  booked_appointments: number;
  total_slots: number;
}

@Component({
  selector: 'app-reports',
  standalone: true,
  templateUrl: './reports.html',
  styleUrl: '../admin-doctors/admin-doctors.css'
})
export class Reports implements OnInit {
  private http = inject(HttpClient);

  rows = signal<LoadRow[]>([]);
  errorMessage = signal('');

  ngOnInit(): void {
    this.http.get<LoadRow[]>('http://127.0.0.1:8000/api/reports/doctor-load/').subscribe({
      next: (rows) => this.rows.set(rows),
      error: () => this.errorMessage.set('Failed to load the report.')
    });
  }

  percent(row: LoadRow): number {
    return row.total_slots ? Math.round((100 * row.booked_appointments) / row.total_slots) : 0;
  }
}