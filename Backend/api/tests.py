from unittest.mock import patch

from django.contrib.auth.models import Group, User
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from .roles import ROLES

# Role limits: endpoint -> roles that are allowed to use it. Everybody else must get 403,
# a visitor without login must get 401. The check does not touch the clinic tables
# (they are created by the SQL files, not by Django), so only the denied cases are called here.
LIMITS = {
    '/api/admin-check/': {'admin'},
    '/api/admin/doctors/': {'admin'},
    '/api/specialties/': {'admin'},
    '/api/reports/doctor-load/': {'admin', 'manager'},
}


class RoleLimitsTests(TestCase):
    def setUp(self):
        self.tokens = {}
        for role in ROLES:
            user = User.objects.create_user(username=f'{role}@test.local', password='Str0ng-Pass-77')
            user.groups.add(Group.objects.get_or_create(name=role)[0])
            self.tokens[role] = Token.objects.create(user=user).key

    def client_for(self, role):
        client = APIClient()
        if role is not None:
            client.credentials(HTTP_AUTHORIZATION='Token ' + self.tokens[role])
        return client

    def test_visitor_without_login_gets_401(self):
        for url in LIMITS:
            self.assertEqual(self.client_for(None).get(url).status_code, 401, url)

    def test_other_roles_get_403(self):
        for url, allowed in LIMITS.items():
            for role in ROLES:
                if role not in allowed:
                    self.assertEqual(self.client_for(role).get(url).status_code, 403, f'{role} {url}')

    def test_only_administrator_can_add_doctors(self):
        for role in ['patient', 'doctor', 'manager']:
            response = self.client_for(role).post('/api/admin/doctors/', {}, format='json')
            self.assertEqual(response.status_code, 403, role)

    def test_every_role_sees_own_profile(self):
        for role in ROLES:
            response = self.client_for(role).get('/api/me/')
            self.assertEqual(response.status_code, 200, role)
            self.assertEqual(response.data['role'], role)

    def test_administrator_check_is_open_for_administrator(self):
        self.assertEqual(self.client_for('admin').get('/api/admin-check/').status_code, 200)


class CreateStaffTests(TestCase):
    def run_command(self, email, role, password='Str0ng-Pass-77', repeat=None):
        with patch('api.management.commands.create_staff.getpass', side_effect=[password, repeat or password]):
            call_command('create_staff', email, role)

    def test_manager_is_created_with_role_group(self):
        self.run_command('m@test.local', 'manager')
        user = User.objects.get(username='m@test.local')
        self.assertEqual(list(user.groups.values_list('name', flat=True)), ['manager'])
        self.assertTrue(user.check_password('Str0ng-Pass-77'))

    def test_patient_and_doctor_cannot_be_created_here(self):
        for role in ['patient', 'doctor']:
            with self.assertRaises(CommandError):
                self.run_command(f'{role}@test.local', role)
        self.assertFalse(User.objects.exists())

    def test_password_mismatch_and_weak_password_are_refused(self):
        with self.assertRaises(CommandError):
            self.run_command('a@test.local', 'admin', repeat='Another-Pass-1')
        with self.assertRaises(CommandError):
            self.run_command('a@test.local', 'admin', password='12345678')
        self.assertFalse(User.objects.exists())