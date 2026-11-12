import { DatePipe, SlicePipe } from '@angular/common';
import { Component, computed, inject, OnDestroy, OnInit, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { EMPTY, Subscription, catchError, switchMap, tap, timer } from 'rxjs';
import { DoctorService } from '../../services/DoctorService';
import { AuthService } from '../../services/AuthService';

interface FreeSlot {
  slot_id: number;
  doctor_id: number;
  doctor_name: string;
  specialty: string;
  consultation_fee_kzt: number;
  slot_date: string;
  start_time: string;
  end_time: string;
}

interface DayGroup {
  date: string;
  slots: FreeSlot[];
}

interface DoctorGroup {
  doctor_id: number;
  doctor_name: string;
  specialty: string;
  days: DayGroup[];
}

@Component({
  selector: 'app-free-slots',
  standalone: true,
  imports: [DatePipe, SlicePipe, RouterLink, FormsModule],
  templateUrl: './free-slots.html',
  styleUrl: './free-slots.css'
})
export class FreeSlots implements OnInit, OnDestroy {
  private doctorService = inject(DoctorService);
  private route = inject(ActivatedRoute);
  auth = inject(AuthService);
  private refreshSubscription?: Subscription;

  freeSlots = signal<FreeSlot[]>([]);
  selectedDoctorId = signal<number | null>(null);
  selectedDoctor = signal<{ full_name: string; specialty_name: string } | null>(null);
  doctorGroups = computed<DoctorGroup[]>(() => {
    const byDoctor = new Map<number, FreeSlot[]>();
    for (const slot of this.freeSlots()) {
      const current = byDoctor.get(slot.doctor_id) ?? [];
      current.push(slot);
      byDoctor.set(slot.doctor_id, current);
    }

    return [...byDoctor.entries()]
      .map(([doctorId, slots]) => {
        const byDay = new Map<string, FreeSlot[]>();
        for (const slot of slots) {
          const sameDay = byDay.get(slot.slot_date) ?? [];
          sameDay.push(slot);
          byDay.set(slot.slot_date, sameDay);
        }
        const first = slots[0];
        return {
          doctor_id: doctorId,
          doctor_name: first.doctor_name,
          specialty: first.specialty,
          days: [...byDay.entries()]
            .sort(([dateA], [dateB]) => dateA.localeCompare(dateB))
            .map(([date, daySlots]) => ({
              date,
              slots: daySlots.sort((a, b) => a.start_time.localeCompare(b.start_time))
            }))
        };
      })
      .sort((a, b) => a.doctor_name.localeCompare(b.doctor_name));
  });
  lastUpdated = signal<Date | null>(null);
  errorMessage = signal('');
  successMessage = signal('');
  selectedSlotId = signal<number | null>(null);
  bookingSlotId = signal<number | null>(null);
  visitReason = '';

  ngOnInit(): void {
    const doctorId = Number(this.route.snapshot.queryParamMap.get('doctorId'));
    if (Number.isSafeInteger(doctorId) && doctorId > 0) {
      this.selectedDoctorId.set(doctorId);
      this.doctorService.getDoctors().subscribe({
        next: (doctors) => {
          const doctor = doctors.find((item) => item.doctor_id === doctorId);
          if (doctor) {
            this.selectedDoctor.set({
              full_name: doctor.full_name,
              specialty_name: doctor.specialty_name
            });
          }
        }
      });
    }

    this.refreshSubscription = timer(0, 30_000)
      .pipe(
        switchMap(() =>
          this.doctorService.getFreeSlots().pipe(
            tap((slots) => {
              this.freeSlots.set(this.forSelectedDoctor(slots));
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

  selectSlot(slotId: number): void {
    this.successMessage.set('');
    this.errorMessage.set('');
    this.visitReason = '';
    this.selectedSlotId.set(slotId);
  }

  bookSelectedSlot(): void {
    const slotId = this.selectedSlotId();
    if (slotId === null || this.bookingSlotId() !== null) return;

    this.errorMessage.set('');
    this.successMessage.set('');
    this.bookingSlotId.set(slotId);
    this.doctorService.bookAppointment(slotId, this.visitReason).subscribe({
      next: () => {
        this.bookingSlotId.set(null);
        this.selectedSlotId.set(null);
        this.successMessage.set('Запись создана и подтверждена. Вы увидите её в профиле.');
        this.visitReason = '';
        this.refreshSlots();
      },
      error: (error) => {
        this.bookingSlotId.set(null);
        this.errorMessage.set(error.error?.detail ?? 'Не удалось создать запись. Попробуйте ещё раз.');
      }
    });
  }

  private refreshSlots(): void {
    this.doctorService.getFreeSlots().subscribe({
      next: (slots) => {
        this.freeSlots.set(this.forSelectedDoctor(slots));
        this.lastUpdated.set(new Date());
      }
    });
  }

  private forSelectedDoctor(slots: FreeSlot[]): FreeSlot[] {
    const doctorId = this.selectedDoctorId();
    return doctorId ? slots.filter((slot) => slot.doctor_id === doctorId) : slots;
  }
}
