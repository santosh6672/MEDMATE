import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool   _isLoading   = false;
  bool   _showNew     = false;
  bool   _showConfirm = false;
  String _errorMessage   = '';
  String _successMessage = '';

  bool get _validLength => _newCtrl.text.length >= 8;
  bool get _match =>
      _newCtrl.text == _confirmCtrl.text && _confirmCtrl.text.isNotEmpty;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_newCtrl.text.isEmpty || _confirmCtrl.text.isEmpty) {
      _setError('Please fill in all fields.');
      return;
    }
    if (!_validLength) {
      _setError('Password must be at least 8 characters.');
      return;
    }
    if (!_match) {
      _setError('Passwords do not match.');
      return;
    }
    if (_isLoading) return;

    setState(() {
      _isLoading      = true;
      _errorMessage   = '';
      _successMessage = '';
    });

    try {
      // Supabase password update — uses the access token in the header.
      // No "old password" required; Supabase trusts the valid JWT.
      final token = await ApiService.getAccessToken();
      if (token == null || token.isEmpty) {
        _setError('Not authenticated. Please login again.');
        return;
      }

      final response = await ApiService.patchWithAuth(
        '$kSupabaseUrl/auth/v1/user',
        {'password': _newCtrl.text},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() => _successMessage = 'Password updated successfully');
        _newCtrl.clear();
        _confirmCtrl.clear();
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context);
      } else if (response.statusCode == 422) {
        _setError('New password is too weak. Use at least 8 characters.');
      } else {
        _setError('Failed (${response.statusCode}). Please try again.');
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
        title:           const Text('Change Password'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Note: Supabase doesn't require current password verification
              // via this endpoint — the valid JWT is proof of identity.
              Container(
                padding:     const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        kPrimary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: kPrimary.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: kPrimary, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enter your new password below. No current password needed.',
                        style: TextStyle(fontSize: 12, color: kPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller:  _newCtrl,
                obscureText: !_showNew,
                onChanged:   (_) => setState(() {}),
                decoration:  inputDecoration('New Password', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: kTextGrey,
                    ),
                    onPressed: () => setState(() => _showNew = !_showNew),
                  ),
                ),
              ),

              if (_newCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                _ValidationRow(ok: _validLength, label: 'At least 8 characters'),
              ],

              const SizedBox(height: 16),

              TextField(
                controller:  _confirmCtrl,
                obscureText: !_showConfirm,
                onChanged:   (_) => setState(() {}),
                decoration:  inputDecoration('Confirm Password', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: kTextGrey,
                    ),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
              ),

              if (_confirmCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                _ValidationRow(
                  ok:    _match,
                  label: _match ? 'Passwords match' : 'Passwords do not match',
                ),
              ],

              const SizedBox(height: 24),

              if (_errorMessage.isNotEmpty) ...[
                ErrorBanner(message: _errorMessage),
                const SizedBox(height: 12),
              ],

              if (_successMessage.isNotEmpty) ...[
                Container(
                  padding:     const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        kAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: kAccent.withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: kAccent),
                      SizedBox(width: 8),
                      Text('Password updated!',
                          style: TextStyle(color: kAccent)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading ? null : _changePassword,
                  child: _isLoading
                      ? const SizedBox(
                          width:  20,
                          height: 20,
                          child:  CircularProgressIndicator(
                            color:       kWhite,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Update Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValidationRow extends StatelessWidget {
  final bool   ok;
  final String label;

  const _ValidationRow({required this.ok, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          size:  14,
          color: ok ? kAccent : kRed,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: ok ? kAccent : kRed),
        ),
      ],
    );
  }
}
