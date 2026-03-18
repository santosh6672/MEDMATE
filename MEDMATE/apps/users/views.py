from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.contrib.auth.models import User
from django.core.mail import send_mail
from django.conf import settings

from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .serializers import (
    UserRegistrationSerializer,
    UserProfileSerializer,
    ChangePasswordSerializer,
    OTPVerifySerializer,
)
from .models import EmailOTP


# ── Helper: issue JWT tokens for a user ──────────────────────────────────────
def _issue_tokens(user):
    refresh = RefreshToken.for_user(user)
    return {
        "refresh": str(refresh),
        "access":  str(refresh.access_token),
    }


# ── Helper: create/replace OTP and send email ────────────────────────────────
def _send_otp(user):
    otp_code = EmailOTP.generate_otp()

    # Replace any existing OTP for this user
    EmailOTP.objects.filter(user=user).delete()
    EmailOTP.objects.create(user=user, otp=otp_code)

    send_mail(
        subject="MedMate — Your verification code",
        message=(
            f"Hi {user.username},\n\n"
            f"Your MedMate verification code is:\n\n"
            f"  {otp_code}\n\n"
            f"This code expires in {EmailOTP.OTP_EXPIRY_MINUTES} minutes.\n"
            f"If you didn't create a MedMate account, ignore this email.\n\n"
            f"— The MedMate Team"
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[user.email],
        fail_silently=False,
    )


# ==========================================
# 1. Register View
#    POST /api/users/register/
#    Creates user (inactive) + sends OTP
# ==========================================

class RegisterView(generics.CreateAPIView):
    serializer_class   = UserRegistrationSerializer
    permission_classes = [permissions.AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()           # is_active=False until OTP verified

        try:
            _send_otp(user)
        except Exception as e:
            # If email fails, delete the user so they can retry
            user.delete()
            return Response(
                {"error": "Could not send verification email. Check your email address and try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {
                "message": f"Account created. A 6-digit code was sent to {user.email}.",
                "email": user.email,
            },
            status=status.HTTP_201_CREATED,
        )


# ==========================================
# 2. Verify OTP View
#    POST /api/users/verify-otp/
#    Body: { "email", "otp" }
#    On success: activates user + returns JWT
# ==========================================

class VerifyOTPView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = OTPVerifySerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        email = serializer.validated_data['email']
        otp   = serializer.validated_data['otp']

        try:
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            return Response(
                {"error": "No account found with this email."},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            otp_obj = user.email_otp
        except EmailOTP.DoesNotExist:
            return Response(
                {"error": "No OTP found. Please register again."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        valid, reason = otp_obj.is_valid(otp)
        if not valid:
            return Response({"error": reason}, status=status.HTTP_400_BAD_REQUEST)

        # ✅ Activate account
        user.is_active = True
        user.save(update_fields=['is_active'])

        return Response(
            {
                "message": "Email verified! Welcome to MedMate.",
                **_issue_tokens(user),
            },
            status=status.HTTP_200_OK,
        )


# ==========================================
# 3. Resend OTP View
#    POST /api/users/resend-otp/
#    Body: { "email" }
# ==========================================

class ResendOTPView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        email = request.data.get('email', '').strip()
        if not email:
            return Response(
                {"error": "Email is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            user = User.objects.get(email=email, is_active=False)
        except User.DoesNotExist:
            return Response(
                {"error": "No unverified account found with this email."},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            _send_otp(user)
        except Exception:
            return Response(
                {"error": "Could not send email. Please try again later."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {"message": f"A new code was sent to {email}."},
            status=status.HTTP_200_OK,
        )


# ==========================================
# 4. Custom Login Serializer + View
# ==========================================

class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        # is_active=False → SimpleJWT raises AuthenticationFailed automatically
        data = super().validate(attrs)
        data["user"] = UserProfileSerializer(self.user).data
        return data


class LoginView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer


# ==========================================
# 5. Profile View
# ==========================================

class ProfileView(generics.RetrieveUpdateAPIView):
    serializer_class   = UserProfileSerializer
    permission_classes = [IsAuthenticated]

    def get_object(self):
        return self.request.user


# ==========================================
# 6. Change Password View
# ==========================================

class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        user = request.user
        if not user.check_password(serializer.validated_data["old_password"]):
            return Response(
                {"old_password": "Wrong password."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.set_password(serializer.validated_data["new_password"])
        user.save()
        return Response(
            {"message": "Password changed successfully."},
            status=status.HTTP_200_OK,
        )


# ==========================================
# 7. Logout View
# ==========================================

class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            token = RefreshToken(request.data["refresh"])
            token.blacklist()
            return Response(
                {"message": "Logout successful."},
                status=status.HTTP_205_RESET_CONTENT,
            )
        except Exception:
            return Response(
                {"error": "Invalid token."},
                status=status.HTTP_400_BAD_REQUEST,
            )