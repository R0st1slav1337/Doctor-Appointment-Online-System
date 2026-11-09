from functools import wraps
from rest_framework.response import Response

ROLES = ['patient', 'doctor', 'admin', 'manager']


def get_role(user):
    """Role of the user = name of the group the user belongs to (None if there is no group).
    Every account has exactly one group. It is set when the account is created (register, add doctor,
    create_staff, setup_roles) and nothing on the site can change it."""
    if not user.is_authenticated:
        return None
    return user.groups.values_list('name', flat=True).first()


def role_required(*allowed_roles):
    """Use under @api_view (the order matters): the endpoint is open only for the listed roles.
    401 = not logged in, 403 = logged in with the wrong role. The check runs before the view,
    so a forbidden role never reaches the database."""
    def decorator(view):
        @wraps(view)
        def wrapper(request, *args, **kwargs):
            if not request.user.is_authenticated:
                return Response({'detail': 'Login required'}, status=401)
            if get_role(request.user) not in allowed_roles:
                return Response({'detail': 'This action is not allowed for your role'}, status=403)
            return view(request, *args, **kwargs)
        return wrapper
    return decorator