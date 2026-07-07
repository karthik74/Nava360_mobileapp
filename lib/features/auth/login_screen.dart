import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

// The shared input formatters are re-exported so the other auth screens get
// them together with the AuthTextField/AuthShell widgets this file provides.
export '../../core/text_formatters.dart';

import '../../core/env.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'biometric/biometric_controller.dart';
import 'biometric/biometric_enroll_gate.dart';
import 'biometric/biometric_service.dart';

/// Login screen — port of the design canvas's `LoginScreen`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.flash});

  /// Optional success message shown above the form (e.g. after a password
  /// reset). Passed via go_router's `extra`.
  final String? flash;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _justSignedIn = false;
  bool _autoBioTried = false;
  bool _bioBusy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .login(_username.text, _password.text);
    if (mounted && ref.read(authControllerProvider).asData?.value != null) {
      // Signal the enroll gate to offer biometric enrollment after this login.
      ref.read(justPasswordLoggedInProvider.notifier).state = true;
      setState(() => _justSignedIn = true);
    }
    // Required OS permissions (location, notifications, battery) are requested
    // by the PermissionGate that wraps the app once the user is signed in.
  }

  /// Case A / D: prompt fingerprint / Face ID, allowing up to 3 attempts before
  /// falling back to the password form. A backend/state error stops retrying and
  /// surfaces the reason (e.g. session expired, account inactive).
  Future<void> _biometricLogin({required bool auto}) async {
    if (_bioBusy) return;
    setState(() => _bioBusy = true);
    final ctrl = ref.read(biometricControllerProvider.notifier);
    try {
      for (var attempt = 1; attempt <= 3; attempt++) {
        final err = await ctrl.loginWithBiometric();
        if (err == null) {
          if (mounted) setState(() => _justSignedIn = true); // router redirects
          return;
        }
        // Only a local verification miss is worth retrying; anything else
        // (device wiped server-side, expired, inactive) should stop immediately.
        final retriable = err.contains('failed');
        if (!retriable) {
          if (mounted) _flash(err);
          return;
        }
        if (attempt == 3 && mounted && !auto) {
          _flash('Biometric authentication failed. Please login using your password.');
        }
      }
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  void _flash(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goBackToWelcome() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final loading = state.isLoading;
    final error = state.hasError ? state.error.toString() : null;
    final bio = ref.watch(biometricControllerProvider);

    // Case A: if a biometric enrollment exists and the device can use it, prompt
    // automatically the first time the login screen appears.
    if (bio.canOfferLogin && !_autoBioTried && !loading && !_justSignedIn) {
      _autoBioTried = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _biometricLogin(auto: true),
      );
    }
    // Fields, navigation and the Sign-in CTA are usable whenever a login isn't
    // already in flight. OS permissions are handled after sign-in by the
    // app-level PermissionGate, so the login form doesn't request them here.
    final formEnabled = !loading;
    final mq = MediaQuery.of(context);
    final size = mq.size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Mesh wallpaper (full-bleed; no top veil so the
          // gradient band reads cleanly).
          const _AuthMesh(veil: false),

          // 2. Hero gradient band — full width, top 42% of screen.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.42,
            child: const _HeroGradient(),
          ),

          // 3. Foreground form (Column so the footer pins to the bottom;
          // the form area itself scrolls when content overflows).
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // Header (logo + title + subtitle), edge-padded.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.8),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x38101828),
                              blurRadius: 26,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        alignment: Alignment.center,
                        child: Image.asset(
                          'assets/logo-mark.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Welcome back',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to access your workspace',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Form — Expanded so it fills the remaining height; scrolls
                // when keyboard pushes things up.
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: _GlassFormCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.flash != null) ...[
                              _FlashSuccess(message: widget.flash!),
                              const SizedBox(height: 16),
                            ],
                            const _FieldLabel('Username'),
                            const SizedBox(height: 8),
                            _AuthTextField(
                              controller: _username,
                              hint: 'Enter your username',
                              prefixIcon: Icons.person_outline_rounded,
                              enabled: formEnabled,
                              textCapitalization:
                                  TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              textInputAction: TextInputAction.next,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            const _FieldLabel('Password'),
                            const SizedBox(height: 8),
                            _AuthTextField(
                              controller: _password,
                              hint: '••••••••',
                              prefixIcon: Icons.lock_outline_rounded,
                              obscure: _obscure,
                              enabled: formEnabled,
                              // Keyboard opens with Shift on for the first
                              // letter only — never rewrites what is typed
                              // (passwords are case-sensitive).
                              textCapitalization:
                                  TextCapitalization.sentences,
                              textInputAction: TextInputAction.done,
                              onSubmit: (_) => _submit(),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                              suffix: IconButton(
                                splashRadius: 18,
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.muted,
                                  size: 19,
                                ),
                                onPressed: formEnabled
                                    ? () => setState(() => _obscure = !_obscure)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: !formEnabled
                                    ? null
                                    : () => context.push(
                                          '/forgot-password',
                                          extra: _username.text,
                                        ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    'Forgot password?',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 16),
                              _FlashError(message: error),
                            ],
                            const SizedBox(height: 20),
                            _GradientAuthButton(
                              label: 'Sign in',
                              loading: loading,
                              done: _justSignedIn,
                              onPressed: (loading || _justSignedIn)
                                  ? null
                                  : _submit,
                            ),
                            _BiometricLoginSection(
                              state: bio,
                              busy: _bioBusy,
                              onTap: () => _biometricLogin(auto: false),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: !formEnabled
                                    ? null
                                    : () => context.push('/first-login'),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: Text.rich(
                                    TextSpan(
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.muted,
                                      ),
                                      children: [
                                        TextSpan(text: 'First time signing in? '),
                                        TextSpan(
                                          text: 'Activate account',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
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
                      ),
                    ),
                  ),
                ),

                // Footer — pinned at the bottom of the screen.
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => launchUrl(
                          Uri.parse(Env.privacyPolicyUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: AppColors.primary.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Secured by Nava360 · v1.0',
                        style: TextStyle(
                          color: AppColors.muted.withOpacity(0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Back button — circular glass chip, top-left.
          Positioned(
            top: mq.padding.top + 10,
            left: 14,
            child: _AuthBackButton(onTap: _goBackToWelcome),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Shared auth screen pieces (mesh + gradient band + back button +
// glass card + fields + flash + gradient CTA). Re-used by ForgotPassword
// and ResetPassword screens so they share the same chrome.
// ──────────────────────────────────────────────────────────────────────

/// Subtle mesh wallpaper behind the auth screens. Mirrors GlassBackdrop but
/// without the white veil so the hero gradient reads correctly.
class _AuthMesh extends StatelessWidget {
  const _AuthMesh({this.veil = true});
  final bool veil;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEDF1FB), Color(0xFFF4ECFB), Color(0xFFE8F4FB)],
            ),
          ),
        ),
        Positioned(
          top: -100,
          left: -100,
          child: _Blob(360, AppColors.meshA.withOpacity(0.36)),
        ),
        Positioned(
          top: 60,
          right: -120,
          child: _Blob(320, AppColors.meshB.withOpacity(0.32)),
        ),
        Positioned(
          bottom: -160,
          left: -40,
          child: _Blob(380, AppColors.meshC.withOpacity(0.32)),
        ),
        if (veil)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.30),
                    Colors.white.withOpacity(0.12),
                    Colors.white.withOpacity(0.25),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob(this.size, this.color);
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

/// Indigo → indigo-dark → cyan hero gradient (with cyan radial highlight).
class _HeroGradient extends StatelessWidget {
  const _HeroGradient();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: const [
                  Color(0xFF4F46E5),
                  Color(0xFF3730A3),
                  Color(0xFF06B6D4),
                ],
                stops: const [0.0, 0.50, 1.30]
                    .map((s) => s.clamp(0.0, 1.0))
                    .toList(),
              ),
            ),
          ),
        ),
        // Diagonal sheen overlay (top-right white → mid transparent → bottom-left dark).
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Colors.white.withOpacity(0.18),
                  Colors.transparent,
                  Colors.black.withOpacity(0.04),
                ],
                stops: const [0, 0.52, 1],
              ),
            ),
          ),
        ),
        // Cyan radial accent in the top-right corner.
        Positioned(
          top: -60,
          right: -50,
          child: _Blob(220, AppColors.accent.withOpacity(0.45)),
        ),
      ],
    );
  }
}

/// 40×40 circular back chip with frosted glass fill.
class _AuthBackButton extends StatelessWidget {
  const _AuthBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: SizedBox(
        width: 40,
        height: 40,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: Colors.white.withOpacity(0.18),
              child: InkWell(
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted-white form card used by every auth screen.
class _GlassFormCard extends StatelessWidget {
  const _GlassFormCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.62),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x386366F1),
                blurRadius: 48,
                offset: Offset(0, 22),
              ),
              BoxShadow(
                color: Color(0x10101828),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        letterSpacing: 0.1,
      ),
    );
  }
}

/// White-tinted text field with prefix icon + optional suffix; focused state
/// shows a primary border + soft outer ring.
class _AuthTextField extends StatefulWidget {
  const _AuthTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscure = false,
    this.enabled = true,
    this.suffix,
    this.textInputAction,
    this.onSubmit,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscure;
  final bool enabled;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmit;
  final FormFieldValidator<String>? validator;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<_AuthTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: _focused ? AppColors.primary : Colors.white.withOpacity(0.85),
        width: _focused ? 1.6 : 1,
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.14),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : const [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscure,
        enabled: widget.enabled,
        textCapitalization: widget.textCapitalization,
        inputFormatters: widget.inputFormatters,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmit,
        validator: widget.validator,
        cursorColor: AppColors.primary,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          isCollapsed: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          hintText: widget.hint,
          hintStyle: const TextStyle(
            color: AppColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.7),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(widget.prefixIcon, size: 18, color: AppColors.muted),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 0),
          suffixIcon: widget.suffix,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          border: border,
          enabledBorder: border,
          focusedBorder: border,
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// Green check banner shown above the form after a successful action.
class _FlashSuccess extends StatelessWidget {
  const _FlashSuccess({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.success,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF059669),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlashError extends StatelessWidget {
  const _FlashError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indigo → cyan gradient submit button with loading + "Done" success state.
class _GradientAuthButton extends StatelessWidget {
  const _GradientAuthButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.done = false,
  });

  final String label;
  final bool loading;
  final bool done;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null && !done;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        gradient: done
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF10B981), Color(0xFF34D399)],
              )
            : disabled
                ? null
                : AppColors.heroGradient,
        color: disabled ? AppColors.muted.withOpacity(0.3) : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.40),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (done) ...[
                        const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Signed in',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ] else ...[
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Biometric login affordance on the login screen.
/// - Case A (enrolled + usable): an "or" divider + "Login with Fingerprint/Face ID".
/// - Case C (enrolled but nothing enrolled on device): a hint to add one.
/// - Case B (no hardware) / not enrolled here: nothing.
class _BiometricLoginSection extends StatelessWidget {
  const _BiometricLoginSection({
    required this.state,
    required this.busy,
    required this.onTap,
  });

  final BiometricState state;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (state.canOfferLogin) {
      final isFace = state.label == 'Face ID';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Divider(color: AppColors.muted.withOpacity(0.3))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('or',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
              Expanded(child: Divider(color: AppColors.muted.withOpacity(0.3))),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.3),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                    size: 20),
            label: Text(
              busy ? 'Verifying…' : 'Login with ${state.label}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      );
    }

    // Case C — enrolled on the account but no fingerprint/Face ID on this device.
    if (state.enabled &&
        state.availability == BiometricAvailability.notEnrolled) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'To use biometric login, please add a fingerprint or Face ID in your device settings.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ──────────────────────────────────────────────────────────────────────
// Shared bits exported for the forgot/reset screens.
// ──────────────────────────────────────────────────────────────────────

/// Shell used by ForgotPasswordScreen / ResetPasswordScreen — same gradient
/// band + back button + small logo chip + title/subtitle + glass card.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onBack,
  });

  final String title;
  final Widget subtitle;
  final Widget child;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AuthMesh(veil: false),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.38,
            child: const _HeroGradient(),
          ),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.8),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x38101828),
                          blurRadius: 26,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/logo-mark.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DefaultTextStyle(
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    child: subtitle,
                  ),
                  const SizedBox(height: 22),
                  _GlassFormCard(child: child),
                ],
              ),
            ),
          ),
          Positioned(
            top: mq.padding.top + 10,
            left: 14,
            child: _AuthBackButton(onTap: onBack),
          ),
        ],
      ),
    );
  }
}

// Re-export the field, label, flash, and button so the forgot/reset screens
// can use them without duplicating the styling.
typedef AuthTextField = _AuthTextField;
typedef AuthFieldLabel = _FieldLabel;
typedef AuthFlashError = _FlashError;
typedef AuthGradientButton = _GradientAuthButton;
