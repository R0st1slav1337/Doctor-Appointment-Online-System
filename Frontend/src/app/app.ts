import { Component, inject, signal, OnInit } from '@angular/core';
import { DoctorService } from './services/DoctorService';

@Component({
  selector: 'app-root',
  imports: [],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App implements OnInit {
  private doctorService = inject(DoctorService);
  doctors = signal<any[]>([]);

  ngOnInit() {
    this.doctorService.getDoctors().subscribe(data => this.doctors.set(data));
  }
}
