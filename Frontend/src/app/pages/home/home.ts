import { Component, computed, inject, OnDestroy, OnInit, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { EMPTY, Subscription, catchError, switchMap, tap, timer } from 'rxjs';
import { DoctorService } from '../../services/DoctorService';
import { DatePipe } from '@angular/common';
import { AuthService } from '../../services/AuthService';
// Task 10 - Altynai: data refreshes automatically every 30 seconds
@Component({
  selector: 'app-home',
  standalone: true,
  imports: [RouterLink, DatePipe],
  templateUrl: './home.html',
  styleUrl: './home.css'
})
export class Home implements OnInit, OnDestroy {
  private doctorService = inject(DoctorService);
  auth = inject(AuthService);
  private refreshSubscription?: Subscription;

  doctors = signal<any[]>([]);
  searchTerm = signal('');
  selectedSpecialty = signal('');
  specialties = computed(() => [...new Set(this.doctors()
    .map((doctor) => doctor.specialty_name)
    .filter((specialty): specialty is string => Boolean(specialty)))].sort((a, b) => a.localeCompare(b)));
  filteredDoctors = computed(() => {
    const query = this.searchTerm().trim().toLocaleLowerCase();
    const specialty = this.selectedSpecialty();
    return this.doctors().filter((doctor) => {
      const matchesName = !query || doctor.full_name.toLocaleLowerCase().includes(query);
      const matchesSpecialty = !specialty || doctor.specialty_name === specialty;
      return matchesName && matchesSpecialty;
    });
  });
  lastUpdated = signal<Date | null>(null);
  errorMessage = signal('');

  ngOnInit(): void {
    this.refreshSubscription = timer(0, 30_000)
      .pipe(
        switchMap(() =>
          this.doctorService.getDoctors().pipe(
            tap((doctors) => {
              this.doctors.set(doctors);
              this.lastUpdated.set(new Date());
              this.errorMessage.set('');
            }),
            catchError(() => {
              this.errorMessage.set('Не удалось загрузить список врачей.');
              return EMPTY;
            })
          )
        )
      )
      .subscribe();
  }

  ngOnDestroy(): void {
    this.refreshSubscription?.unsubscribe();
  }
}
