from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import Doctors
from .serializers import DoctorSerializer
from django.db import connection
from django.contrib.auth import authenticate
from rest_framework.authtoken.models import Token
from .roles import get_role, role_required

@api_view(['GET'])
def doctors_list(request):
    doctors = Doctors.objects.filter(is_active=True)
    return Response(DoctorSerializer(doctors, many=True).data)

# Task 10 - Altynai: free slots endpoint for the auto-refreshing slots page
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

@api_view(['POST'])
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


# Temporary endpoint to check that roles work (open only for the administrator).
@api_view(['GET'])
@role_required('admin')
def admin_check(request):
    return Response({'detail': 'You are an administrator'})