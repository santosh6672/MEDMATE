from django.urls import path
from . import views
from rest_framework_simplejwt.views import TokenRefreshView

urlpatterns = [
    path('register/',    views.RegisterView.as_view(),      name='register'),
    path('login/',       views.LoginView.as_view(),          name='login'),
    path('profile/',     views.ProfileView.as_view(),        name='profile'),
    path('change-password/', views.ChangePasswordView.as_view(), name='change-password'),
    path('logout/',      views.LogoutView.as_view(),         name='logout'),

    # JWT Refresh
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]