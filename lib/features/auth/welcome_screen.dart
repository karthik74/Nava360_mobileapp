import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding.dart';
import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'welcome_seen_controller.dart';

/// Nava360 welcome / get-started screen.
///
/// Pro "immersive" layout: deep brand surface with the brand row, a "By
/// <company>" badge and the headline, and a white action sheet pinned to the
/// bottom with the feature tiles and the Get started / Sign in actions.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: FieldReadyBackdrop(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand row + hero copy (scrolls on very short screens).
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding:
                      EdgeInsets.fromLTRB(24, mq.padding.top + 20, 24, 24),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BrandRow(),
                      SizedBox(height: 72),
                      _HeroCopy(),
                    ],
                  ),
                ),
              ),

              // Bottom white action sheet.
              _ActionSheet(
                bottomInset: mq.padding.bottom,
                onGetStarted: () => _goToLogin(context, ref),
                onSignIn: () => _goToLogin(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToLogin(BuildContext context, WidgetRef ref) {
    // Persist that the welcome was seen and update the in-memory flag now, so
    // a later sign-out / failed login routes to /login instead of replaying
    // onboarding.
    // ignore: discarded_futures
    ref.read(welcomeSeenProvider.notifier).markSeen();
    context.go('/login');
  }
}

// ──────────────────────────────────────────────────────────────────────
// Brand row — small logo chip + workspace name
// ──────────────────────────────────────────────────────────────────────

class _BrandRow extends ConsumerWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(brandingProvider);
    final logoUrl = Env.fileUrl(b.logoUrl);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 22,
                spreadRadius: -10,
                offset: Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(5),
          // Company logo from runtime branding; product mark as fallback.
          child: logoUrl == null
              ? Image.asset('assets/logo-mark.png', fit: BoxFit.contain)
              : Image.network(
                  logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Image.asset('assets/logo-mark.png', fit: BoxFit.contain),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            b.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Hero copy — badge + headline + subtitle
// ──────────────────────────────────────────────────────────────────────

class _HeroCopy extends ConsumerWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyName = ref.watch(brandingProvider).companyName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "By <company>" pill — from runtime branding; hidden when the
        // deployment hasn't configured a company name.
        if (companyName.isNotEmpty) ...[
          Container(
            height: 30,
            padding: const EdgeInsets.only(left: 6, right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ProPulseDot(color: AppColors.live, size: 7),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'By $companyName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xDBFFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        const Text(
          'Field work,\nfully handled.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w600,
            height: 1.1,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 322),
          child: const Text(
            'Track attendance with GPS, complete field tasks and request '
            'leave — all from one app built for the ground.',
            style: TextStyle(
              color: Color(0xBDFFFFFF),
              fontSize: 15,
              height: 1.53,
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Bottom white action sheet — feature tiles + Get started + Sign in
// ──────────────────────────────────────────────────────────────────────

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.bottomInset,
    required this.onGetStarted,
    required this.onSignIn,
  });

  final double bottomInset;
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final features = [
      ('Attendance', Icons.fingerprint_rounded, AppColors.success,
          AppColors.successTint),
      ('Tasks', Icons.task_alt_rounded, AppColors.primary,
          AppColors.primary.withOpacity(0.1)),
      ('Leave', Icons.event_available_rounded, AppColors.info,
          AppColors.infoTint),
      ('Team', Icons.groups_rounded, AppColors.pink, const Color(0xFFF0EBF7)),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset + 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final f in features)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: f.$4,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(f.$2, color: f.$3, size: 22),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        f.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: onGetStarted,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Get started'),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: onSignIn,
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  TextSpan(
                    text: 'Sign in',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
