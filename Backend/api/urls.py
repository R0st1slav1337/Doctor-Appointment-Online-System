from django.urls import path
from .views import (doctors_list, free_slots_list, login, me, admin_check, register, phone_countries_list,
                    specialties_list, admin_doctors, doctor_load_report,
                    logout, change_password, my_profile, my_appointments, book_appointment,
                    admin_appointments, cancel_my_appointment)

urlpatterns = [
    path('doctors/', doctors_list),
    path('free-slots/', free_slots_list),
    path('appointments/', book_appointment),
    path('admin/appointments/', admin_appointments),
    path('login/', login),
    path('register/', register),
    path('phone-countries/', phone_countries_list),
    path('me/', me),
    path('me/profile/', my_profile),
    path('me/appointments/', my_appointments),
    path('me/appointments/cancel/', cancel_my_appointment),
    path('me/password/', change_password),
    path('logout/', logout),
    path('admin-check/', admin_check),
    path('specialties/', specialties_list),
    path('admin/doctors/', admin_doctors),
    path('reports/doctor-load/', doctor_load_report),
]
