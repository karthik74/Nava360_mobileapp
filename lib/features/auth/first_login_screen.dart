import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'auth_repository.dart';
import 'login_screen.dart';
import 'sms_otp.dart';

/// First-time login / account activation:
/// 1. Enter Employee Code → OTP sent to the registered mobile.
/// 2. Verify the 6-digit OTP → receive a short-lived setup token.
/// 3. Set a permanent password → sign in.
class FirstLoginScreen extends ConsumerStatefulWidget {
  const FirstLoginScreen({super.key});

  @override
  ConsumerState<FirstLoginScreen> createState() => _FirstLoginScreenState();
}

enum _Step { code, otp, password }

class _FirstLoginScreenState extends ConsumerState<FirstLoginScreen> {
  _Step _step = _Step.code;

  final _code = TextEditingController();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  String _otp = '';

  String? _maskedMobile;
  String _setupToken = '';

  bool _loading = false;
  bool _done = false;
  String? _error;
  bool _o1 = true;
  bool _o2 = true;

  // OTP SMS auto-read (SMS User Consent API — no READ_SMS permission).
  final _smsOtp = SmsOtpListener();
  final _otpKey = GlobalKey<OtpInputState>();

  // Resend cooldown.
  Timer? _timer;
  int _cooldown = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _smsOtp.cancel();
    _code.dispose();
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  /// Begin listening for the incoming OTP so it auto-fills the boxes.
  void _listenForOtp() {
    _smsOtp.start(
      digits: 6,
      onCode: (code) {
        if (!mounted) return;
        _otpKey.currentState?.setCode(code);
        setState(() => _otp = code);
        // Auto-verify once the code is complete.
        if (code.length >= 6 && !_loading) _verifyOtp();
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
      case _Step.code:
        context.go('/login');
        break;
      case _Step.otp:
        _smsOtp.cancel();
        setState(() {
          _step = _Step.code;
          _error = null;
        });
        break;
      case _Step.password:
        setState(() {
          _step = _Step.otp;
          _error = null;
        });
        break;
    }
  }

  // ── Step 1: send OTP ──────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your employee code.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final res = await ref.read(authRepositoryProvider).firstLoginStart(code);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _maskedMobile = res.maskedMobile;
        _otp = '';
        _step = _Step.otp;
      });
      _startCooldown();
      _listenForOtp();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_cooldown > 0) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .firstLoginResendOtp(_code.text.trim());
      if (!mounted) return;
      _startCooldown();
      _listenForOtp();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  // ── Step 2: verify OTP ────────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Enter the 6-digit code sent to your mobile.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final res = await ref
          .read(authRepositoryProvider)
          .firstLoginVerifyOtp(_code.text.trim(), _otp);
      if (!mounted) return;
      _smsOtp.cancel();
      setState(() {
        _loading = false;
        _setupToken = res.setupToken;
        _step = _Step.password;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Step 3: set password ──────────────────────────────────────────────────
  Future<void> _setPassword() async {
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
      await ref.read(authRepositoryProvider).firstLoginSetPassword(
            employeeCode: _code.text.trim(),
            setupToken: _setupToken,
            newPassword: _p1.text,
            confirmPassword: _p2.text,
          );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _done = true;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      context.go(
        '/login',
        extra: 'Account activated. Please sign in with your new password.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.code:
        return _buildCodeStep();
      case _Step.otp:
        return _buildOtpStep();
      case _Step.password:
        return _buildPasswordStep();
    }
  }

  // ── Step 1 UI ─────────────────────────────────────────────────────────────
  Widget _buildCodeStep() {
    return AuthShell(
      header: 'First login',
      steps: _kSteps,
      step: 0,
      icon: Icons.badge_outlined,
      title: 'Activate account',
      subtitle: const Text(
        'First time signing in? Enter your employee code and we’ll send a '
        'one-time code to your registered mobile number.',
      ),
      onBack: _back,
      action: AuthGradientButton(
        label: 'Send OTP',
        loading: _loading,
        done: false,
        onPressed: _loading ? null : _sendOtp,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('Employee code'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _code,
            hint: 'e.g. EMP-0001',
            prefixIcon: Icons.badge_outlined,
            enabled: !_loading,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseTextFormatter()],
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _sendOtp(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AuthFlashError(message: _error!),
          ],
        ],
      ),
    );
  }

  // ── Step 2 UI ─────────────────────────────────────────────────────────────
  Widget _buildOtpStep() {
    return AuthShell(
      header: 'First login',
      steps: _kSteps,
      step: 1,
      icon: Icons.sms_outlined,
      title: 'Verify OTP',
      subtitle: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Enter the 6-digit code sent to '),
            TextSpan(
              text: _maskedMobile ?? 'your registered mobile',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
      onBack: _back,
      action: AuthGradientButton(
        label: 'Verify',
        loading: _loading,
        done: false,
        onPressed: _loading ? null : _verifyOtp,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('Verification code'),
          const SizedBox(height: 6),
          OtpInput(
            key: _otpKey,
            length: 6,
            onChanged: (v) => setState(() => _otp = v),
          ),
          const SizedBox(height: 4),
          OtpResendRow(
            cooldown: _cooldown,
            onResend: (_loading || _cooldown > 0) ? null : _resendOtp,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            AuthFlashError(message: _error!),
          ],
        ],
      ),
    );
  }

  // ── Step 3 UI ─────────────────────────────────────────────────────────────
  Widget _buildPasswordStep() {
    return AuthShell(
      header: 'First login',
      steps: _kSteps,
      step: 2,
      icon: Icons.lock_outline_rounded,
      title: 'Set your password',
      subtitle: const Text(
        'Create a password to finish activating your account.',
      ),
      onBack: _back,
      action: AuthGradientButton(
        label: 'Activate & continue',
        doneLabel: 'Activated',
        loading: _loading,
        done: _done,
        onPressed: (_loading || _done) ? null : _setPassword,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('New password'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _p1,
            hint: 'At least 8 characters',
            prefixIcon: Icons.lock_outline_rounded,
            obscure: _o1,
            enabled: !_loading,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            suffix: AuthVisibilityToggle(
              obscure: _o1,
              onPressed: () => setState(() => _o1 = !_o1),
            ),
          ),
          const SizedBox(height: 14),
          const AuthFieldLabel('Confirm new password'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _p2,
            hint: 'Re-enter new password',
            prefixIcon: Icons.lock_outline_rounded,
            obscure: _o2,
            enabled: !_loading,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _setPassword(),
            suffix: AuthVisibilityToggle(
              obscure: _o2,
              onPressed: () => setState(() => _o2 = !_o2),
            ),
          ),
          const SizedBox(height: 14),
          AuthPasswordRules(
            listenable: Listenable.merge([_p1, _p2]),
            rules: [
              ('At least 8 characters', () => _p1.text.length >= 8),
              (
                'Both passwords match',
                () => _p2.text.isNotEmpty && _p1.text == _p2.text
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AuthFlashError(message: _error!),
          ],
        ],
      ),
    );
  }
}

/// Wizard step labels (header caption + progress bar).
const _kSteps = ['Your code', 'Verify OTP', 'Password'];

/// "Didn't get it? Resend" row under the OTP boxes. Public so the
/// forgot-password screen can reuse it.
class OtpResendRow extends StatelessWidget {
  const OtpResendRow({super.key, required this.cooldown, required this.onResend});

  final int cooldown;

  /// Null while a resend isn't allowed (cooldown / request in flight).
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            "Didn't get it?",
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ),
        TextButton(
          onPressed: onResend,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            disabledForegroundColor: AppColors.muted,
          ),
          child: Text(
            cooldown > 0 ? 'Resend in ${cooldown}s' : 'Resend',
            style: const TextStyle(
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// 6-digit OTP input — auto-advances on type, backspaces to previous.
// Public so the forgot-password screen can reuse it.
// ──────────────────────────────────────────────────────────────────────

class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.length, required this.onChanged});
  final int length;
  final ValueChanged<String> onChanged;

  @override
  State<OtpInput> createState() => OtpInputState();
}

class OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers =
      List.generate(widget.length, (_) => TextEditingController());
  late final List<FocusNode> _nodes =
      List.generate(widget.length, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  /// Fill the boxes from an auto-read OTP code.
  void setCode(String code) {
    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].text = i < code.length ? code[i] : '';
    }
    final last = code.length.clamp(1, widget.length) - 1;
    _nodes[last].requestFocus();
    _emit();
  }

  void _emit() => widget.onChanged(_controllers.map((c) => c.text).join());

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _OtpCell(
              controller: _controllers[i],
              focusNode: _nodes[i],
              onChanged: (v) {
                _emit();
                if (v.isNotEmpty && i < widget.length - 1) {
                  _nodes[i + 1].requestFocus();
                }
              },
              onBackspaceEmpty: () {
                if (i > 0) _nodes[i - 1].requestFocus();
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _OtpCell extends StatefulWidget {
  const _OtpCell({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspaceEmpty,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspaceEmpty;

  @override
  State<_OtpCell> createState() => _OtpCellState();
}

class _OtpCellState extends State<_OtpCell> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      setState(() => _focused = widget.focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? AppColors.primary
              : filled
                  ? const Color(0xFFA9BABE)
                  : AppColors.hairline,
          width: _focused ? 1.6 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.12),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              widget.controller.text.isEmpty) {
            widget.onBackspaceEmpty();
          }
        },
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          maxLength: 1,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          cursorColor: AppColors.primary,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          // The cell draws its own border; switch off the themed field chrome.
          decoration: const InputDecoration(
            counterText: '',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
