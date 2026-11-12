from rest_framework import serializers
from .models import Doctors

class DoctorSerializer(serializers.ModelSerializer):
    specialty_name = serializers.CharField(source='specialty.name', read_only=True)

    class Meta:
        model = Doctors
        fields = ('doctor_id', 'specialty', 'specialty_name', 'full_name', 'email',
                  'room_number', 'consultation_fee_kzt', 'is_active')
