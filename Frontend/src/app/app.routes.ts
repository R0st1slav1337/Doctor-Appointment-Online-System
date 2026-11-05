import { Routes } from '@angular/router';
import { Home } from './pages/home/home';
import { FreeSlots } from './pages/free-slots/free-slots';
import { Login } from './pages/login/login';
import { Me } from './pages/me/me';
import { roleGuard } from './services/AuthService';

export const routes: Routes = [
  { path: '', component: Home, pathMatch: 'full' },
  { path: 'free-slots', component: FreeSlots },
  { path: 'login', component: Login },
  { path: 'me', component: Me, canActivate: [roleGuard('patient', 'doctor', 'admin', 'manager')] },
  { path: '**', redirectTo: '' }
];