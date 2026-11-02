from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import Doctors
from .serializers import DoctorSerializer

@api_view(['GET'])
def doctors_list(request):
    doctors = Doctors.objects.all()
    return Response(DoctorSerializer(doctors, many=True).data)