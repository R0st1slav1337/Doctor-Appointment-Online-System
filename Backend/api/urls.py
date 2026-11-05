from django.urls import path
from .views import doctors_list, free_slots_list, login, me, admin_check

urlpatterns = [
    path('doctors/', doctors_list),
    path('free-slots/', free_slots_list),
    path('login/', login),
    path('me/', me),
    path('admin-check/', admin_check),
]