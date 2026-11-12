from unittest.mock import patch

from django.contrib.auth.models import Group, User
from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase
from django.contrib.auth.hashers import make_password
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
    '/api/me/appointments/': {'patient'},
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


# Task 11 - Amina: password storage and account security.
# These tests use only Django tables (auth_user, authtoken), so they work in the test database.
class PasswordSecurityTests(TestCase):
    PASSWORD = 'Str0ng-Pass-77'

    def setUp(self):
        cache.clear()   # the attempt counters (throttling) live in the cache
        self.user = User.objects.create_user(username='p@test.local', password=self.PASSWORD)
        self.user.groups.add(Group.objects.get_or_create(name='patient')[0])
        self.token = Token.objects.create(user=self.user).key

    def auth_client(self, token=None):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION='Token ' + (token or self.token))
        return client

    def test_password_is_stored_as_argon2_hash(self):
        stored = User.objects.get(pk=self.user.pk).password
        self.assertTrue(stored.startswith('argon2$argon2id$'), stored[:20])
        self.assertNotIn(self.PASSWORD, stored)

    def test_same_password_gives_different_hashes(self):
        other = User.objects.create_user(username='q@test.local', password=self.PASSWORD)
        self.assertNotEqual(other.password, User.objects.get(pk=self.user.pk).password)   # random salt

    def test_old_pbkdf2_hash_is_upgraded_on_login(self):
        old = make_password(self.PASSWORD, hasher='pbkdf2_sha256')
        User.objects.filter(pk=self.user.pk).update(password=old)
        response = APIClient().post('/api/login/', {'email': 'p@test.local', 'password': self.PASSWORD},
                                    format='json')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(User.objects.get(pk=self.user.pk).password.startswith('argon2$'))

    def test_wrong_password_gives_401_without_details(self):
        response = APIClient().post('/api/login/', {'email': 'p@test.local', 'password': 'wrong'},
                                    format='json')
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.data['detail'], 'Wrong email or password')

    def test_login_is_limited_to_5_attempts_per_minute(self):
        client = APIClient()
        codes = [client.post('/api/login/', {'email': 'p@test.local', 'password': 'wrong'},
                             format='json').status_code for _ in range(6)]
        self.assertEqual(codes[:5], [401] * 5)
        self.assertEqual(codes[5], 429)

    def test_logout_deletes_token_on_server(self):
        self.assertEqual(self.auth_client().post('/api/logout/').status_code, 204)
        self.assertFalse(Token.objects.filter(key=self.token).exists())
        self.assertEqual(self.auth_client().get('/api/me/').status_code, 401)

    def test_change_password_needs_current_password(self):
        response = self.auth_client().post('/api/me/password/', {
            'old_password': 'wrong', 'new_password': 'N3w-Strong-Pass'}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertTrue(User.objects.get(pk=self.user.pk).check_password(self.PASSWORD))

    def test_change_password_rejects_weak_password(self):
        response = self.auth_client().post('/api/me/password/', {
            'old_password': self.PASSWORD, 'new_password': '12345678'}, format='json')
        self.assertEqual(response.status_code, 400)

    def test_change_password_works_and_old_token_stops_working(self):
        response = self.auth_client().post('/api/me/password/', {
            'old_password': self.PASSWORD, 'new_password': 'N3w-Strong-Pass'}, format='json')
        self.assertEqual(response.status_code, 200)
        user = User.objects.get(pk=self.user.pk)
        self.assertTrue(user.check_password('N3w-Strong-Pass'))
        self.assertTrue(user.password.startswith('argon2$'))
        self.assertEqual(self.auth_client().get('/api/me/').status_code, 401)              # old token
        self.assertEqual(self.auth_client(response.data['token']).get('/api/me/').status_code, 200)

    def test_new_endpoints_need_login(self):
        for url in ['/api/logout/', '/api/me/password/']:
            self.assertEqual(APIClient().post(url).status_code, 401, url)
        self.assertEqual(APIClient().get('/api/me/profile/').status_code, 401)
