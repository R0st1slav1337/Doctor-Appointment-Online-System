import re
from datetime import date

from django.contrib.auth import authenticate
from django.contrib.auth.hashers import make_password
from django.contrib.auth.models import Group, User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.db import DatabaseError, IntegrityError, connection, transaction
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, authentication_classes, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .models import Doctors, Patients, PhoneCountries, Specialties
from .roles import get_role, role_required
from .serializers import DoctorSerializer
from .throttles import LoginThrottle, PasswordChangeThrottle, RegisterThrottle

# Public endpoints (doctors, free slots, login, register, phone countries) have @authentication_classes([]):
# the token is not checked there. Without it, an old token left in the browser (for example after the
# database was recreated) would give 401 even on the login page, and the user could not log in again.
@api_view(['GET'])
@authentication_classes([])
def doctors_list(request):
    doctors = Doctors.objects.filter(is_active=True).select_related('specialty').order_by('full_name')
    return Response(DoctorSerializer(doctors, many=True).data)

# Task 10 - Altynai: free slots endpoint for the auto-refreshing slots page
@api_view(['GET'])
@authentication_classes([])
def free_slots_list(request):
    with connection.cursor() as cursor:
        # Keep a rolling two-week window available as old generated slots expire.
        cursor.execute('SELECT generate_slots(CURRENT_DATE + 1, CURRENT_DATE + 14, 30)')
        cursor.execute("""
            SELECT slot_id, doctor_id, doctor_name, specialty,
                   consultation_fee_kzt, slot_date, start_time, end_time
            FROM v_free_slots
            ORDER BY slot_date, start_time
        """)
        columns = [column[0] for column in cursor.description]
        slots = [dict(zip(columns, row)) for row in cursor.fetchall()]

    return Response(slots)


@api_view(['POST'])
@role_required('patient')
def book_appointment(request):
    try:
        slot_id = int(request.data.get('slot_id'))
    except (TypeError, ValueError):
        return Response({'detail': 'Choose a valid appointment time.'}, status=400)

    reason = str(request.data.get('reason', '')).strip() or None
    if reason and len(reason) > 1000:
        return Response({'detail': 'The visit reason must be 1000 characters or fewer.'}, status=400)

    patient = Patients.objects.filter(email=request.user.username).first()
    if patient is None:
        return Response({'detail': 'Patient profile was not found.'}, status=404)

    try:
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute('SELECT book_appointment(%s, %s, %s)', [patient.patient_id, slot_id, reason])
                appointment_id = cursor.fetchone()[0]
    except DatabaseError as error:
        message = str(error).lower()
        if 'already taken' in message or 'unique' in message:
            detail = 'This time was just booked by someone else. Please choose another slot.'
        elif 'unavailable' in message:
            detail = 'The doctor is unavailable at this time. Please choose another slot.'
        elif 'past' in message or 'does not exist' in message or 'inactive' in message:
            detail = 'This appointment time is no longer available. Please choose another slot.'
        else:
            detail = 'The appointment could not be created. Please try again.'
        return Response({'detail': detail}, status=409)

    return Response({
        'appointment_id': appointment_id,
        'status': 'booked',
        'detail': 'Appointment created and confirmed successfully.',
    }, status=201)


@api_view(['GET', 'POST'])
@role_required('admin')
def admin_appointments(request):
    if request.method == 'GET':
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT a.appointment_id, a.status, a.reason, p.full_name AS patient_name,
                       d.full_name AS doctor_name, s.name AS specialty,
                       t.slot_date, t.start_time, t.end_time
                FROM appointments a
                JOIN patients p ON p.patient_id = a.patient_id
                JOIN time_slots t ON t.slot_id = a.slot_id
                JOIN doctors d ON d.doctor_id = t.doctor_id
                JOIN specialties s ON s.specialty_id = d.specialty_id
                WHERE a.status = 'booked'
                ORDER BY t.slot_date, t.start_time
            """)
            columns = [column[0] for column in cursor.description]
            appointments = [dict(zip(columns, row)) for row in cursor.fetchall()]
        return Response(appointments)

    try:
        appointment_id = int(request.data.get('appointment_id'))
    except (TypeError, ValueError):
        return Response({'detail': 'Choose a valid appointment.'}, status=400)

    with connection.cursor() as cursor:
        cursor.execute("""
            UPDATE appointments
            SET status = 'cancelled'
            WHERE appointment_id = %s AND status = 'booked'
            RETURNING appointment_id
        """, [appointment_id])
        cancelled_id = cursor.fetchone()
    if cancelled_id is None:
        return Response({'detail': 'This appointment is no longer active.'}, status=409)
    return Response({'appointment_id': cancelled_id[0], 'detail': 'Appointment cancelled.'})

@api_view(['POST'])
@authentication_classes([])
@throttle_classes([LoginThrottle])   # Task 11 - Amina: max 5 login attempts per minute from one IP
def login(request):
    email = request.data.get('email', '')
    password = request.data.get('password', '')
    user = authenticate(request, username=email, password=password)
    if user is None:
        return Response({'detail': 'Wrong email or password'}, status=401)
    token, _ = Token.objects.get_or_create(user=user)
    return Response({'token': token.key, 'email': user.username, 'role': get_role(user)})


@api_view(['GET'])
@role_required('patient', 'doctor', 'admin', 'manager')
def me(request):
    return Response({'email': request.user.username, 'role': get_role(request.user)})


# Test endpoint for the role limits (see tests.py): open only for the administrator. Can be removed later.
@api_view(['GET'])
@role_required('admin')
def admin_check(request):
    return Response({'detail': 'You are an administrator'})

# Countries for the phone selector on the registration page (public).
@api_view(['GET'])
@authentication_classes([])
def phone_countries_list(request):
    countries = PhoneCountries.objects.filter(is_active=True).values(
        'country_code', 'name', 'dial_code', 'min_digits', 'max_digits', 'example_mask')
    return Response(list(countries))


def _parse_phone(country_code, raw_phone):
    """Country + number without the code -> (country, phone in E.164, error text or None).
    E.164 = "+" + country dial code + digits, e.g. +77011234567. Used by registration and the profile."""
    digits = re.sub(r'\D', '', str(raw_phone or ''))
    country = PhoneCountries.objects.filter(
        country_code=str(country_code or '').strip().upper(), is_active=True).first()
    if country is None:
        return None, None, 'Choose the country of your phone number.'
    if not country.min_digits <= len(digits) <= country.max_digits:
        need = (str(country.min_digits) if country.min_digits == country.max_digits
                else f'{country.min_digits}-{country.max_digits}')
        return country, None, (f'For {country.name} the phone number without the country code '
                               f'must have {need} digits, you entered {len(digits)}.')
    return country, '+' + country.dial_code + digits, None


def _db_error_message(error):
    """Readable text for an error raised by a PostgreSQL constraint or trigger."""
    text = str(error)
    if 'ux_patients_phone' in text:
        return 'This phone number is already registered.'
    if 'unique' in text.lower():
        return 'This email is already registered.'
    return 'Registration failed: ' + text.strip().splitlines()[0]


# Public registration. It always creates a PATIENT: the role is never taken from the request,
# so nobody can register himself as a doctor, administrator or manager.
@api_view(['POST'])
@authentication_classes([])
@throttle_classes([RegisterThrottle])
def register(request):
    data = request.data
    full_name = str(data.get('full_name', '')).strip()
    email = str(data.get('email', '')).strip().lower()
    password = str(data.get('password', ''))
    phone_country = str(data.get('phone_country', '')).strip().upper()
    digits = re.sub(r'\D', '', str(data.get('phone', '')))

    if not full_name or len(full_name) > 120:
        return Response({'detail': 'Enter your full name (up to 120 characters).'}, status=400)
    try:
        validate_email(email)
    except ValidationError:
        return Response({'detail': 'Enter a valid email.'}, status=400)
    if len(email) > 150:
        return Response({'detail': 'The email is too long.'}, status=400)
    try:
        birth_date = date.fromisoformat(str(data.get('birth_date', '')))
    except ValueError:
        return Response({'detail': 'Enter a valid date of birth.'}, status=400)
    if birth_date < date(1900, 1, 1) or birth_date > date.today():
        return Response({'detail': 'The date of birth must be between 1900 and today.'}, status=400)

    country, full_phone, phone_error = _parse_phone(phone_country, digits)
    if phone_error:
        return Response({'detail': phone_error}, status=400)

    try:
        validate_password(password, user=User(username=email, email=email))
    except ValidationError as e:
        return Response({'detail': ' '.join(e.messages)}, status=400)

    # The database checks the length again for the chosen country (trigger trg_patients_phone)
    # and keeps the phone unique (index ux_patients_phone): one person = one account.
    if Patients.objects.filter(phone=full_phone).exists():
        return Response({'detail': 'This phone number is already registered.'}, status=400)

    # The email is the login (User.username), so it must be free in all three places:
    # login accounts, patients and doctors.
    if (User.objects.filter(username__iexact=email).exists()
            or Patients.objects.filter(email=email).exists()
            or Doctors.objects.filter(email=email).exists()):
        return Response({'detail': 'This email is already registered.'}, status=400)

    # Task 11 - Amina: the password is stored ONLY as a hash (Argon2, see PASSWORD_HASHERS in settings.py)
    # and ONLY in the Django login account. The patients table has no password column any more.
    try:
        # the patient row and the login account are created together or not at all
        with transaction.atomic():
            Patients.objects.create(
                full_name=full_name,
                email=email,
                phone_country=country,
                phone=full_phone,
                birth_date=birth_date,
                created_at=timezone.now(),
            )
            user = User.objects.create_user(username=email, email=email, password=password)
            group, _ = Group.objects.get_or_create(name='patient')
            user.groups.add(group)
    except IntegrityError as e:
        return Response({'detail': _db_error_message(e)}, status=400)

    token, _ = Token.objects.get_or_create(user=user)
    return Response({'token': token.key, 'email': user.username, 'role': 'patient'}, status=201)

# ---- Administrator: doctors ----------------------------------------------------------

# Specialties for the "add doctor" form.
@api_view(['GET'])
@role_required('admin')
def specialties_list(request):
    rows = Specialties.objects.filter(is_active=True).order_by('name').values('specialty_id', 'name')
    return Response(list(rows))

# Default working time of a new doctor (same as in the seed data): Monday-Friday 09:00-18:00,
# lunch 13:00-14:00. Slots are generated for the next 14 days in 30-minute steps.
# The schedule can be changed later in weekly_schedules.
DEFAULT_SLOT_MINUTES = 30
DEFAULT_SLOT_DAYS_AHEAD = 14


def _create_default_schedule(doctor_id):
    """Creates the weekly schedule and the slots of a new doctor. Returns the number of slots."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO weekly_schedules
                (doctor_id, day_of_week, start_time, end_time, lunch_start, lunch_end, is_active)
            SELECT %s::integer, d.day_of_week, TIME '09:00', TIME '18:00', TIME '13:00', TIME '14:00', true
            FROM generate_series(1, 5) AS d(day_of_week)
            """,
            [doctor_id],
        )
        cursor.execute(
            f'SELECT generate_slots(CURRENT_DATE + 1, CURRENT_DATE + {DEFAULT_SLOT_DAYS_AHEAD}, '
            f'{DEFAULT_SLOT_MINUTES})'
        )
        cursor.execute(
            'SELECT count(*) FROM time_slots WHERE doctor_id = %s AND slot_date > CURRENT_DATE',
            [doctor_id],
        )
        return cursor.fetchone()[0]

# GET: all doctors (also inactive ones). POST: add a doctor = doctor card + login account.
# Only the administrator can do it; the account always gets the role "doctor".
@api_view(['GET', 'POST'])
@role_required('admin')
def admin_doctors(request):
    if request.method == 'GET':
        doctors = Doctors.objects.select_related('specialty').order_by('doctor_id')
        return Response([
            {
                'doctor_id': d.doctor_id,
                'full_name': d.full_name,
                'email': d.email,
                'specialty': d.specialty.name,
                'room_number': d.room_number,
                'consultation_fee_kzt': d.consultation_fee_kzt,
                'is_active': d.is_active,
            }
            for d in doctors
        ])

    data = request.data
    full_name = str(data.get('full_name', '')).strip()
    email = str(data.get('email', '')).strip().lower()
    room_number = str(data.get('room_number', '')).strip()
    password = str(data.get('password', ''))

    if not full_name or len(full_name) > 120:
        return Response({'detail': 'Enter the full name (up to 120 characters).'}, status=400)
    try:
        validate_email(email)
    except ValidationError:
        return Response({'detail': 'Enter a valid email.'}, status=400)
    if len(email) > 150:
        return Response({'detail': 'The email is too long.'}, status=400)
    if len(room_number) > 10:
        return Response({'detail': 'The room number can have up to 10 characters.'}, status=400)
    try:
        fee = int(data.get('consultation_fee_kzt'))
    except (TypeError, ValueError):
        return Response({'detail': 'Enter the consultation fee as a number.'}, status=400)
    if not 0 <= fee <= 200000:
        return Response({'detail': 'The fee must be between 0 and 200000 KZT.'}, status=400)
    try:
        specialty_id = int(data.get('specialty_id'))
    except (TypeError, ValueError):
        return Response({'detail': 'Choose a specialty.'}, status=400)
    specialty = Specialties.objects.filter(specialty_id=specialty_id, is_active=True).first()
    if specialty is None:
        return Response({'detail': 'Choose a specialty.'}, status=400)

    try:
        validate_password(password, user=User(username=email, email=email))
    except ValidationError as e:
        return Response({'detail': ' '.join(e.messages)}, status=400)

    if (User.objects.filter(username__iexact=email).exists()
            or Patients.objects.filter(email=email).exists()
            or Doctors.objects.filter(email=email).exists()):
        return Response({'detail': 'This email is already used.'}, status=400)

    try:
        # the doctor card and the login account are created together or not at all
        with transaction.atomic():
            doctor = Doctors.objects.create(
                specialty=specialty,
                full_name=full_name,
                email=email,
                room_number=room_number or None,
                consultation_fee_kzt=fee,
                is_active=True,
            )
            user = User.objects.create(username=email, email=email, password=make_password(password))
            group, _ = Group.objects.get_or_create(name='doctor')
            user.groups.add(group)
            # inside the same transaction: if the schedule fails, the doctor and the account are not created either
            slots_created = _create_default_schedule(doctor.doctor_id)
    except IntegrityError as e:
        return Response({'detail': _db_error_message(e)}, status=400)

    return Response({'doctor_id': doctor.doctor_id, 'email': email, 'role': 'doctor',
                     'slots_created': slots_created}, status=201)

# ---- Reports: administrator and manager (read-only) -----------------------------------

# Doctor load from today: booked appointments and total slots per doctor.
# Only numbers: no patient names, no reasons for the visit.
@api_view(['GET'])
@role_required('admin', 'manager')
def doctor_load_report(request):
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT doctor_id, doctor_name,
                   sum(booked_appointments)::integer AS booked_appointments,
                   sum(total_slots)::integer         AS total_slots
            FROM v_doctor_load
            WHERE slot_date >= CURRENT_DATE
            GROUP BY doctor_id, doctor_name
            ORDER BY doctor_name
        """)
        columns = [column[0] for column in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    return Response(rows)

# ---- Task 11 - Amina: account security and the patient's contacts ----------------------

# Log out on the SERVER: the token is deleted, so a copied token stops working too.
# (Before, logout only removed the token from the browser; the token itself stayed valid forever.)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def logout(request):
    Token.objects.filter(user=request.user).delete()
    return Response(status=204)


# Change password: the old password is required, the new one goes through the same rules as at registration.
# After the change all old tokens are deleted (other devices are logged out) and a new token is returned.
@api_view(['POST'])
@permission_classes([IsAuthenticated])
@throttle_classes([PasswordChangeThrottle])
def change_password(request):
    user = request.user
    old_password = str(request.data.get('old_password', ''))
    new_password = str(request.data.get('new_password', ''))
    if not user.check_password(old_password):
        return Response({'detail': 'The current password is wrong.'}, status=400)
    if new_password == old_password:
        return Response({'detail': 'The new password must be different from the current one.'}, status=400)
    try:
        validate_password(new_password, user=user)
    except ValidationError as e:
        return Response({'detail': ' '.join(e.messages)}, status=400)
    user.set_password(new_password)   # Argon2 hash with a new random salt
    user.save(update_fields=['password'])
    Token.objects.filter(user=user).delete()
    token = Token.objects.create(user=user)
    return Response({'token': token.key, 'email': user.username, 'role': get_role(user)})


def _phone_country_dict(country):
    return {'country_code': country.country_code, 'name': country.name, 'dial_code': country.dial_code,
            'min_digits': country.min_digits, 'max_digits': country.max_digits,
            'example_mask': country.example_mask}


def _patient_contacts(patient):
    return {
        'full_name': patient.full_name,
        'email': patient.email,
        'phone': patient.phone,
        'phone_country': _phone_country_dict(patient.phone_country),
        'birth_date': patient.birth_date,
    }


# GET: own profile. A patient also gets the contacts (phone with country, date of birth),
# a doctor gets the specialty and room. Only the OWN record: it is found by the email of the token's user.
# PATCH (patient): change the phone country and number. Checked here and again by the database trigger.
@api_view(['GET', 'PATCH'])
@role_required('patient', 'doctor', 'admin', 'manager')
def my_profile(request):
    role = get_role(request.user)
    email = request.user.username
    patient = None
    if role == 'patient':
        patient = Patients.objects.select_related('phone_country').filter(email=email).first()

    if request.method == 'PATCH':
        if patient is None:
            return Response({'detail': 'Only a patient can change the phone here.'}, status=403)
        country, full_phone, phone_error = _parse_phone(
            request.data.get('phone_country'), request.data.get('phone'))
        if phone_error:
            return Response({'detail': phone_error}, status=400)
        if Patients.objects.filter(phone=full_phone).exclude(patient_id=patient.patient_id).exists():
            return Response({'detail': 'This phone number is already registered.'}, status=400)
        try:
            with transaction.atomic():
                Patients.objects.filter(patient_id=patient.patient_id).update(
                    phone_country=country, phone=full_phone)
        except IntegrityError as e:
            return Response({'detail': _db_error_message(e)}, status=400)
        patient = Patients.objects.select_related('phone_country').get(patient_id=patient.patient_id)

    data = {'email': email, 'role': role}
    if patient is not None:
        data['contacts'] = _patient_contacts(patient)
    elif role == 'doctor':
        doctor = Doctors.objects.select_related('specialty').filter(email=email).first()
        if doctor is not None:
            data['doctor'] = {'full_name': doctor.full_name, 'specialty': doctor.specialty.name,
                              'room_number': doctor.room_number}
    return Response(data)


# The patient's OWN appointments with the reason for the visit (newest first).
# Other patients' appointments are never returned: the filter is by the email of the logged-in user.
@api_view(['GET'])
@role_required('patient')
def my_appointments(request):
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT a.appointment_id, a.status, a.reason, t.slot_date, t.start_time, t.end_time,
                   d.full_name AS doctor_name, s.name AS specialty, d.room_number
            FROM appointments a
            JOIN patients p    ON p.patient_id = a.patient_id
            JOIN time_slots t  ON t.slot_id = a.slot_id
            JOIN doctors d     ON d.doctor_id = t.doctor_id
            JOIN specialties s ON s.specialty_id = d.specialty_id
            WHERE p.email = %s
            ORDER BY t.slot_date DESC, t.start_time DESC
        """, [request.user.username])
        columns = [column[0] for column in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    return Response(rows)


@api_view(['POST'])
@role_required('patient')
def cancel_my_appointment(request):
    try:
        appointment_id = int(request.data.get('appointment_id'))
    except (TypeError, ValueError):
        return Response({'detail': 'Choose a valid appointment.'}, status=400)

    patient = Patients.objects.filter(email=request.user.username).first()
    if patient is None:
        return Response({'detail': 'Patient profile was not found.'}, status=404)

    try:
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute(
                    'SELECT cancel_appointment(%s, %s)',
                    [appointment_id, patient.patient_id]
                )
    except DatabaseError:
        return Response(
            {'detail': 'This appointment is no longer active or does not belong to you.'},
            status=409
        )

    return Response({
        'appointment_id': appointment_id,
        'status': 'cancelled',
        'detail': 'Your appointment was cancelled.'
    })


@api_view(['POST'])
@role_required('admin')
def deactivate_doctor(request, doctor_id):
    with transaction.atomic():
        doctor = Doctors.objects.select_for_update().filter(doctor_id=doctor_id).first()
        if doctor is None:
            return Response({'detail': 'Doctor not found'}, status=404)
        if not doctor.is_active:
            return Response({'detail': 'Doctor is already inactive'}, status=409)
        doctor.is_active = False
        doctor.save(update_fields=['is_active'])
    return Response({
        'doctor_id': doctor_id,
        'is_active': False,
        'detail': 'Doctor deactivated; future bookings processed by database trigger',
    }, status=200)