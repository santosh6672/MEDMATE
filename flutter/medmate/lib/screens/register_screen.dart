import 'dart:convert';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _nameFocus      = FocusNode();
  final _emailFocus     = FocusNode();
  final _passwordFocus  = FocusNode();
  final _confirmFocus   = FocusNode();

  final _nameController     = TextEditingController();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();

  bool   _isLoading      = false;
  bool   _obscurePass    = true;
  bool   _obscureConfirm = true;
  String _errorMessage   = '';

  @override
  void dispose() {
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ── Register ───────────────────────────────────────────────────────────────

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isLoading) return;

    setState(() {
      _isLoading    = true;
      _errorMessage = '';
    });

    try {
      final response = await ApiService.postWithAuth(
        '$kBaseUrl/api/users/register/',
        {
          'name':              _nameController.text.trim(),
          'email':             _emailController.text.trim().toLowerCase(),
          'password':          _passwordController.text,
          'password_confirm':  _confirmController.text,
        },
      );

      if (!mounted) return;

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final access  = data['access']  as String?;
        final refresh = data['refresh'] as String?;

        if (access == null || refresh == null) {
          _setError('Registration succeeded but login failed. Please sign in.');
          return;
        }

        await ApiService.saveTokens(access, refresh);

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (_) => false,
        );

      } else if (response.statusCode == 400) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final message = _extractError(data);
        _setError(message);

      } else {
        _setError('Registration failed (${response.statusCode}). Please try again.');
      }
    } on Exception {
      _setError('Cannot connect to server. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _extractError(Map<String, dynamic> data) {
    for (final key in ['email', 'password', 'name', 'non_field_errors', 'detail']) {
      final val = data[key];
      if (val is List && val.isNotEmpty) return val.first.toString();
      if (val is String && val.isNotEmpty) return val;
    }
    return 'Registration failed. Please check your details.';
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading    = false;
    });
  }

  // ── Validators ─────────────────────────────────────────────────────────────

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Name is required';
    if (v.trim().length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
        .hasMatch(v.trim());
    if (!valid) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation:       0,
        foregroundColor: kTextDark,
        title: const Text(
          'Create Account',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color:      kTextDark,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _RegisterHeader(),
                const SizedBox(height: 28),
                TextFormField(
                  controller:    _nameController,
                  focusNode:     _nameFocus,
                  decoration:    inputDecoration('Full Name', Icons.person_outline),
                  textInputAction: TextInputAction.next,
                  keyboardType:  TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_emailFocus),
                  validator: _validateName,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller:    _emailController,
                  focusNode:     _emailFocus,
                  decoration:    inputDecoration('Email', Icons.email_outlined),
                  keyboardType:  TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect:   false,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_passwordFocus),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller:     _passwordController,
                  focusNode:      _passwordFocus,
                  decoration:     inputDecoration(
                    'Password',
                    Icons.lock_outline,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: kTextGrey,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  obscureText:    _obscurePass,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_confirmFocus),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller:     _confirmController,
                  focusNode:      _confirmFocus,
                  decoration:     inputDecoration(
                    'Confirm Password',
                    Icons.lock_outline,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: kTextGrey,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  obscureText:    _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  validator: _validateConfirm,
                ),
                const SizedBox(height: 24),
                if (_errorMessage.isNotEmpty) ...[
                  ErrorBanner(message: _errorMessage),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isLoading ? null : _register,
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
                          'Create Account',
                          style: TextStyle(
                            fontSize:   16,
                            fontWeight: FontWeight.w600,
                            color:      kWhite,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: kTextGrey, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color:      kPrimary,
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _RegisterHeader extends StatelessWidget {
  const _RegisterHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:        kPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.person_add_outlined, color: kPrimary, size: 32),
        ),
        const SizedBox(height: 16),
        const Text(
          'Join MedMate',
          style: TextStyle(
            fontSize:   26,
            fontWeight: FontWeight.bold,
            color:      kTextDark,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Create your account to manage medications smarter.',
          style: TextStyle(fontSize: 14, color: kTextGrey),
        ),
      ],
    );
  }
}