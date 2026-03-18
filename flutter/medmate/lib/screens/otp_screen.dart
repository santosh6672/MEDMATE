import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'dashboard_screen.dart';

// URL 1: POST /api/users/verify-otp/   Body: { "email", "otp" }
// URL 2: POST /api/users/resend-otp/   Body: { "email" }

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  // 6 individual controllers + focus nodes for auto-advance
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  bool   _isVerifying = false;
  bool   _isResending = false;
  String _errorMessage = "";
  String _successMessage = "";

  // ── Resend countdown ──────────────────────────────────────────────────────
  static const int _resendCooldown = 60; // seconds
  int  _secondsLeft = _resendCooldown;
  bool _canResend   = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _canResend   = false;
    _secondsLeft = _resendCooldown;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          _canResend = true;
          t.cancel();
        }
      });
    });
  }

  String get _enteredOtp =>
      _controllers.map((c) => c.text).join();

  // ── Verify ────────────────────────────────────────────────────────────────
  Future<void> _verify() async {
    if (_enteredOtp.length < 6) {
      setState(() => _errorMessage = "Please enter all 6 digits.");
      return;
    }

    setState(() { _isVerifying = true; _errorMessage = ""; _successMessage = ""; });

    try {
      final response = await http.post(
        Uri.parse("$kBaseUrl/api/users/verify-otp/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": widget.email, "otp": _enteredOtp}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await ApiService.saveTokens(data["access"], data["refresh"]);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
      } else {
        setState(() => _errorMessage = data["error"] ?? "Verification failed.");
        // Clear boxes on wrong OTP
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
      }
    } catch (_) {
      setState(() => _errorMessage = "Cannot connect to server.");
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  // ── Resend ────────────────────────────────────────────────────────────────
  Future<void> _resend() async {
    if (!_canResend) return;

    setState(() { _isResending = true; _errorMessage = ""; _successMessage = ""; });

    try {
      final response = await http.post(
        Uri.parse("$kBaseUrl/api/users/resend-otp/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": widget.email}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => _successMessage = "A new code was sent to ${widget.email}.");
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
        _startCountdown();
      } else {
        setState(() => _errorMessage = data["error"] ?? "Could not resend. Try again.");
      }
    } catch (_) {
      setState(() => _errorMessage = "Cannot connect to server.");
    } finally {
      setState(() => _isResending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify Email"),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const SizedBox(height: 16),

            // Icon + title
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: kPrimary, size: 48),
              ),
            ),

            const SizedBox(height: 24),

            const Center(
              child: Text("Check your inbox",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: kTextDark)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                "We sent a 6-digit code to\n${widget.email}",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: kTextGrey),
              ),
            ),

            const SizedBox(height: 36),

            // ── 6 OTP boxes ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) {
                return SizedBox(
                  width: 46,
                  height: 56,
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: kTextDark),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: kWhite,
                      counterText: "",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: kPrimary, width: 2)),
                    ),
                    onChanged: (val) {
                      if (val.isNotEmpty && i < 5) {
                        // Auto-advance to next box
                        _focusNodes[i + 1].requestFocus();
                      }
                      if (val.isEmpty && i > 0) {
                        // Auto-go-back on delete
                        _focusNodes[i - 1].requestFocus();
                      }
                      setState(() {});
                      // Auto-verify when all 6 filled
                      if (_enteredOtp.length == 6) _verify();
                    },
                  ),
                );
              }),
            ),

            const SizedBox(height: 28),

            // ── Verify button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: _isVerifying ? null : _verify,
                child: _isVerifying
                    ? const CircularProgressIndicator(color: kWhite)
                    : const Text("Verify & Continue",
                        style: TextStyle(fontSize: 17, color: kWhite)),
              ),
            ),

            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 14),
              ErrorBanner(message: _errorMessage),
            ],

            if (_successMessage.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kAccent.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: kAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_successMessage,
                        style: const TextStyle(
                            color: kAccent, fontSize: 14)),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 28),

            // ── Resend row ─────────────────────────────────────────────────
            Center(
              child: _isResending
                  ? const CircularProgressIndicator(color: kPrimary)
                  : Column(children: [
                      const Text("Didn't receive the code?",
                          style:
                              TextStyle(color: kTextGrey, fontSize: 13)),
                      const SizedBox(height: 6),
                      _canResend
                          ? GestureDetector(
                              onTap: _resend,
                              child: const Text("Resend Code",
                                  style: TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                            )
                          : Text(
                              "Resend in $_secondsLeft s",
                              style: const TextStyle(
                                  color: kTextGrey, fontSize: 13),
                            ),
                    ]),
            ),

          ],
        ),
      ),
    );
  }
}