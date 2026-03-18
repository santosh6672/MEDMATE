import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_storage.dart';
import '../widgets/common_widgets.dart';
import 'start_screen.dart';
import 'change_password_screen.dart';

// URL 1: GET  /api/users/profile/
// URL 2: POST /api/users/logout/

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    setState(() { isLoading = true; errorMessage = ""; });
    try {
      final response = await ApiService.getWithAuth("$kBaseUrl/api/users/profile/");
      if (response.statusCode == 200) {
        setState(() { profile = jsonDecode(response.body); isLoading = false; });
      } else {
        setState(() { errorMessage = "Failed to load profile."; isLoading = false; });
      }
    } catch (_) {
      setState(() { errorMessage = "Cannot connect to server."; isLoading = false; });
    }
  }

  Future<void> logout() async {
    // 1. Cancel all notifications + clear this user's local medicine data
    await cancelAllNotifications();
    await ReminderStorage.clearAll();

    // 2. Blacklist the refresh token on Django
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? refresh = prefs.getString("refresh");
      await ApiService.postWithAuth(
          "$kBaseUrl/api/users/logout/", {"refresh": refresh ?? ""});
    } catch (_) {}

    // 3. Clear saved tokens from device storage
    await ApiService.clearTokens();

    // 4. Go to StartScreen, remove all previous routes
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const StartScreen()),
      (route) => false,
    );
  }

  void confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () { Navigator.pop(context); logout(); },
            child: const Text("Logout", style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("My Profile"),
          backgroundColor: kPrimary,
          foregroundColor: kWhite),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ErrorBanner(message: errorMessage)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const CircleAvatar(
                          radius: 44,
                          backgroundColor: kPrimary,
                          child: Icon(Icons.person, size: 44, color: kWhite)),
                      const SizedBox(height: 14),
                      Text(profile?["username"] ?? "—",
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: kTextDark)),
                      const SizedBox(height: 4),
                      Text(profile?["email"] ?? "—",
                          style: const TextStyle(
                              fontSize: 15, color: kTextGrey)),
                      const SizedBox(height: 30),

                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                        child: Column(children: [
                          _ProfileRow(
                              icon: Icons.person_outline,
                              label: "Username",
                              value: profile?["username"] ?? "—"),
                          const Divider(height: 1),
                          _ProfileRow(
                              icon: Icons.email_outlined,
                              label: "Email",
                              value: profile?["email"] ?? "—"),
                          const Divider(height: 1),
                          _ProfileRow(
                            icon: Icons.calendar_today_outlined,
                            label: "Joined",
                            value: profile?["date_joined"] != null
                                ? profile!["date_joined"]
                                    .toString()
                                    .substring(0, 10)
                                : "—",
                          ),
                        ]),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: kPrimary),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const ChangePasswordScreen())),
                          icon: const Icon(Icons.lock_reset, color: kPrimary),
                          label: const Text("Change Password",
                              style:
                                  TextStyle(color: kPrimary, fontSize: 15)),
                        ),
                      ),

                      const SizedBox(height: 14),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: kRed,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          onPressed: confirmLogout,
                          icon: const Icon(Icons.logout, color: kWhite),
                          label: const Text("Logout",
                              style:
                                  TextStyle(color: kWhite, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: kPrimary, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(fontSize: 14, color: kTextGrey)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kTextDark)),
      ]),
    );
  }
}