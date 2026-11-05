from django.contrib.auth.models import Group, User
from django.core.management.base import BaseCommand
from api.roles import ROLES

# Development only: the same demo password for every demo user.
DEMO_PASSWORD = 'Clinic12345'
DEMO_USERS = [
    ('a@mail.test', 'patient'),            # Test Patient A from 04_seed.sql
    ('a.nurtaeva@clinic.test', 'doctor'),  # Dr. Aigerim Nurtaeva from 04_seed.sql
    ('admin@clinic.test', 'admin'),
    ('manager@clinic.test', 'manager'),
]


class Command(BaseCommand):
    help = 'Create the role groups and one demo user per role (development only)'

    def handle(self, *args, **options):
        for name in ROLES:
            Group.objects.get_or_create(name=name)
        for email, role in DEMO_USERS:
            user, _ = User.objects.get_or_create(username=email, defaults={'email': email})
            user.set_password(DEMO_PASSWORD)
            user.save()
            user.groups.set([Group.objects.get(name=role)])
            self.stdout.write(f'{role:8} {email}')
        self.stdout.write(self.style.SUCCESS(f'Done. Password for all demo users: {DEMO_PASSWORD}'))