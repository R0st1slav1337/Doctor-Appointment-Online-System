# Task 11 - Amina: limits of attempts against password guessing (brute force).
# The counter is per IP address; the rates are in settings.py (REST_FRAMEWORK['DEFAULT_THROTTLE_RATES']).
# Over the limit the server answers 429 Too Many Requests and says after how many seconds to try again.
from rest_framework.throttling import SimpleRateThrottle


class _IpThrottle(SimpleRateThrottle):
    """Counts requests per IP address, also for logged-in users."""

    def get_cache_key(self, request, view):
        return self.cache_format % {'scope': self.scope, 'ident': self.get_ident(request)}


class LoginThrottle(_IpThrottle):
    scope = 'login'


class RegisterThrottle(_IpThrottle):
    scope = 'register'


class PasswordChangeThrottle(_IpThrottle):
    scope = 'password_change'
