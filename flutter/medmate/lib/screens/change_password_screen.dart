import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

// URL: POST /api/users/change-password/
// Body: { "old_password", "new_password" }

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final oldPasswordController     = TextEditingController();
  final newPasswordController     = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  String errorMessage = "";
  String successMessage = "";

  Future<void> changePassword() async {
    if (oldPasswordController.text.isEmpty ||
        newPasswordController.text.isEmpty ||
        confirmPasswordController.text.isEmpty) {
      setState(() => errorMessage = "Please fill in all fields.");
      return;
    }
    if (newPasswordController.text != confirmPasswordController.text) {
      setState(() => errorMessage = "New passwords do not match.");
      return;
    }

    setState(() { isLoading = true; errorMessage = ""; successMessage = ""; });

    try {
      final response = await ApiService.postWithAuth(
        "$kBaseUrl/api/users/change-password/",
        {"old_password": oldPasswordController.text, "new_password": newPasswordController.text},
      );

      if (response.statusCode == 200) {
        setState(() => successMessage = "Password changed successfully!");
        oldPasswordController.clear();
        newPasswordController.clear();
        confirmPasswordController.clear();
      } else if (response.statusCode == 400) {
        setState(() => errorMessage = "Old password is incorrect.");
      } else {
        setState(() => errorMessage = "Failed. Please try again.");
      }
    } catch (_) {
      setState(() => errorMessage = "Cannot connect to server.");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    oldPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Change Password"),
          backgroundColor: kPrimary, foregroundColor: kWhite),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Text("Change Password 🔒",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kTextDark)),
            const SizedBox(height: 6),
            const Text("Enter your old and new password",
                style: TextStyle(fontSize: 15, color: kTextGrey)),
            const SizedBox(height: 30),

            const Text("Current Password", style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark)),
            const SizedBox(height: 6),
            TextField(controller: oldPasswordController, obscureText: true,
                decoration: inputDecoration("Enter current password", Icons.lock_outline)),

            const SizedBox(height: 18),
            const Text("New Password", style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark)),
            const SizedBox(height: 6),
            TextField(controller: newPasswordController, obscureText: true,
                decoration: inputDecoration("Enter new password", Icons.lock_open)),

            const SizedBox(height: 18),
            const Text("Confirm New Password", style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark)),
            const SizedBox(height: 6),
            TextField(controller: confirmPasswordController, obscureText: true,
                decoration: inputDecoration("Re-enter new password", Icons.lock_open)),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: isLoading ? null : changePassword,
                child: isLoading
                    ? const CircularProgressIndicator(color: kWhite)
                    : const Text("Update Password", style: TextStyle(fontSize: 17, color: kWhite)),
              ),
            ),

            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              ErrorBanner(message: errorMessage),
            ],

            if (successMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: kAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(successMessage, style: const TextStyle(color: kAccent, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}