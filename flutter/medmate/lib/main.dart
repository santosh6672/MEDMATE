import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'services/api_service.dart';
import 'services/anchor_storage.dart';
import 'screens/dashboard_screen.dart';
import 'screens/start_screen.dart';
import 'screens/anchor_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Timezone initialization is no longer needed for native alarms.
  // initNotifications() is removed because we now use the native alarm system.

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
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
        primaryColor: kPrimary,
        scaffoldBackgroundColor: kBg,
        fontFamily: 'Roboto',
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
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh');

    bool isLoggedIn = false;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      isLoggedIn = await ApiService.refreshToken();
    }

    if (!mounted) return;

    Widget nextScreen = const StartScreen();
    if (isLoggedIn) {
      final hasAnchors = await AnchorStorage.hasAnchors();
      if (!mounted) return;
      nextScreen = hasAnchors ? const DashboardScreen() : const AnchorSetupScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
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
                radius: 50,
                backgroundColor: kWhite,
                child: Icon(Icons.medical_services, size: 50, color: kPrimary),
              ),
              const SizedBox(height: 20),
              const Text(
                'MedMate',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: kWhite,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your Smart Medicine Companion',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(
                color: kWhite,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}