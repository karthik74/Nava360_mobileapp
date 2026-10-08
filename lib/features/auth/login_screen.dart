import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

// The shared input formatters are re-exported so the other auth screens get
// them together with the AuthTextField/AuthShell widgets this file provides.
export '../../core/text_formatters.dart';

import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'biometric/biometric_controller.dart';
import 'biometric/biometric_enroll_gate.dart';
import 'biometric/biometric_service.dart';

/// Demo-only quick logins ("Test FO" / "Test BM"). Compiled in only when a build
/// passes `--dart-define=DEMO_LOGIN_PASSWORD=...`; a normal build has an empty
/// password and never shows the buttons, and no password lives in source.
const _kDemoPassword = String.fromEnvironment('DEMO_LOGIN_PASSWORD');
const _kDemoFoUser = String.fromEnvironment('DEMO_FO_USER', defaultValue: 'karthik.fo');
const _kDemoBmUser = String.fromEnvironment('DEMO_BM_USER', defaultValue: 'rajesh.bm');

/// Login screen — Pro "immersive" layout: deep brand surface with the logo and
/// headline on top, a white rounded sheet holding the sign-in form below.
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
    await _signIn();
  }

  /// Fills the form with a demo account and signs in (demo builds only).
  Future<void> _demoLogin(String username) async {
    _username.text = username;
    _password.text = _kDemoPassword;
    await _signIn();
  }

  Future<void> _signIn() async {
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
    // Deployment-level kill switch from /api/public/branding.
    final bioFeatureOn = ref
        .watch(brandingProvider)
        .featureEnabled('FEATURE_BIOMETRIC_LOGIN');

    // Case A: if a biometric enrollment exists and the device can use it, prompt
    // automatically the first time the login screen appears.
    if (bioFeatureOn &&
        bio.canOfferLogin &&
        !_autoBioTried &&
        !loading &&
        !_justSignedIn) {
      _autoBioTried = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _biometricLogin(auto: true),
      );
    }
    // Fields, navigation and the Sign-in CTA are usable whenever a login isn't
    // already in flight. OS permissions are handled after sign-in by the
    // app-level PermissionGate, so the login form doesn't request them here.
    final formEnabled = !loading;

    return Scaffold(
      backgroundColor: AppColors.deep,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: FieldReadyBackdrop(
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              // 1. Deep brand area: back, logo + product name, headline.
              SliverToBoxAdapter(
                child: _AuthTop(
                  onBack: _goBackToWelcome,
                  headline: 'Field work,\nfully handled.',
                  tags: const ['Attendance', 'Leave', 'Tasks', 'Team'],
                ),
              ),

              // 2. White sheet with the form; fills the rest of the screen and
              // scrolls with it when the keyboard pushes things up.
              SliverFillRemaining(
                hasScrollBody: false,
                child: _AuthSheet(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Welcome back', style: _kSheetTitle),
                        const SizedBox(height: 2),
                        const Text(
                          'Sign in to access your workspace',
                          style: _kSheetSubtitle,
                        ),
                        const SizedBox(height: 20),
                        if (widget.flash != null) ...[
                          _FlashSuccess(message: widget.flash!),
                          const SizedBox(height: 16),
                        ],
                        const _FieldLabel('Username'),
                        const SizedBox(height: 6),
                        _AuthTextField(
                          controller: _username,
                          hint: 'Enter your username',
                          prefixIcon: Icons.person_outline_rounded,
                          enabled: formEnabled,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: const [UpperCaseTextFormatter()],
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Expanded(child: _FieldLabel('Password')),
                            _InlineLink(
                              label: 'Forgot password?',
                              onTap: !formEnabled
                                  ? null
                                  : () => context.push(
                                        '/forgot-password',
                                        extra: _username.text.trim(),
                                      ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _AuthTextField(
                          controller: _password,
                          hint: '••••••••',
                          prefixIcon: Icons.lock_outline_rounded,
                          obscure: _obscure,
                          enabled: formEnabled,
                          // Keyboard opens with Shift on for the first
                          // letter only — never rewrites what is typed
                          // (passwords are case-sensitive).
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          onSubmit: (_) => _submit(),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                          suffix: _VisibilityToggle(
                            obscure: _obscure,
                            onPressed: formEnabled
                                ? () => setState(() => _obscure = !_obscure)
                                : null,
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 14),
                          _FlashError(message: error),
                        ],
                        const SizedBox(height: 20),
                        _GradientAuthButton(
                          label: 'Sign in',
                          doneLabel: 'Signed in',
                          loading: loading,
                          done: _justSignedIn,
                          onPressed:
                              (loading || _justSignedIn) ? null : _submit,
                        ),
                        if (bioFeatureOn)
                          _BiometricLoginSection(
                            state: bio,
                            busy: _bioBusy,
                            onTap: () => _biometricLogin(auto: false),
                          ),
                        if (_kDemoPassword.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _DemoLoginRow(
                            enabled: !(loading || _justSignedIn),
                            onFieldOfficer: () => _demoLogin(_kDemoFoUser),
                            onBranchManager: () => _demoLogin(_kDemoBmUser),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Spacer(),

                        // Footer — activation link, privacy, version.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Flexible(
                              child: Text(
                                'First time signing in?',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _kFootText,
                              ),
                            ),
                            _InlineLink(
                              label: 'Activate account',
                              onTap: !formEnabled
                                  ? null
                                  : () => context.push('/first-login'),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _InlineLink(
                              label: 'Privacy Policy',
                              small: true,
                              onTap: () => launchUrl(
                                Uri.parse(
                                    Branding.current.effectivePrivacyUrl),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                            const Text('·', style: _kFootText),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Secured by ${Branding.current.productName} · v1.0',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.faint,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Shared auth screen pieces (deep top + white sheet, fields, notes, CTA).
// Re-used by the first-login / forgot-password screens.
// ──────────────────────────────────────────────────────────────────────

const _kSheetTitle = TextStyle(
  fontSize: 24,
  height: 1.25,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.6,
  color: AppColors.ink,
);

const _kSheetSubtitle = TextStyle(
  fontSize: 14,
  height: 1.4,
  color: AppColors.muted,
);

const _kFootText = TextStyle(fontSize: 13, color: AppColors.muted);

/// Deep top area of the immersive auth screens: back chip, logo + product
/// name, a large headline and optional feature tags.
class _AuthTop extends StatelessWidget {
  const _AuthTop({
    required this.onBack,
    required this.headline,
    this.tags = const [],
  });

  final VoidCallback onBack;
  final String headline;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProHeroIconButton(
                icon: Icons.chevron_left_rounded,
                iconSize: 24,
                tooltip: 'Back',
                onTap: onBack,
              ),
              const SizedBox(width: 12),
              const _AuthLogoChip(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Branding.current.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 44),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              height: 1.16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.9,
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in tags) ProHeroTag(t)],
            ),
          ],
        ],
      ),
    );
  }
}

/// Small white logo chip used on deep surfaces and in the wizard header.
class _AuthLogoChip extends StatelessWidget {
  const _AuthLogoChip({this.size = 36, this.bordered = false});
  final double size;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.31),
        border: bordered ? Border.all(color: AppColors.hairline) : null,
      ),
      child: Image.asset('assets/logo-mark.png', fit: BoxFit.contain),
    );
  }
}

/// White rounded-top sheet that holds an auth form on the deep surface.
class _AuthSheet extends StatelessWidget {
  const _AuthSheet({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 26, 24, bottom + 10),
      child: child,
    );
  }
}

/// Compact text link (Forgot password?, Activate account, Privacy Policy).
class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.label, required this.onTap, this.small = false});
  final String label;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: small ? 12.5 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Eye toggle for password fields.
class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.obscure, required this.onPressed});
  final bool obscure;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscure ? 'Show password' : 'Hide password',
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: AppColors.muted,
        size: 20,
      ),
      onPressed: onPressed,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppText.label);
}

/// Text field with a leading icon and optional suffix. Borders, fill and the
/// focused primary outline come from the global input theme.
class _AuthTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmit,
      validator: validator,
      cursorColor: AppColors.primary,
      style: const TextStyle(
        fontSize: 15,
        color: AppColors.ink,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(prefixIcon, size: 18, color: AppColors.faint),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 0),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );
  }
}

/// Green banner shown above the form after a successful action.
class _FlashSuccess extends StatelessWidget {
  const _FlashSuccess({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) =>
      ProNote(message, tone: ProNoteTone.ok);
}

class _FlashError extends StatelessWidget {
  const _FlashError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) =>
      ProNote(message, tone: ProNoteTone.bad);
}

/// Full-width primary CTA with loading spinner and a "done" success state.
class _GradientAuthButton extends StatelessWidget {
  const _GradientAuthButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.done = false,
    this.doneLabel = 'Signed in',
  });

  final String label;
  final bool loading;
  final bool done;
  final String doneLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = done ? AppColors.success : AppColors.primary;
    // Keep the brand (or success) colour while a request is in flight or
    // after it succeeded, instead of the grey disabled style.
    final hold = loading || done;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          disabledBackgroundColor: hold ? bg : null,
          disabledForegroundColor: hold ? Colors.white : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: loading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Row(
                  key: ValueKey(done),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (done) ...[
                      const Icon(Icons.check_rounded, size: 19),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(doneLabel,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ] else ...[
                      Flexible(
                        child: Text(label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// The two demo quick-login buttons, under a small "Demo login" caption so
/// nobody mistakes them for a real sign-in option.
class _DemoLoginRow extends StatelessWidget {
  const _DemoLoginRow({
    required this.enabled,
    required this.onFieldOfficer,
    required this.onBranchManager,
  });

  final bool enabled;
  final VoidCallback onFieldOfficer;
  final VoidCallback onBranchManager;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, IconData icon, VoidCallback onTap) => Expanded(
          child: OutlinedButton.icon(
            onPressed: enabled ? onTap : null,
            icon: Icon(icon, size: 18, color: AppColors.primary),
            label: Text(label),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Demo login',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.faint,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            button('Test FO', Icons.directions_walk_rounded, onFieldOfficer),
            const SizedBox(width: 10),
            button('Test BM', Icons.storefront_rounded, onBranchManager),
          ],
        ),
      ],
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
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.hairline)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('or',
                    style: TextStyle(color: AppColors.faint, fontSize: 12.5)),
              ),
              Expanded(child: Divider(color: AppColors.hairline)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onTap,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Icon(
                      isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
              label: Text(busy ? 'Verifying…' : 'Login with ${state.label}'),
            ),
          ),
        ],
      );
    }

    // Case C — enrolled on the account but no fingerprint/Face ID on this device.
    if (state.enabled &&
        state.availability == BiometricAvailability.notEnrolled) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: ProNote(
          'To use biometric login, please add a fingerprint or Face ID in your device settings.',
          tone: ProNoteTone.info,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Live checklist shown under a new-password pair. Presentation only — the
/// screens still validate on submit exactly as before.
class AuthPasswordRules extends StatelessWidget {
  const AuthPasswordRules({
    super.key,
    required this.listenable,
    required this.rules,
  });

  /// Rebuilds when any of these change (usually the password controllers).
  final Listenable listenable;

  /// (label, isMet) pairs.
  final List<(String, bool Function())> rules;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in rules) _RuleRow(label: r.$1, ok: r.$2()),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.ok});
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: ok ? AppColors.success : Colors.transparent,
              shape: BoxShape.circle,
              border: ok
                  ? null
                  : Border.all(color: const Color(0xFFC6D3D6), width: 1.5),
            ),
            child: ok
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ok ? AppColors.success : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Wizard shell shared by the first-login and forgot-password flows.
// ──────────────────────────────────────────────────────────────────────

/// Pro form/wizard shell: light header with back + step caption, segmented
/// step progress, one white card (icon, title, subtitle, form) and the primary
/// action pinned in a bottom bar that stays above the keyboard.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onBack,
    this.header,
    this.steps = const [],
    this.step = 0,
    this.icon,
    this.action,
  });

  /// Card title (e.g. "Verify OTP").
  final String title;
  final Widget subtitle;
  final Widget child;
  final VoidCallback onBack;

  /// Header title (e.g. "First login"); defaults to [title].
  final String? header;

  /// Step labels for the progress bar; empty hides it.
  final List<String> steps;

  /// Zero-based current step.
  final int step;

  /// Icon shown next to the card title.
  final IconData? icon;

  /// Primary call to action, pinned in the bottom bar.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final hasSteps = steps.isNotEmpty;
    final current = hasSteps ? step.clamp(0, steps.length - 1) : 0;
    final caption = hasSteps
        ? 'Step ${current + 1} of ${steps.length} · ${steps[current]}'
        : null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        automaticallyImplyLeading: false,
        leadingWidth: 62,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(child: ProBackButton(onTap: onBack)),
        ),
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              header ?? title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: AppColors.ink,
              ),
            ),
            if (caption != null)
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: _AuthLogoChip(size: 40, bordered: true)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (hasSteps) ...[
                  _WizardSteps(labels: steps, current: current),
                  const SizedBox(height: 16),
                ],
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProIconWell(
                            icon: icon ?? Icons.lock_outline_rounded,
                            color: AppColors.primary,
                            size: 44,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    height: 1.33,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.35,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                DefaultTextStyle(
                                  style: const TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: AppColors.muted,
                                  ),
                                  child: subtitle,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      child,
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ProBottomBar(children: [action!]),
        ],
      ),
    );
  }
}

/// Labelled step progress (done = green, current = brand, upcoming = grey).
class _WizardSteps extends StatelessWidget {
  const _WizardSteps({required this.labels, required this.current});
  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _WizardStep(
              index: i,
              label: labels[i],
              done: i < current,
              on: i == current,
            ),
          ),
        ],
      ],
    );
  }
}

class _WizardStep extends StatelessWidget {
  const _WizardStep({
    required this.index,
    required this.label,
    required this.done,
    required this.on,
  });

  final int index;
  final String label;
  final bool done;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final barColor = done
        ? AppColors.success
        : on
            ? AppColors.primary
            : const Color(0xFFDFE7E9);
    final textColor = done
        ? AppColors.success
        : on
            ? AppColors.ink
            : AppColors.faint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 4,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppColors.successTint
                    : on
                        ? AppColors.primary
                        : Colors.transparent,
                border: done || on
                    ? null
                    : Border.all(color: const Color(0xFFC6D3D6), width: 1.5),
              ),
              child: done
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: AppColors.success)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : AppColors.faint,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Re-export the field, label, flash, and button so the first-login screen
// can use them without duplicating the styling.
typedef AuthTextField = _AuthTextField;
typedef AuthFieldLabel = _FieldLabel;
typedef AuthFlashError = _FlashError;
typedef AuthGradientButton = _GradientAuthButton;
typedef AuthVisibilityToggle = _VisibilityToggle;
