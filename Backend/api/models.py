# managed = False: Django does NOT create or change these tables. They are created by the SQL files
# in database/ (01_schema.sql ...). To change a table, change the SQL, not Django migrations.
from django.db import models


class Specialties(models.Model):
    specialty_id = models.AutoField(primary_key=True)
    name = models.CharField(unique=True, max_length=80)
    description = models.CharField(max_length=255, blank=True, null=True)
    is_active = models.BooleanField()

    class Meta:
        managed = False
        db_table = 'specialties'


class Doctors(models.Model):
    doctor_id = models.AutoField(primary_key=True)
    specialty = models.ForeignKey(Specialties, models.DO_NOTHING)
    full_name = models.CharField(max_length=120)
    email = models.TextField(unique=True)  # This field type is a guess.
    room_number = models.CharField(max_length=10, blank=True, null=True)
    consultation_fee_kzt = models.IntegerField()
    is_active = models.BooleanField()

    class Meta:
        managed = False
        db_table = 'doctors'


class PhoneCountries(models.Model):
    country_code = models.CharField(primary_key=True, max_length=2)
    name = models.CharField(max_length=60)
    dial_code = models.CharField(max_length=4)
    min_digits = models.SmallIntegerField()
    max_digits = models.SmallIntegerField()
    example_mask = models.CharField(max_length=25, blank=True, null=True)
    sort_order = models.SmallIntegerField()
    is_active = models.BooleanField()

    class Meta:
        managed = False
        db_table = 'phone_countries'
        ordering = ['sort_order', 'name']


class Patients(models.Model):
    patient_id = models.AutoField(primary_key=True)
    full_name = models.CharField(max_length=120)
    email = models.TextField(unique=True)  # This field type is a guess.
    phone_country = models.ForeignKey(PhoneCountries, models.DO_NOTHING, db_column='phone_country')
    phone = models.CharField(max_length=16)  # E.164: +77011234567
    birth_date = models.DateField()
    password_hash = models.CharField(max_length=255)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'patients'


class TimeSlots(models.Model):
    slot_id = models.AutoField(primary_key=True)
    doctor = models.ForeignKey(Doctors, models.DO_NOTHING)
    slot_date = models.DateField()
    start_time = models.TimeField()
    end_time = models.TimeField()

    class Meta:
        managed = False
        db_table = 'time_slots'
        unique_together = (('doctor', 'slot_date', 'start_time'),)


class Appointments(models.Model):
    appointment_id = models.AutoField(primary_key=True)
    patient = models.ForeignKey(Patients, models.DO_NOTHING)
    slot = models.ForeignKey(TimeSlots, models.DO_NOTHING)
    status = models.CharField(max_length=15)
    reason = models.TextField(max_length=1000, blank=True, null=True)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'appointments'