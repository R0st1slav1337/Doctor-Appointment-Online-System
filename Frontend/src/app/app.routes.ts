import { Routes } from '@angular/router';
import { Home } from './pages/home/home';
import { FreeSlots } from './pages/free-slots/free-slots';

export const routes: Routes = [
  { path: '', component: Home, pathMatch: 'full' },
  { path: 'free-slots', component: FreeSlots },
  { path: '**', redirectTo: '' }
];