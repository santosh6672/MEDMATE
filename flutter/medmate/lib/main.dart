import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'constants.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/reminder_storage.dart';
import 'screens/dashboard_screen.dart';
import 'screens/start_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  await initNotifications();

  runApp(const MedMateApp());
}

class MedMateApp extends StatelessWidget {
  const MedMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MedMate',
      theme: ThemeData(
        colorScheme:             ColorScheme.fromSeed(seedColor: kPrimary),
        primaryColor:            kPrimary,
        scaffoldBackgroundColor: kBg,
        fontFamily:              'Roboto',
      ),
      home: const _SplashScreen(),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _checkAuth() async {
    final prefs        = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh');

    bool isLoggedIn = false;
    if (refreshToken != null && refreshToken.isNotEmpty) {
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
    return Scaffold(
      backgroundColor: kPrimary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius:          50,
                backgroundColor: kWhite,
                child: Icon(Icons.medical_services, size: 50, color: kPrimary),
              ),
              const SizedBox(height: 20),
              const Text(
                'MedMate',
                style: TextStyle(
                  fontSize:   36,
                  fontWeight: FontWeight.bold,
                  color:      kWhite,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your Smart Medicine Companion',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(
                color:       kWhite,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}