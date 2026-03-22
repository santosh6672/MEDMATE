import 'package:flutter/material.dart';

import '../constants.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

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
              child: _HeroSection(size: size),
            ),
            Expanded(
              flex: 4,
              child: _BottomPanel(size: size),
            ),
          ],
        ),
      ),
    );
  }
}

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
          Container(
            width:  size.width * 0.38,
            height: size.width * 0.38,
            decoration: BoxDecoration(
              color:        kWhite.withOpacity(0.15),
              shape:        BoxShape.circle,
              border:       Border.all(color: kWhite.withOpacity(0.3), width: 2),
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              size:  80,
              color: kWhite,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'MedMate',
            style: TextStyle(
              fontSize:      40,
              fontWeight:    FontWeight.bold,
              color:         kWhite,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your Smart Medicine Companion',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color:    Colors.white70,
              height:   1.5,
            ),
          ),
          const SizedBox(height: 16),
          _FeatureRow(
            items: const [
              (Icons.notifications_active_rounded, 'Smart\nReminders'),
              (Icons.document_scanner_rounded,     'Scan\nPrescriptions'),
              (Icons.insights_rounded,             'Track\nAdherence'),
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
      children: items
          .map(
            (item) => _FeatureChip(icon: item.$1, label: item.$2),
          )
          .toList(),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String   label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:        kWhite.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: kWhite, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color:    Colors.white70,
            fontSize: 11,
            height:   1.3,
          ),
        ),
      ],
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final Size size;

  const _BottomPanel({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:       double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
      decoration: const BoxDecoration(
        color:        kWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Get Started',
            style: TextStyle(
              fontSize:   26,
              fontWeight: FontWeight.bold,
              color:      kTextDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Manage your medications smarter.',
            style: TextStyle(fontSize: 14, color: kTextGrey),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: kPrimary,
              padding:         const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Sign In',
              style: TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.w600,
                color:      kWhite,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegisterScreen()),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side:    const BorderSide(color: kPrimary, width: 1.5),
              shape:   RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Create Account',
              style: TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.w600,
                color:      kPrimary,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'By continuing you agree to our Terms & Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: kTextGrey),
          ),
        ],
      ),
    );
  }
}