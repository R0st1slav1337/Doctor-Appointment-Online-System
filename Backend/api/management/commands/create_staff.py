from getpass import getpass

from django.contrib.auth.models import Group, User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError
from django.core.validators import validate_email

# Only these two roles can be created here. Patients register on the site,
# doctors are added by the administrator on the site.
STAFF_ROLES = ['admin', 'manager']


class Command(BaseCommand):
    help = ('Create an administrator or manager account. This works only in the server console: '
            'there is no way to create these roles from the website or the API.')

    def add_arguments(self, parser):
        parser.add_argument('email')
        parser.add_argument('role', choices=STAFF_ROLES)

    def handle(self, *args, **options):
        email = options['email'].strip().lower()
        role = options['role']

        try:
            validate_email(email)
        except ValidationError:
            raise CommandError('Invalid email.')
        if User.objects.filter(username__iexact=email).exists():
            raise CommandError('This email already has an account.')
        
        # getpass: the password is typed hidden and does not stay in the command line history
        password = getpass('Password: ')
        if password != getpass('Repeat password: '):
            raise CommandError('Passwords do not match.')
        try:
            validate_password(password, user=User(username=email, email=email))
        except ValidationError as e:
            raise CommandError(' '.join(e.messages))

        user = User.objects.create_user(username=email, email=email, password=password)
        group, _ = Group.objects.get_or_create(name=role)
        user.groups.set([group])
        self.stdout.write(self.style.SUCCESS(f'Created {role}: {email}'))