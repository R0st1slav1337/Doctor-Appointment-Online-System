"""Week 11: five isolated API tests. No clinic PostgreSQL tables required.

Integration of the PostgreSQL rebooking trigger must be tested separately against
a real clinic database loaded from database/ SQL scripts.
"""
from unittest.mock import MagicMock, patch

from django.contrib.auth.models import Group, User
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient


URL = '/api/admin/doctors/7/deactivate/'


class DoctorDeactivationAPITests(TestCase):
    @classmethod
    def setUpTestData(cls):
        for role in ('admin', 'patient', 'doctor', 'manager'):
            user = User.objects.create_user(username=f'{role}@test.local', password='Str0ng-Pass-77')
            user.groups.add(Group.objects.get_or_create(name=role)[0])
            Token.objects.create(user=user)

    def client_for(self, role=None):
        client = APIClient()
        if role:
            user = User.objects.get(username=f'{role}@test.local')
            client.credentials(HTTP_AUTHORIZATION='Token ' + user.auth_token.key)
        return client

    def test_1_visitor_is_denied_401(self):
        self.assertEqual(self.client_for().post(URL).status_code, 401)

    def test_2_non_admin_roles_are_denied_403(self):
        for role in ('patient', 'doctor', 'manager'):
            with self.subTest(role=role):
                self.assertEqual(self.client_for(role).post(URL).status_code, 403)

    @patch('api.views.Doctors.objects.select_for_update')
    def test_3_missing_doctor_returns_404(self, select_for_update):
        select_for_update.return_value.filter.return_value.first.return_value = None
        response = self.client_for('admin').post(URL)
        self.assertEqual(response.status_code, 404)

    @patch('api.views.Doctors.objects.select_for_update')
    def test_4_already_inactive_returns_409(self, select_for_update):
        doctor = MagicMock(is_active=False)
        select_for_update.return_value.filter.return_value.first.return_value = doctor
        response = self.client_for('admin').post(URL)
        self.assertEqual(response.status_code, 409)
        doctor.save.assert_not_called()

    @patch('api.views.Doctors.objects.select_for_update')
    def test_5_admin_deactivates_doctor(self, select_for_update):
        doctor = MagicMock(is_active=True)
        select_for_update.return_value.filter.return_value.first.return_value = doctor
        response = self.client_for('admin').post(URL)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['is_active'], False)
        self.assertFalse(doctor.is_active)
        doctor.save.assert_called_once_with(update_fields=['is_active'])
