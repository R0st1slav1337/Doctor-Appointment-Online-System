from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import Doctors
from .serializers import DoctorSerializer
from django.db import connection

@api_view(['GET'])
def doctors_list(request):
    doctors = Doctors.objects.all()
    return Response(DoctorSerializer(doctors, many=True).data)

@api_view(['GET'])
def free_slots_list(request):
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT slot_id, doctor_id, doctor_name, specialty,
                   consultation_fee_kzt, slot_date, start_time, end_time
            FROM v_free_slots
            ORDER BY slot_date, start_time
        """)
        columns = [column[0] for column in cursor.description]
        slots = [dict(zip(columns, row)) for row in cursor.fetchall()]

    return Response(slots)