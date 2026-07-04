import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium app-opening / loading screen for Nava360.
///
/// A clean white screen with the brand logo at the centre that:
///   • fades in and gently scales up on first appearance (professional entrance)
///   • keeps a subtle, continuous pulse so it never feels static
///   • is wrapped by a rotating teal → green gradient ring (the brand loader)
///   • shows the app name and a short loading caption below
///
/// It is intentionally self-contained and lightweight — three small
/// [AnimationController]s and a single [CustomPainter], no extra packages — so
/// it is smooth on low-end Android and iOS alike and is safe to show as the
/// very first frame while the app bootstraps.
///
/// Reusable: drop it into any full-screen `loading:` state, or use it as the
/// splash while routing decides between Home and Login (it does not navigate
/// itself — navigation stays with the router).
class AppLoadingScreen extends StatefulWidget {
  const AppLoadingScreen({
    super.key,
    this.title = 'NAVA360',
    this.message = 'Loading your workspace...',
    this.logoAsset = 'assets/images/nava360_logo.png',
  });

  /// App name shown under the logo.
  final String title;

  /// Short caption shown under the title.
  final String message;

  /// Logo image asset path.
  final String logoAsset;

  // ── Brand palette ──────────────────────────────────────────────────────
  static const Color teal = Color(0xFF008196);
  static const Color green = Color(0xFF76B82A);
  static const Color background = Color(0xFFFFFFFF);

  @override
  State<AppLoadingScreen> createState() => _AppLoadingScreenState();
}

class _AppLoadingScreenState extends State<AppLoadingScreen>
    with TickerProviderStateMixin {
  // Entrance: fade + scale-up, runs once.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  // Gentle, never-ending pulse so the logo feels alive.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  // Continuous rotation that drives the gradient ring.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final Animation<double> _fade =
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  late final Animation<double> _entranceScale = Tween<double>(
    begin: 0.82,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
  late final Animation<double> _pulseScale = Tween<double>(
    begin: 1.0,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _entrance.forward();
    _pulse.repeat(reverse: true);
    _spin.repeat();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive sizing: scale to the smaller screen edge, clamped so it stays
    // tasteful from compact phones to large tablets.
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final logoSize = (shortestSide * 0.22).clamp(72.0, 132.0);
    final ringSize = logoSize * 1.9;

    return Scaffold(
      backgroundColor: AppLoadingScreen.background,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo inside the rotating brand ring.
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotating teal → green gradient ring.
                      AnimatedBuilder(
                        animation: _spin,
                        builder: (_, __) => CustomPaint(
                          size: Size.square(ringSize),
                          painter: _BrandRingPainter(turns: _spin.value),
                        ),
                      ),
                      // Logo with combined entrance + pulse scale.
                      AnimatedBuilder(
                        animation: Listenable.merge([_entranceScale, _pulseScale]),
                        builder: (_, child) => Transform.scale(
                          scale: _entranceScale.value * _pulseScale.value,
                          child: child,
                        ),
                        child: Image.asset(
                          widget.logoAsset,
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                          // Graceful fallback if the asset is missing.
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.account_balance_wallet_rounded,
                            size: logoSize * 0.7,
                            color: AppLoadingScreen.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: logoSize * 0.42),
                // App name.
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppLoadingScreen.teal,
                    letterSpacing: 3.0,
                  ),
                ),
                const SizedBox(height: 8),
                // Loading caption.
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black.withOpacity(0.45),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a soft full circle "track" plus a rotating gradient arc that sweeps
/// from teal to green — the branded circular loader around the logo.
class _BrandRingPainter extends CustomPainter {
  _BrandRingPainter({required this.turns});

  /// Current rotation in turns (0..1), driven by the spin controller.
  final double turns;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.width * 0.055;
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Faint full-circle track.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppLoadingScreen.teal.withOpacity(0.10);
    canvas.drawCircle(center, radius, track);

    // Rotating gradient arc (≈ 3/4 of the circle) with rounded ends.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turns * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [
          AppLoadingScreen.teal,
          AppLoadingScreen.green,
          AppLoadingScreen.teal,
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect, 0, math.pi * 1.5, false, arc);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandRingPainter old) => old.turns != turns;
}
