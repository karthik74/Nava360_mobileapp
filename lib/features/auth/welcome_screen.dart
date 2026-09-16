import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import 'welcome_seen_controller.dart';

/// Nava360 welcome / get-started screen.
///
/// Variation C "Field-Ready" from the design canvas — bold layered teal-led
/// gradient with a watermark logo, brand row, large headline, and a frosted
/// glass action sheet pinned to the bottom.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient — cyan → teal → indigo (160° in CSS).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFF06B6D4), // cyan-500
                  Color(0xFF0E7490), // cyan-800
                  Color(0xFF3730A3), // indigo-800
                ],
                stops: [0.0, 0.38, 1.0],
              ),
            ),
          ),

          // Decorative radial glows.
          Positioned(
            top: -90,
            right: -90,
            child: _Glow(
              size: 300,
              color: const Color(0xFF14B8A6).withOpacity(0.55),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -80,
            child: _Glow(
              size: 260,
              color: const Color(0xFF4F46E5).withOpacity(0.60),
            ),
          ),

          // Giant watermark logo, faded.
          Positioned(
            top: 150,
            right: -150,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.10,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/logo-mark.png',
                    width: 460,
                    height: 460,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          // Top brand row.
          Positioned(
            top: mq.padding.top + 22,
            left: 24,
            right: 24,
            child: const _BrandRow(),
          ),

          // Hero headline.
          Positioned(
            left: 24,
            right: 24,
            top: mq.padding.top + 160,
            child: const _HeroCopy(),
          ),

          // Bottom glass action sheet.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ActionSheet(
              bottomInset: mq.padding.bottom,
              onGetStarted: () => _goToLogin(context, ref),
              onSignIn: () => _goToLogin(context, ref),
            ),
          ),
        ],
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
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
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
        Text(
          b.productName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34D399),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF34D399),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'BY ${companyName.toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
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
            fontWeight: FontWeight.w800,
            height: 1.04,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Track attendance with GPS, complete field tasks and request '
            'leave — all from one app built for the ground.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Bottom glass action sheet — feature dots + Get Started + Sign in
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

  static const _features = [
    ('Attendance', Color(0xFF34D399)),
    ('Tasks', Colors.white),
    ('Leave', Color(0xFFA5F3FC)),
    ('Team', Color(0xFFC4B5FD)),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(30),
        topRight: Radius.circular(30),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(22, 22, 22, bottomInset + 24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.30)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final f in _features)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: f.$2,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          f.$1,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _GetStartedButton(onTap: onGetStarted),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onSignIn,
                behavior: HitTestBehavior.opaque,
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    children: const [
                      TextSpan(text: 'Already have an account? '),
                      TextSpan(
                        text: 'Sign in',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
// "Get Started →" — white button with primary-dark text
// ──────────────────────────────────────────────────────────────────────

class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Get Started',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.primaryDark,
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Soft radial glow blob used in the background.
// ──────────────────────────────────────────────────────────────────────

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
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
            stops: const [0, 0.7],
          ),
        ),
      ),
    );
  }
}
