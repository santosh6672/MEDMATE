import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'constants.dart';
import 'services/notification_service.dart';
import 'services/reminder_storage.dart';
import 'services/api_service.dart';
import 'screens/start_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  await initNotifications(
    onTaken: (baseId, medicineName) {
      ReminderStorage.markAsTakenByBaseId(baseId);
    },
  );

  // Show app immediately with a splash — auth check runs inside SplashScreen
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: kPrimary,
        scaffoldBackgroundColor: kBg,
      ),
      home: const _SplashScreen(),
    ),
  );
}

// ── Splash screen — shown instantly, does auth check in background ────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Run on next frame so splash renders first — prevents frame skipping
    await Future.microtask(() {});

    final prefs = await SharedPreferences.getInstance();
    final String? refreshToken = prefs.getString('refresh');

    bool isLoggedIn = false;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      // Silently get a new access token using saved refresh token
      isLoggedIn = await ApiService.refreshToken();
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            isLoggedIn ? const DashboardScreen() : const StartScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same look as StartScreen so transition feels seamless
    return Scaffold(
      backgroundColor: kPrimary,
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: kWhite,
              child: Icon(Icons.medical_services, size: 50, color: kPrimary),
            ),
            SizedBox(height: 20),
            Text(
              "MedMate",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: kWhite,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Your Smart Medicine Companion",
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(
              color: kWhite,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}