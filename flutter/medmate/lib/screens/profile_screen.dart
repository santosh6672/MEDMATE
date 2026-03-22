import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_storage.dart';
import '../widgets/common_widgets.dart';
import 'change_password_screen.dart';
import 'start_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool   _isLoading    = true;
  String _errorMessage = '';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading    = true;
      _errorMessage = '';
    });

    try {
      final response = await ApiService.getWithAuth(
        '$kBaseUrl/api/users/profile/',
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          setState(() {
            _profile   = data;
            _isLoading = false;
          });
        } else {
          _setError('Unexpected response from server.');
        }
      } else {
        _setError('Failed to load profile (${response.statusCode}).');
      }
    } on Exception {
      _setError('Cannot connect to server. Check your internet connection.');
    }
  }

  Future<void> _logout() async {
    await cancelAllNotifications();
    await ReminderStorage.clearAll();

    try {
      final prefs   = await SharedPreferences.getInstance();
      final refresh = prefs.getString('refresh') ?? '';
      if (refresh.isNotEmpty) {
        await ApiService.postWithAuth(
          '$kBaseUrl/api/users/logout/',
          {'refresh': refresh},
        );
      }
    } on Exception {
      // Server-side logout is best-effort; proceed regardless.
    }

    await ApiService.clearTokens();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const StartScreen()),
      (_) => false,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading    = false;
    });
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
    }
  }

  String get _initials {
    final name = (_profile?['username'] as String? ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to logout?\nYour reminders will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Logout', style: TextStyle(color: kWhite)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        elevation:       0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kPrimary),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ErrorBanner(message: _errorMessage),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadProfile,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color:     kPrimary,
      onRefresh: _loadProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _ProfileHeader(
              initials: _initials,
              username: _profile?['username'] as String? ?? '—',
              email:    _profile?['email']    as String? ?? '—',
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _InfoCard(
                rows: [
                  _ProfileRowData(
                    icon:  Icons.person_outline,
                    label: 'Username',
                    value: _profile?['username'] as String? ?? '—',
                  ),
                  _ProfileRowData(
                    icon:  Icons.email_outlined,
                    label: 'Email',
                    value: _profile?['email'] as String? ?? '—',
                  ),
                  _ProfileRowData(
                    icon:  Icons.calendar_today_outlined,
                    label: 'Member since',
                    value: _formatDate(_profile?['date_joined'] as String?),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ActionsCard(
                onChangePassword: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
                onLogout: _confirmLogout,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'MedMate v1.0.0',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Profile header ─────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String initials;
  final String username;
  final String email;

  const _ProfileHeader({
    required this.initials,
    required this.username,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      decoration: const BoxDecoration(
        color:        kPrimary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width:  80,
            height: 80,
            decoration: BoxDecoration(
              color:  Colors.white.withOpacity(0.2),
              shape:  BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color:      kWhite,
                  fontSize:   28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            username,
            style: const TextStyle(
              color:      kWhite,
              fontSize:   20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: TextStyle(
              color:    Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info card ──────────────────────────────────────────────────────────────────

class _ProfileRowData {
  final IconData icon;
  final String   label;
  final String   value;

  const _ProfileRowData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _InfoCard extends StatelessWidget {
  final List<_ProfileRowData> rows;

  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        kWhite,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _ProfileRow(
              icon:  rows[i].icon,
              label: rows[i].label,
              value: rows[i].value,
            ),
            if (i < rows.length - 1)
              const Divider(height: 1, indent: 52, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width:  36,
            height: 36,
            decoration: BoxDecoration(
              color:        kPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPrimary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize:   11,
                    color:      kTextGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                    color:      kTextDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Actions card ───────────────────────────────────────────────────────────────

class _ActionsCard extends StatelessWidget {
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;

  const _ActionsCard({
    required this.onChangePassword,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        kWhite,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _ActionRow(
            icon:      Icons.lock_reset_outlined,
            label:     'Change Password',
            iconColor: kPrimary,
            onTap:     onChangePassword,
          ),
          const Divider(height: 1, indent: 52, endIndent: 16),
          _ActionRow(
            icon:       Icons.logout_rounded,
            label:      'Logout',
            iconColor:  kRed,
            labelColor: kRed,
            onTap:      onLogout,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        iconColor;
  final Color        labelColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.labelColor = kTextDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width:  36,
              height: 36,
              decoration: BoxDecoration(
                color:        iconColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize:   14,
                  fontWeight: FontWeight.w600,
                  color:      labelColor,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}