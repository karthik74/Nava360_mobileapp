import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'auth_repository.dart';
import 'login_screen.dart';
import 'sms_otp.dart';

/// Step 2 of password reset: enter the 6-digit OTP and a new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.username});

  /// Username carried over from the forgot screen (shown in the subtitle).
  final String? username;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  String _otp = '';
  bool _o1 = true;
  bool _o2 = true;
  bool _loading = false;
  bool _done = false;
  String? _error;

  // OTP SMS auto-read (SMS User Consent API — no READ_SMS permission).
  final _smsOtp = SmsOtpListener();
  final _otpKey = GlobalKey<_OtpBoxesState>();

  @override
  void initState() {
    super.initState();
    // The OTP was sent on the previous (forgot-password) screen, so it should
    // arrive shortly after this screen opens — start listening now.
    _smsOtp.start(
      digits: 6,
      onCode: (code) {
        if (!mounted) return;
        _otpKey.currentState?.setCode(code);
        setState(() => _otp = code);
      },
    );
  }

  @override
  void dispose() {
    _smsOtp.cancel();
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Enter the 6-digit code sent to your mobile.');
      return;
    }
    if (_p1.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
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
      final user = widget.username ?? 'your account';
      await ref.read(authRepositoryProvider).resetPassword(
            username: user,
            otp: _otp,
            newPassword: _p1.text,
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
        extra: 'Password reset successfully. Please sign in.',
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
    final user = widget.username ?? 'your account';
    return AuthShell(
      title: 'Reset password',
      subtitle: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'We sent a 6-digit code to the mobile number '
                  'registered with ',
            ),
            TextSpan(
              text: user,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(text: '. Enter it and set a new password.'),
          ],
        ),
      ),
      onBack: () =>
          context.canPop() ? context.pop() : context.go('/forgot-password'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('Verification code'),
          const SizedBox(height: 8),
          _OtpBoxes(
            key: _otpKey,
            length: 6,
            onChanged: (v) => setState(() => _otp = v),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _loading ? null : () {/* TODO: hook resend */},
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    children: [
                      TextSpan(text: "Didn't get it? "),
                      TextSpan(
                        text: 'Resend',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const AuthFieldLabel('New password'),
          const SizedBox(height: 8),
          AuthTextField(
            controller: _p1,
            hint: 'At least 6 characters',
            prefixIcon: Icons.lock_outline_rounded,
            obscure: _o1,
            enabled: !_loading,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            suffix: IconButton(
              splashRadius: 18,
              icon: Icon(
                _o1
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
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
            onSubmit: (_) => _submit(),
            suffix: IconButton(
              splashRadius: 18,
              icon: Icon(
                _o2
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
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
            label: 'Reset password',
            loading: _loading,
            done: _done,
            onPressed: (_loading || _done) ? null : _submit,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// 6-digit OTP input — auto-advances on type, backspaces to previous.
// ──────────────────────────────────────────────────────────────────────

class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({super.key, required this.length, required this.onChanged});
  final int length;
  final ValueChanged<String> onChanged;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
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

  void _emit() {
    widget.onChanged(_controllers.map((c) => c.text).join());
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _OtpBox(
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

class _OtpBox extends StatefulWidget {
  const _OtpBox({
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
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
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
    final highlight = _focused || filled;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? AppColors.primary : Colors.white.withOpacity(0.85),
          width: highlight ? 1.6 : 1,
        ),
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
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            isCollapsed: true,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
