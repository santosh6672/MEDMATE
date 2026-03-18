from rest_framework import serializers
from django.contrib.auth.models import User
from rest_framework.validators import UniqueValidator


# ── Password validator — min 8 characters ────────────────────────────────────
def validate_strong_password(value):
    if len(value) < 8:
        raise serializers.ValidationError(
            "Password must be at least 8 characters."
        )
    return value


# ===============================
# 1. User Registration Serializer
# ===============================

class UserRegistrationSerializer(serializers.ModelSerializer):

    email = serializers.EmailField(
        required=True,
        validators=[UniqueValidator(
            queryset=User.objects.all(),
            message="An account with this email already exists."
        )]
    )

    username = serializers.CharField(
        required=True,
        validators=[UniqueValidator(
            queryset=User.objects.all(),
            message="This username is already taken."
        )]
    )

    password = serializers.CharField(
        write_only=True,
        required=True,
        validators=[validate_strong_password]
    )

    password2 = serializers.CharField(
        write_only=True,
        required=True
    )

    class Meta:
        model = User
        fields = ('username', 'email', 'password', 'password2')

    def validate(self, attrs):
        if attrs['password'] != attrs['password2']:
            raise serializers.ValidationError(
                {"password": "Passwords do not match."}
            )
        return attrs

    def create(self, validated_data):
        validated_data.pop('password2')
        # Create user but mark as inactive until email is verified
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password'],
            is_active=False,   # ← blocked until OTP verified
        )
        return user


# ===============================
# 2. User Profile Serializer
# ===============================

class UserProfileSerializer(serializers.ModelSerializer):

    date_joined = serializers.DateTimeField(read_only=True)

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'first_name', 'last_name', 'date_joined')
        read_only_fields = ('id', 'username', 'date_joined')


# ===============================
# 3. Change Password Serializer
# ===============================

class ChangePasswordSerializer(serializers.Serializer):

    old_password = serializers.CharField(required=True)
    new_password = serializers.CharField(
        required=True,
        validators=[validate_strong_password]
    )
    confirm_password = serializers.CharField(required=True)

    def validate(self, attrs):
        if attrs['new_password'] != attrs['confirm_password']:
            raise serializers.ValidationError(
                {"new_password": "Passwords do not match."}
            )
        return attrs


# ===============================
# 4. OTP Verify Serializer
# ===============================

class OTPVerifySerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    otp   = serializers.CharField(required=True, min_length=6, max_length=6)