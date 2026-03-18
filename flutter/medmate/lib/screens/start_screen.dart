import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../constants.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _fadeController;
  late Animation<double> _floatAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _floatAnim = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _floatController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Background gradient ──────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kPrimary,
                  kPrimary.withBlue(210),
                  const Color(0xFF0A5F4B),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // ── Decorative circles ───────────────────────────────────────────
          Positioned(
            top: -60,
            right: -60,
            child: _DecorCircle(size: 220, opacity: 0.07),
          ),
          Positioned(
            top: 80,
            right: -30,
            child: _DecorCircle(size: 120, opacity: 0.05),
          ),
          Positioned(
            top: 160,
            left: -80,
            child: _DecorCircle(size: 200, opacity: 0.06),
          ),

          // ── Cross / plus icons scattered ─────────────────────────────────
          ..._buildCrossIcons(),

          SafeArea(
            child: Column(
              children: [
                // ── Logo section ─────────────────────────────────────────
                Expanded(
                  flex: 11,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Floating logo
                        AnimatedBuilder(
                          animation: _floatAnim,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(0, -_floatAnim.value),
                            child: child,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer glow ring
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              // Inner ring
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.15),
                                ),
                              ),
                              // Icon
                              Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: kWhite,
                                ),
                                child: const Icon(
                                  Icons.medical_services_rounded,
                                  size: 42,
                                  color: kPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // App name
                        const Text(
                          "MedMate",
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: kWhite,
                            letterSpacing: 1.5,
                            height: 1.0,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Tagline with pill background
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "Your Smart Medicine Companion",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),

                        const SizedBox(height: 48),

                        // Feature chips row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _FeatureChip(icon: Icons.document_scanner_outlined, label: "Scan Rx"),
                              const SizedBox(width: 10),
                              _FeatureChip(icon: Icons.alarm_outlined, label: "Reminders"),
                              const SizedBox(width: 10),
                              _FeatureChip(icon: Icons.track_changes_outlined, label: "Track"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bottom sheet ─────────────────────────────────────────
                SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                      decoration: const BoxDecoration(
                        color: kWhite,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(36)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle bar
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),

                          const Text(
                            "Get Started",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: kTextDark,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            "Manage your medicines the smart way",
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade500),
                          ),

                          const SizedBox(height: 24),

                          // Login button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen())),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.login_rounded,
                                      color: kWhite, size: 20),
                                  SizedBox(width: 8),
                                  Text("Login",
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: kWhite)),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Register button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: kPrimary.withOpacity(0.5), width: 1.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const RegisterScreen())),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_add_outlined,
                                      color: kPrimary, size: 20),
                                  SizedBox(width: 8),
                                  Text("Create Account",
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: kPrimary)),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCrossIcons() {
    final positions = [
      [0.15, 0.22],
      [0.78, 0.15],
      [0.88, 0.38],
      [0.08, 0.45],
      [0.65, 0.52],
      [0.25, 0.58],
    ];

    return positions.map((pos) {
      return Positioned(
        left: MediaQuery.of(context).size.width * pos[0],
        top: MediaQuery.of(context).size.height * pos[1],
        child: Transform.rotate(
          angle: math.pi / 6,
          child: Icon(
            Icons.add,
            color: Colors.white.withOpacity(0.07),
            size: 28,
          ),
        ),
      );
    }).toList();
  }
}

// ── Decorative circle ─────────────────────────────────────────────────────────
class _DecorCircle extends StatelessWidget {
  final double size;
  final double opacity;
  const _DecorCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }
}

// ── Feature chip ──────────────────────────────────────────────────────────────
class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kWhite, size: 14),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: kWhite, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}