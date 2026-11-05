import { DatePipe } from '@angular/common';
import { Component, inject, OnDestroy, OnInit, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { EMPTY, Subscription, catchError, switchMap, tap, timer } from 'rxjs';
import { DoctorService } from '../../services/DoctorService';

@Component({
  selector: 'app-free-slots',
  standalone: true,
  imports: [DatePipe, RouterLink],
  templateUrl: './free-slots.html',
  styleUrl: './free-slots.css'
})
export class FreeSlots implements OnInit, OnDestroy {
  private doctorService = inject(DoctorService);
  private route = inject(ActivatedRoute);
  private refreshSubscription?: Subscription;

  freeSlots = signal<any[]>([]);
  lastUpdated = signal<Date | null>(null);
  errorMessage = signal('');

  ngOnInit(): void {
    this.refreshSubscription = timer(0, 30_000)
      .pipe(
        switchMap(() =>
          this.doctorService.getFreeSlots().pipe(
            tap((slots) => {
              const doctorId = Number(
                this.route.snapshot.queryParamMap.get('doctorId')
              );

              const visibleSlots = doctorId
                ? slots.filter((slot) => slot.doctor_id === doctorId)
                : slots;

              this.freeSlots.set(visibleSlots);
              this.lastUpdated.set(new Date());
              this.errorMessage.set('');
            }),
            catchError(() => {
              this.errorMessage.set('Не удалось загрузить свободные слоты.');
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