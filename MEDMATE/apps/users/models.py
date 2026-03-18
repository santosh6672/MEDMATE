from django.db import models
from django.contrib.auth.models import User
import random
import string
from django.utils import timezone
from datetime import timedelta


class EmailOTP(models.Model):
    """
    Stores a 6-digit OTP tied to an email address.
    Expires after OTP_EXPIRY_MINUTES minutes.
    Invalidated after OTP_MAX_ATTEMPTS failed attempts.
    """

    OTP_EXPIRY_MINUTES = 10
    OTP_MAX_ATTEMPTS   = 5

    user       = models.OneToOneField(User, on_delete=models.CASCADE, related_name='email_otp')
    otp        = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    attempts   = models.IntegerField(default=0)
    verified   = models.BooleanField(default=False)

    class Meta:
        verbose_name = "Email OTP"

    def __str__(self):
        return f"{self.user.email} — {self.otp} ({'verified' if self.verified else 'pending'})"

    @staticmethod
    def generate_otp():
        """Returns a random 6-digit numeric string."""
        return ''.join(random.choices(string.digits, k=6))

    def is_expired(self):
        expiry = self.created_at + timedelta(minutes=self.OTP_EXPIRY_MINUTES)
        return timezone.now() > expiry

    def is_valid(self, entered_otp: str) -> tuple[bool, str]:
        """
        Returns (success: bool, reason: str).
        Increments attempt counter on failure.
        """
        if self.verified:
            return False, "OTP already used."
        if self.is_expired():
            return False, "OTP has expired. Please request a new one."
        if self.attempts >= self.OTP_MAX_ATTEMPTS:
            return False, "Too many attempts. Please request a new OTP."
        if self.otp != entered_otp.strip():
            self.attempts += 1
            self.save(update_fields=['attempts'])
            remaining = self.OTP_MAX_ATTEMPTS - self.attempts
            return False, f"Incorrect OTP. {remaining} attempt(s) remaining."

        # ✅ Valid
        self.verified = True
        self.save(update_fields=['verified'])
        return True, "verified"