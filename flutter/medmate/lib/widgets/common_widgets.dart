import 'package:flutter/material.dart';

import '../constants.dart';

class ErrorBanner extends StatelessWidget {
  final String message;

  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kRed.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: kRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: kRed, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class DashCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final Color color;
  final VoidCallback onTap;

  const DashCard({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kTextDark,
              ),
            ),
            if (description != null)
              Text(
                description!,
                style: const TextStyle(fontSize: 11, color: kTextGrey),
              ),
          ],
        ),
      ),
    );
  }
}

InputDecoration inputDecoration(String hint, IconData icon) {
  return InputDecoration(
    hintText:   hint,
    prefixIcon: Icon(icon, color: kPrimary),
    filled:     true,
    fillColor:  kWhite,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: Color(0xFFE0E0E0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: kPrimary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: kRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: kRed, width: 2),
    ),
  );
}