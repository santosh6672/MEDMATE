import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../widgets/common_widgets.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl  = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _password2Ctrl = TextEditingController();

  bool   _isLoading     = false;
  bool   _showPassword  = false;
  bool   _showPassword2 = false;
  String _errorMessage  = "";

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool get _hasLength     => _passwordCtrl.text.length >= 8;
  bool get _passwordsMatch =>
      _passwordCtrl.text == _password2Ctrl.text &&
      _password2Ctrl.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnim  = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _password2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username  = _usernameCtrl.text.trim();
    final email     = _emailCtrl.text.trim();
    final password  = _passwordCtrl.text;
    final password2 = _password2Ctrl.text;

    if (username.isEmpty || email.isEmpty ||
        password.isEmpty || password2.isEmpty) {
      setState(() => _errorMessage = "Please fill in all fields.");
      return;
    }
    if (!_hasLength) {
      setState(() => _errorMessage = "Password must be at least 8 characters.");
      return;
    }
    if (password != password2) {
      setState(() => _errorMessage = "Passwords do not match.");
      return;
    }

    setState(() { _isLoading = true; _errorMessage = ""; });

    try {
      final response = await http.post(
        Uri.parse("$kBaseUrl/api/users/register/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username":  username,
          "email":     email,
          "password":  password,
          "password2": password2,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => OtpScreen(email: data["email"] ?? email)),
        );
      } else {
        String msg = "";
        if (data is Map) {
          msg = data.values
              .map((v) => v is List ? v.join(" ") : v.toString())
              .join("\n");
        } else {
          msg = data.toString();
        }
        setState(() => _errorMessage = msg);
      }
    } catch (_) {
      setState(() => _errorMessage = "Cannot connect to server.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      body: Column(
        children: [
          // ── Top green header ───────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kPrimary, kPrimary.withBlue(210)],
              ),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: kWhite, size: 16),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Create\nAccount 👤",
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: kWhite,
                        height: 1.2)),
                const SizedBox(height: 6),
                Text("Join MedMate and stay on track",
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8))),
              ],
            ),
          ),

          // ── Form ──────────────────────────────────────────────────────
          Expanded(
            child: SlideTransition(
              position: _slideAnim,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Username ────────────────────────────────────────
                      _FieldLabel("Username"),
                      _StyledField(
                        controller: _usernameCtrl,
                        hint: "Choose a username",
                        icon: Icons.person_outline_rounded,
                      ),

                      const SizedBox(height: 18),

                      // ── Email ───────────────────────────────────────────
                      _FieldLabel("Email"),
                      _StyledField(
                        controller: _emailCtrl,
                        hint: "Enter your email",
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),

                      const SizedBox(height: 18),

                      // ── Password ────────────────────────────────────────
                      _FieldLabel("Password"),
                      _StyledField(
                        controller: _passwordCtrl,
                        hint: "At least 8 characters",
                        icon: Icons.lock_outline_rounded,
                        obscure: !_showPassword,
                        onChanged: (_) => setState(() {}),
                        suffix: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: kTextGrey, size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),

                      if (_passwordCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ValidationRow(
                          passed: _hasLength,
                          label: "At least 8 characters",
                        ),
                      ],

                      const SizedBox(height: 18),

                      // ── Confirm Password ────────────────────────────────
                      _FieldLabel("Confirm Password"),
                      _StyledField(
                        controller: _password2Ctrl,
                        hint: "Re-enter your password",
                        icon: Icons.lock_outline_rounded,
                        obscure: !_showPassword2,
                        onChanged: (_) => setState(() {}),
                        suffix: IconButton(
                          icon: Icon(
                            _showPassword2
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: kTextGrey, size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword2 = !_showPassword2),
                        ),
                        enabledBorder: _password2Ctrl.text.isNotEmpty
                            ? OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _passwordsMatch ? kAccent : kRed,
                                  width: 1.5,
                                ),
                              )
                            : null,
                      ),

                      if (_password2Ctrl.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ValidationRow(
                          passed: _passwordsMatch,
                          label: _passwordsMatch
                              ? "Passwords match"
                              : "Passwords do not match",
                        ),
                      ],

                      const SizedBox(height: 30),

                      // ── Register button ─────────────────────────────────
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
                          onPressed: _isLoading ? null : _register,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: kWhite, strokeWidth: 2.5))
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text("Create Account",
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: kWhite)),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded,
                                        color: kWhite, size: 18),
                                  ],
                                ),
                        ),
                      ),

                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _ErrorCard(message: _errorMessage),
                      ],

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Already have an account? ",
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 14)),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text("Login",
                                style: TextStyle(
                                    color: kPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kTextDark,
                letterSpacing: 0.3)),
      );
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final void Function(String)? onChanged;
  final TextInputType? keyboardType;
  final OutlineInputBorder? enabledBorder;

  const _StyledField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.keyboardType,
    this.enabledBorder,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: kTextDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(icon, color: kPrimary, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: kWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: enabledBorder ??
            OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kPrimary, width: 1.5),
        ),
      ),
    );
  }
}

class _ValidationRow extends StatelessWidget {
  final bool passed;
  final String label;
  const _ValidationRow({required this.passed, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(
        passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
        size: 15,
        color: passed ? kAccent : kRed,
      ),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontSize: 12,
              color: passed ? kAccent : kRed,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRed.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, color: kRed, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: TextStyle(color: kRed, fontSize: 13))),
      ]),
    );
  }
}