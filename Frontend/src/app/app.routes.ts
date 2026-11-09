import { Routes } from '@angular/router';
import { Home } from './pages/home/home';
import { FreeSlots } from './pages/free-slots/free-slots';
import { Login } from './pages/login/login';
import { Register } from './pages/register/register';
import { Me } from './pages/me/me';
import { roleGuard } from './services/AuthService';
import { AdminDoctors } from './pages/admin-doctors/admin-doctors';
import { Reports } from './pages/reports/reports';

export const routes: Routes = [
  { path: '', component: Home, pathMatch: 'full' },
  { path: 'free-slots', component: FreeSlots },
  { path: 'login', component: Login },
  { path: 'register', component: Register },
  { path: 'me', component: Me, canActivate: [roleGuard('patient', 'doctor', 'admin', 'manager')] },
  { path: 'admin/doctors', component: AdminDoctors, canActivate: [roleGuard('admin')] },
  { path: 'reports', component: Reports, canActivate: [roleGuard('admin', 'manager')] },
  { path: '**', redirectTo: '' }
];