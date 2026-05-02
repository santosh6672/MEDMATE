import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_storage.dart';
import '../utils/date_utils.dart';
import '../widgets/common_widgets.dart';
import 'change_password_screen.dart';
import 'start_screen.dart';
import 'anchor_setup_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool   _isLoading    = true;
  String _errorMessage = '';
  String _appVersion   = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      if (mounted) setState(() => _appVersion = '1.0.0');
    }
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading    = true;
      _errorMessage = '';
    });

    try {
      final prefs    = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? 'User';

      // Decode email from stored JWT access token payload.
      // dart:convert is imported at the top — no inline import needed.
      String email = '';
      final token = await ApiService.getAccessToken();
      if (token != null && token.isNotEmpty) {
        email = _emailFromJwt(token);
      }

      if (!mounted) return;
      setState(() {
        _profile = {'username': username, 'email': email};
        _isLoading = false;
      });
    } catch (_) {
      _setError('Could not load profile.');
    }
  }

  /// Decodes the email claim from a Supabase JWT payload.
  /// Supabase JWTs are standard base64url-encoded JSON.
  String _emailFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '';

      // Base64url → standard Base64 with padding
      String payload = parts[1]
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2: payload += '=='; break;
        case 3: payload += '=';  break;
        default: break;
      }

      final decoded = utf8.decode(base64.decode(payload));
      final map     = jsonDecode(decoded) as Map<String, dynamic>;
      return map['email'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _logout() async {
    await cancelAllNotifications();
    await ReminderStorage.clearAll();
    await ApiService.logout();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const StartScreen()),
      (_) => false,
    );
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading    = false;
    });
  }

  String get _initials {
    final name = (_profile?['username'] as String? ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding:    const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:        kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded, color: kRed, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Logout',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout?\nYour local reminders will be cleared.',
          style: TextStyle(height: 1.5, color: kTextGrey, fontSize: 14),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              side:    BorderSide(color: Colors.grey.shade300),
              shape:   RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text('Cancel',
                style: TextStyle(
                    color:      Colors.grey.shade700,
                    fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kRed,
              shape:   RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Logout',
                style: TextStyle(color: kWhite, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        elevation:       0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:    const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded,
                    size: 40, color: kTextGrey),
              ),
              const SizedBox(height: 16),
              ErrorBanner(message: _errorMessage),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon:  const Icon(Icons.refresh_rounded, color: kWhite),
                label: const Text('Retry',
                    style: TextStyle(
                        color: kWhite, fontWeight: FontWeight.w600)),
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
                    icon:  Icons.info_outline,
                    label: 'App Version',
                    value: _appVersion.isNotEmpty ? 'v$_appVersion' : '—',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ActionsCard(
                onEditSchedule: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AnchorSetupScreen()),
                ),
                onChangePassword: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen()),
                ),
                onLogout: _confirmLogout,
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ── Profile Header ─────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: const BoxDecoration(
        color:        kPrimary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius:          44,
                backgroundColor: kWhite,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color:         kPrimary,
                    fontSize:      30,
                    fontWeight:    FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right:  0,
                child: Container(
                  width:  18,
                  height: 18,
                  decoration: BoxDecoration(
                    color:  kAccent,
                    shape:  BoxShape.circle,
                    border: Border.all(color: kPrimary, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(username,
              style: const TextStyle(
                  color:         kWhite,
                  fontSize:      22,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 0.2)),
          const SizedBox(height: 4),
          Text(email,
              style: TextStyle(
                  color:    kWhite.withOpacity(0.75), fontSize: 14)),
        ],
      ),
    );
  }
}

// ── Info Card ──────────────────────────────────────────────────────────────────

class _ProfileRowData {
  final IconData icon;
  final String   label;
  final String   value;
  const _ProfileRowData(
      {required this.icon, required this.label, required this.value});
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
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _ProfileRow(
                icon: rows[i].icon,
                label: rows[i].label,
                value: rows[i].value),
            if (i < rows.length - 1)
              Divider(
                  height:    1,
                  indent:    52,
                  endIndent: 16,
                  color:     Colors.grey.shade100),
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

  const _ProfileRow(
      {required this.icon, required this.label, required this.value});

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
                Text(label,
                    style: const TextStyle(
                        fontSize:      11,
                        color:         kTextGrey,
                        fontWeight:    FontWeight.w500,
                        letterSpacing: 0.2)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                        color:      kTextDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Actions Card ───────────────────────────────────────────────────────────────

class _ActionsCard extends StatelessWidget {
  final VoidCallback onEditSchedule;
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;

  const _ActionsCard({
    required this.onEditSchedule,
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
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _ActionRow(
            icon:      Icons.schedule_rounded,
            label:     'Edit Daily Schedule',
            subtitle:  'Meals & wake/sleep times',
            iconColor: kPrimary,
            onTap:     onEditSchedule,
          ),
          Divider(
              height: 1, indent: 52, endIndent: 16,
              color: Colors.grey.shade100),
          _ActionRow(
            icon:      Icons.lock_reset_outlined,
            label:     'Change Password',
            subtitle:  'Update your account password',
            iconColor: kPrimary,
            onTap:     onChangePassword,
          ),
          Divider(
              height: 1, indent: 52, endIndent: 16,
              color: Colors.grey.shade100),
          _ActionRow(
            icon:       Icons.logout_rounded,
            label:      'Logout',
            subtitle:   'Sign out of your account',
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
  final String       subtitle;
  final Color        iconColor;
  final Color        labelColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                          color:      labelColor)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: kTextGrey)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}
