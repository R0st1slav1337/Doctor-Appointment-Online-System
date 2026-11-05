from django.urls import path
from .views import doctors_list, free_slots_list


urlpatterns = [
    path('doctors/', doctors_list),
     path('free-slots/', free_slots_list),
]