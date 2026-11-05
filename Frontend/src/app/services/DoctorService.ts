import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';

@Injectable({ providedIn: 'root' })
export class DoctorService {
  private http = inject(HttpClient);

  getDoctors() {
    return this.http.get<any[]>('http://127.0.0.1:8000/api/doctors/');
  }
  getFreeSlots() {
  return this.http.get<any[]>('http://127.0.0.1:8000/api/free-slots/');
}
}
