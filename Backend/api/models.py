# This is an auto-generated Django model module.
# You'll have to do the following manually to clean this up:
#   * Rearrange models' order
#   * Make sure each model has one field with primary_key=True
#   * Make sure each ForeignKey and OneToOneField has `on_delete` set to the desired behavior
#   * Remove `managed = False` lines if you wish to allow Django to create, modify, and delete the table
# Feel free to rename the models, but don't rename db_table values or field names.
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


class Patients(models.Model):
    patient_id = models.AutoField(primary_key=True)
    full_name = models.CharField(max_length=120)
    email = models.TextField(unique=True)  # This field type is a guess.
    phone = models.CharField(max_length=20)
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
    reason = models.CharField(max_length=255, blank=True, null=True)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'appointments'
