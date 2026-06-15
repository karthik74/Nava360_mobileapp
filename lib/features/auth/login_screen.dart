import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

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
  bool _checkingPermissions = true;
  bool _requestingPermissions = false;
  String? _permissionError;
  bool _consentAccepted = false;
  bool _locationServiceEnabled = false;
  LocationPermission _locationPermission = LocationPermission.denied;
  AuthorizationStatus _notificationStatus = AuthorizationStatus.notDetermined;

  bool get _locationReady =>
      _locationServiceEnabled &&
      _locationPermission == LocationPermission.always;

  bool get _notificationsReady =>
      _notificationStatus == AuthorizationStatus.authorized ||
      _notificationStatus == AuthorizationStatus.provisional;

  /// Required permissions for sign-in (SMS is optional, so it's excluded here).
  bool get _permissionsReady => _locationReady && _notificationsReady;

  /// Required permissions granted AND the user has ticked the consent box.
  /// Sign-in is only enabled in this state.
  bool get _readyToSignIn => _permissionsReady && _consentAccepted;

  @override
  void initState() {
    super.initState();
    _refreshRequiredPermissions();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!await _ensureRequiredPermissions()) return;
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .login(_username.text, _password.text);
    if (mounted && ref.read(authControllerProvider).asData?.value != null) {
      setState(() => _justSignedIn = true);
    }
  }

  /// Reads the FCM notification permission status. If Firebase isn't configured
  /// (e.g. iOS without a GoogleService-Info.plist), accessing
  /// `FirebaseMessaging.instance` throws `[core/no-app]` — in that case we don't
  /// block sign-in and treat notifications as authorised.
  Future<AuthorizationStatus> _readNotificationStatus() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus;
    } catch (_) {
      return AuthorizationStatus.authorized;
    }
  }

  Future<void> _refreshRequiredPermissions() async {
    setState(() {
      _checkingPermissions = true;
      _permissionError = null;
    });
    try {
      final locationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();
      final locationPermission = await Geolocator.checkPermission();
      final notificationStatus = await _readNotificationStatus();
      if (!mounted) return;
      setState(() {
        _locationServiceEnabled = locationServiceEnabled;
        _locationPermission = locationPermission;
        _notificationStatus = notificationStatus;
      });
    } catch (e) {
      if (mounted) setState(() => _permissionError = e.toString());
    } finally {
      if (mounted) setState(() => _checkingPermissions = false);
    }
  }

  Future<bool> _ensureRequiredPermissions() async {
    if (_requestingPermissions) return false;
    // Affirmative consent must come BEFORE we request any OS permission
    // (Google Play prominent-disclosure requirement).
    if (!_consentAccepted) {
      setState(() => _permissionError =
          'Please tick the consent box to grant the permissions below.');
      return false;
    }
    setState(() {
      _requestingPermissions = true;
      _permissionError = null;
    });

    try {
      var locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!locationServiceEnabled) {
        await Geolocator.openLocationSettings();
        locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      }

      var locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await Geolocator.requestPermission();
      }
      if (locationPermission == LocationPermission.whileInUse) {
        locationPermission = await Geolocator.requestPermission();
      }
      if (locationPermission != LocationPermission.always) {
        await Geolocator.openAppSettings();
        locationPermission = await Geolocator.checkPermission();
      }

      // Notification permission. If Firebase isn't configured (e.g. iOS without
      // a GoogleService-Info.plist) these calls throw `[core/no-app]`; in that
      // case don't block sign-in — treat notifications as authorised.
      AuthorizationStatus notifStatus;
      try {
        var settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        if (settings.authorizationStatus ==
            AuthorizationStatus.notDetermined) {
          settings = await FirebaseMessaging.instance
              .requestPermission(alert: true, badge: true, sound: true);
        }
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          await Geolocator.openAppSettings();
          settings = await FirebaseMessaging.instance.getNotificationSettings();
        }
        notifStatus = settings.authorizationStatus;
      } catch (_) {
        notifStatus = AuthorizationStatus.authorized;
      }

      if (!mounted) return false;
      setState(() {
        _locationServiceEnabled = locationServiceEnabled;
        _locationPermission = locationPermission;
        _notificationStatus = notifStatus;
      });

      // Only the REQUIRED permissions (location + notifications) gate sign-in.
      if (!_permissionsReady) {
        setState(() {
          _permissionError =
              'Allow location all the time and notifications to continue.';
        });
        return false;
      }

      return true;
    } catch (e) {
      if (mounted) setState(() => _permissionError = e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
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
    // Fields/navigation are usable any time (so users can fill the form while
    // reviewing the consent below); only the Sign-in CTA waits on consent +
    // permissions via [_readyToSignIn].
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
                            const SizedBox(height: 16),
                            // Consent + full permission disclosure, directly
                            // above the Sign-in button. Sign-in stays disabled
                            // until the box is ticked and access is granted.
                            _ConsentPanel(
                              checking: _checkingPermissions,
                              requesting: _requestingPermissions,
                              locationServiceEnabled: _locationServiceEnabled,
                              locationPermission: _locationPermission,
                              notificationStatus: _notificationStatus,
                              accepted: _consentAccepted,
                              error: _permissionError,
                              onAcceptedChanged: (v) =>
                                  setState(() => _consentAccepted = v),
                              onGrant: _ensureRequiredPermissions,
                              onRefresh: _refreshRequiredPermissions,
                            ),
                            const SizedBox(height: 14),
                            _GradientAuthButton(
                              label: 'Sign in',
                              loading: loading,
                              done: _justSignedIn,
                              onPressed: (!_readyToSignIn || loading || _justSignedIn)
                                  ? null
                                  : _submit,
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
                  child: Center(
                    child: Text(
                      'Secured by Nava360 · v1.0',
                      style: TextStyle(
                        color: AppColors.muted.withOpacity(0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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

/// Consent + full permission disclosure shown directly above the Sign-in
/// button. Lists every permission the app uses and why, lets the user grant
/// them, and carries the affirmative consent checkbox. This is the prominent
/// disclosure Google Play expects before accessing notifications/location.
class _ConsentPanel extends StatelessWidget {
  const _ConsentPanel({
    required this.checking,
    required this.requesting,
    required this.locationServiceEnabled,
    required this.locationPermission,
    required this.notificationStatus,
    required this.accepted,
    required this.error,
    required this.onAcceptedChanged,
    required this.onGrant,
    required this.onRefresh,
  });

  final bool checking;
  final bool requesting;
  final bool locationServiceEnabled;
  final LocationPermission locationPermission;
  final AuthorizationStatus notificationStatus;
  final bool accepted;
  final String? error;
  final ValueChanged<bool> onAcceptedChanged;
  final Future<bool> Function() onGrant;
  final Future<void> Function() onRefresh;

  bool get _notificationReady =>
      notificationStatus == AuthorizationStatus.authorized ||
      notificationStatus == AuthorizationStatus.provisional;

  // The required permissions gate the Grant/Refresh buttons.
  bool get _requiredGranted =>
      locationServiceEnabled &&
      locationPermission == LocationPermission.always &&
      _notificationReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.privacy_tip_outlined,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  checking
                      ? 'Checking permissions…'
                      : 'Permissions & data consent',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Nava360 needs the access below to work. Your data is used only for '
            'the purposes described, and you can revoke it any time in Settings.',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _ConsentPermissionRow(
            granted: locationServiceEnabled &&
                locationPermission == LocationPermission.always,
            label: 'Location (all the time)',
            purpose:
                'Records your attendance check-in/out, including in the background.',
            detail: _locationLabel(locationPermission),
          ),
          const SizedBox(height: 10),
          _ConsentPermissionRow(
            granted: _notificationReady,
            label: 'Notifications',
            purpose: 'Approvals, reminders and important alerts.',
            detail: _notificationLabel(notificationStatus),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (!_requiredGranted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PermissionButton(
                    label: requesting ? 'Opening settings…' : 'Grant access',
                    icon: Icons.lock_open_rounded,
                    primary: true,
                    enabled: !checking && !requesting,
                    onTap: onGrant,
                  ),
                ),
                const SizedBox(width: 8),
                _PermissionButton(
                  label: 'Refresh',
                  icon: Icons.refresh_rounded,
                  enabled: !checking && !requesting,
                  onTap: () async {
                    await onRefresh();
                    return true;
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          // Affirmative consent checkbox — required to enable Sign in.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onAcceptedChanged(!accepted),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: accepted,
                      onChanged: (v) => onAcceptedChanged(v ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      activeColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'I have read and agree to the permissions and data use '
                      'described above.',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _locationLabel(LocationPermission permission) {
    if (!locationServiceEnabled) return 'Service off';
    switch (permission) {
      case LocationPermission.always:
        return 'Allow all the time';
      case LocationPermission.whileInUse:
        return 'Only while using';
      case LocationPermission.deniedForever:
        return 'Denied in settings';
      case LocationPermission.denied:
        return 'Not granted';
      case LocationPermission.unableToDetermine:
        return 'Unknown';
    }
  }

  String _notificationLabel(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return 'Allowed';
      case AuthorizationStatus.provisional:
        return 'Allowed quietly';
      case AuthorizationStatus.denied:
        return 'Denied';
      case AuthorizationStatus.notDetermined:
        return 'Not granted';
    }
  }
}

/// One permission row inside [_ConsentPanel]: status icon + label + a plain
/// explanation of why the app needs it + the current grant status.
class _ConsentPermissionRow extends StatelessWidget {
  const _ConsentPermissionRow({
    required this.granted,
    required this.label,
    required this.purpose,
    required this.detail,
  });

  final bool granted;
  final String label;
  final String purpose;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final color = granted ? AppColors.success : AppColors.warning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            granted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: color,
            size: 17,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    detail,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                purpose,
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionButton extends StatelessWidget {
  const _PermissionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final Future<bool> Function() onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.primary : Colors.white.withOpacity(0.55);
    final fg = primary ? Colors.white : AppColors.primary;
    return Material(
      color: enabled ? bg : AppColors.muted.withOpacity(0.25),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisSize: primary ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: enabled ? fg : AppColors.muted, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? fg : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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
