import 'package:flutter/material.dart';

import '../constants.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: kPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideUp,
                  child: _HeroSection(size: size),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: FadeTransition(
                opacity: _fadeIn,
                child: _BottomPanel(size: size),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero Section ───────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final Size size;
  const _HeroSection({required this.size});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Layered icon with glow effect
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size.width * 0.44,
                height: size.width * 0.44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kWhite.withOpacity(0.06),
                ),
              ),
              Container(
                width: size.width * 0.36,
                height: size.width * 0.36,
                decoration: BoxDecoration(
                  color: kWhite.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: kWhite.withOpacity(0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: kWhite.withOpacity(0.12),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.medication_rounded,
                  size: 72,
                  color: kWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'MedMate',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: kWhite,
              letterSpacing: 1.4,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your Smart Medicine Companion',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white70,
              height: 1.5,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 28),
          _FeatureRow(
            items: const [
              (Icons.notifications_active_rounded, 'Smart\nReminders'),
              (Icons.document_scanner_rounded, 'Scan\nPrescriptions'),
              (Icons.insights_rounded, 'Track\nAdherence'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final List<(IconData, String)> items;
  const _FeatureRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) {
        return _FeatureChip(icon: item.$1, label: item.$2);
      }).toList(),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kWhite.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kWhite.withOpacity(0.2), width: 1),
          ),
          child: Icon(icon, color: kWhite, size: 22),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Bottom Panel ───────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final Size size;
  const _BottomPanel({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      decoration: const BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with pill badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Get Started',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: kTextDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Manage your medications smarter.',
                      style: TextStyle(
                        fontSize: 14,
                        color: kTextGrey,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: kPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Free',
                      style: TextStyle(
                        fontSize: 11,
                        color: kPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Sign In button
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: kPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Sign In',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kWhite,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Create Account button
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegisterScreen()),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: kPrimary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Create Account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kPrimary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'By continuing you agree to our Terms & Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: kTextGrey, height: 1.4),
          ),
        ],
      ),
    );
  }
}