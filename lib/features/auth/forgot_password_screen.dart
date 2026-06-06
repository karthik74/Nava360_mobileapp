import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'auth_repository.dart';
import 'login_screen.dart';

/// Step 1 of password reset: collect the username and "send" an OTP.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialUsername});

  /// Pre-filled username (typically what the user typed on the login screen).
  final String? initialUsername;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final TextEditingController _username =
      TextEditingController(text: widget.initialUsername ?? '');
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _username.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Please enter your username.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(authRepositoryProvider).forgotPassword(value);
      if (!mounted) return;
      setState(() => _loading = false);
      context.go('/reset-password', extra: value);
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
    return AuthShell(
      title: 'Forgot password?',
      subtitle: const Text(
        "Enter your username and we'll send a one-time code to your "
        'registered mobile number.',
      ),
      onBack: () => context.canPop() ? context.pop() : context.go('/login'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('Username'),
          const SizedBox(height: 8),
          AuthTextField(
            controller: _username,
            hint: 'Enter your username',
            prefixIcon: Icons.person_outline_rounded,
            enabled: !_loading,
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _send(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthFlashError(message: _error!),
          ],
          SizedBox(height: _error != null ? 16 : 22),
          AuthGradientButton(
            label: 'Send OTP',
            loading: _loading,
            onPressed: _loading ? null : _send,
          ),
          const SizedBox(height: 16),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _loading ? null : () => context.go('/login'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      TextSpan(text: 'Back to '),
                      TextSpan(
                        text: 'Sign in',
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
        ],
      ),
    );
  }
}
