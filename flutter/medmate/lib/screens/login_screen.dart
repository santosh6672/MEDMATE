import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../services/reminder_storage.dart';
import '../services/anchor_storage.dart';
import '../widgets/common_widgets.dart';
import 'dashboard_screen.dart';
import 'register_screen.dart';
import 'anchor_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  bool   _isLoading    = false;
  bool   _showPassword = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email    = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _setError('Please fill in all fields.');
      return;
    }

    if (_isLoading) return;

    setState(() {
      _isLoading    = true;
      _errorMessage = '';
    });

    try {
      // Supabase login — returns access_token + refresh_token
      final data = await ApiService.login(email, password);

      if (!mounted) return;

      if (data != null) {
        await ReminderStorage.clearAll();

        // Save display name from Supabase user metadata if available
        final userMeta = data['user']?['user_metadata'] as Map<String, dynamic>?;
        final username = userMeta?['username'] as String?
            ?? userMeta?['full_name'] as String?
            ?? email.split('@').first;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', username);

        final hasAnchors = await AnchorStorage.hasAnchors();
        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => hasAnchors
                ? const DashboardScreen()
                : const AnchorSetupScreen(),
          ),
          (_) => false,
        );
      } else {
        _setError('Wrong email or password.');
      }
    } catch (_) {
      _setError('Cannot connect to server.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading    = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title:           const Text('Login'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              TextField(
                controller:   _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration:   inputDecoration('Email', Icons.email_outlined),
              ),

              const SizedBox(height: 16),

              TextField(
                controller:  _passwordController,
                obscureText: !_showPassword,
                decoration:  inputDecoration('Password', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: kTextGrey,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (_errorMessage.isNotEmpty) ...[
                ErrorBanner(message: _errorMessage),
                const SizedBox(height: 16),
              ],

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width:  22,
                          height: 22,
                          child:  CircularProgressIndicator(
                            color:       kWhite,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(
                            fontSize:   16,
                            fontWeight: FontWeight.w600,
                            color:      kWhite,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: kTextGrey),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterScreen(),
                      ),
                    ),
                    child: const Text(
                      'Register',
                      style: TextStyle(
                        color:      kPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
