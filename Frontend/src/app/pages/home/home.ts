import { Component, inject, OnDestroy, OnInit, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { EMPTY, Subscription, catchError, switchMap, tap, timer } from 'rxjs';
import { DoctorService } from '../../services/DoctorService';
import { DatePipe } from '@angular/common';
@Component({
  selector: 'app-home',
  standalone: true,
  imports: [RouterLink, DatePipe],
  templateUrl: './home.html',
  styleUrl: './home.css'
})
export class Home implements OnInit, OnDestroy {
  private doctorService = inject(DoctorService);
  private refreshSubscription?: Subscription;

  doctors = signal<any[]>([]);
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