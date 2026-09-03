import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'auth_repository.dart';
import 'first_login_screen.dart' show OtpInput, OtpInputState;
import 'login_screen.dart';
import 'sms_otp.dart';

/// Forgot password: username → one-time code on the registered mobile
/// (WhatsApp) → new password. Mirrors the web /forgot-password flow and the
/// first-login activation screen's look.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialUsername});

  /// Pre-filled from the login form so the user doesn't retype it.
  final String? initialUsername;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

enum _Step { username, verify }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  _Step _step = _Step.username;

  late final TextEditingController _username =
      TextEditingController(text: widget.initialUsername ?? '');
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  String _otp = '';

  String? _maskedPhone;
  int _expiresIn = 0;

  bool _loading = false;
  bool _done = false;
  String? _error;
  bool _o1 = true;
  bool _o2 = true;

  // OTP auto-read (SMS User Consent API — only helps when the code comes by
  // SMS; a WhatsApp code is typed by hand).
  final _smsOtp = SmsOtpListener();
  final _otpKey = GlobalKey<OtpInputState>();

  Timer? _timer;
  int _cooldown = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _smsOtp.cancel();
    _username.dispose();
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  void _listenForOtp() {
    _smsOtp.start(
      digits: 6,
      onCode: (code) {
        if (!mounted) return;
        _otpKey.currentState?.setCode(code);
        setState(() => _otp = code);
      },
    );
  }

  void _startCooldown([int seconds = 30]) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  void _back() {
    if (_loading) return;
    switch (_step) {
      case _Step.username:
        context.go('/login');
        break;
      case _Step.verify:
        _smsOtp.cancel();
        setState(() {
          _step = _Step.username;
          _error = null;
        });
        break;
    }
  }

  // ── Step 1: send OTP ──────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Enter your username (employee code).');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final res = await ref.read(authRepositoryProvider).forgotPassword(username);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _maskedPhone = res.maskedPhone;
        _expiresIn = res.expiresInSeconds;
        _otp = '';
        _step = _Step.verify;
      });
      _startCooldown();
      _listenForOtp();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_cooldown > 0 || _loading) return;
    try {
      final res = await ref
          .read(authRepositoryProvider)
          .forgotPassword(_username.text.trim());
      if (!mounted) return;
      setState(() {
        _maskedPhone = res.maskedPhone;
        _expiresIn = res.expiresInSeconds;
        _error = null;
      });
      _startCooldown();
      _listenForOtp();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _clean(e));
    }
  }

  // ── Step 2: verify OTP + set password ─────────────────────────────────────
  Future<void> _reset() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Enter the 6-digit code sent to your mobile.');
      return;
    }
    if (_p1.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_p1.text != _p2.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(
            username: _username.text.trim(),
            otp: _otp,
            newPassword: _p1.text,
          );
      if (!mounted) return;
      _smsOtp.cancel();
      setState(() {
        _loading = false;
        _done = true;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      context.go(
        '/login',
        extra: 'Password updated. Please sign in with your new password.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  /// ApiException.toString() is already the server message; strip the
  /// "Exception: " prefix a plain Exception would add.
  static String _clean(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.username:
        return _buildUsernameStep();
      case _Step.verify:
        return _buildVerifyStep();
    }
  }

  Widget _buildUsernameStep() {
    return AuthShell(
      title: 'Forgot password',
      subtitle: const Text(
        'Enter your username and we’ll send a one-time code to the mobile '
        'number on your employee record.',
      ),
      onBack: _back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('Username'),
          const SizedBox(height: 8),
          AuthTextField(
            controller: _username,
            hint: 'e.g. EMP-0001',
            prefixIcon: Icons.person_outline_rounded,
            enabled: !_loading,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [UpperCaseTextFormatter()],
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _sendOtp(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthFlashError(message: _error!),
          ],
          SizedBox(height: _error != null ? 16 : 22),
          AuthGradientButton(
            label: 'Send OTP',
            loading: _loading,
            done: false,
            onPressed: _loading ? null : _sendOtp,
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyStep() {
    final minutes = (_expiresIn / 60).round();
    return AuthShell(
      title: 'Reset password',
      subtitle: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Enter the 6-digit code sent to '),
            TextSpan(
              text: _maskedPhone ?? 'your registered mobile',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: minutes > 0
                  ? ' (valid for $minutes min) and choose a new password.'
                  : ' and choose a new password.',
            ),
          ],
        ),
      ),
      onBack: _back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('Verification code'),
          const SizedBox(height: 8),
          OtpInput(
            key: _otpKey,
            length: 6,
            onChanged: (v) => setState(() => _otp = v),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: (_loading || _cooldown > 0) ? null : _resendOtp,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.muted),
                    children: [
                      const TextSpan(text: "Didn't get it? "),
                      TextSpan(
                        text: _cooldown > 0
                            ? 'Resend in ${_cooldown}s'
                            : 'Resend',
                        style: TextStyle(
                          color: _cooldown > 0
                              ? AppColors.muted
                              : AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const AuthFieldLabel('New password'),
          const SizedBox(height: 8),
          AuthTextField(
            controller: _p1,
            hint: 'At least 8 characters',
            prefixIcon: Icons.lock_outline_rounded,
            obscure: _o1,
            enabled: !_loading,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            suffix: IconButton(
              splashRadius: 18,
              icon: Icon(
                _o1 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.muted,
                size: 19,
              ),
              onPressed: () => setState(() => _o1 = !_o1),
            ),
          ),
          const SizedBox(height: 14),
          const AuthFieldLabel('Confirm new password'),
          const SizedBox(height: 8),
          AuthTextField(
            controller: _p2,
            hint: 'Re-enter new password',
            prefixIcon: Icons.lock_outline_rounded,
            obscure: _o2,
            enabled: !_loading,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _reset(),
            suffix: IconButton(
              splashRadius: 18,
              icon: Icon(
                _o2 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.muted,
                size: 19,
              ),
              onPressed: () => setState(() => _o2 = !_o2),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthFlashError(message: _error!),
          ],
          SizedBox(height: _error != null ? 16 : 22),
          AuthGradientButton(
            label: 'Update password',
            loading: _loading,
            done: _done,
            onPressed: (_loading || _done) ? null : _reset,
          ),
        ],
      ),
    );
  }
}
