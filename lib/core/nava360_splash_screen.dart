// =============================================================================
//  NAVA360 — Premium Splash / Loading Animation
// -----------------------------------------------------------------------------
//  The two outer brand swooshes (blue upper arc + green lower arc, incl. the
//  arrow head) rotate clockwise as a continuous loading ring, while the inner
//  logo (figures, hands, leaf, icons) stays static with a soft fade + scale-in.
//
//  Assets required (see pubspec snippet at the bottom of this file):
//    assets/nava360_ring.png     -> the two outer arcs only  (transparent)
//    assets/nava360_center.png   -> inner content only        (transparent)
//
//  Both assets share the same square canvas and the same centre point, so the
//  ring spins around the exact centre of the logo — no wobble.
//
//  Built for 60 FPS: the ring + its glow are wrapped in a RepaintBoundary, so
//  the (relatively costly) blur is rasterised once and only the cheap rotation
//  transform + glow-opacity composite run each frame.
// =============================================================================

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class Nava360SplashScreen extends StatefulWidget {
  const Nava360SplashScreen({
    super.key,
    this.onFinish,
    this.minDisplay = const Duration(seconds: 3),
  });

  /// Called once [minDisplay] has elapsed. Use it to navigate to your home
  /// screen (or wrap it around your real bootstrap / async init future).
  final VoidCallback? onFinish;

  /// Minimum time the splash stays on screen before [onFinish] fires.
  final Duration minDisplay;

  @override
  State<Nava360SplashScreen> createState() => _Nava360SplashScreenState();
}

class _Nava360SplashScreenState extends State<Nava360SplashScreen>
    with TickerProviderStateMixin {
  // ----------------------------- Tunables ------------------------------------
  static const Duration _kRevolution = Duration(seconds: 2); // 2s / full turn
  static const bool _kClockwise = true;
  // Requested ease-in-out gives a gentle "breathing" rotation. Velocity is ~0
  // at the seam between revolutions, so it loops smoothly with no jump.
  // Swap to Curves.linear if you prefer perfectly constant spinner speed.
  static const Curve _kRotationCurve = Curves.easeInOut;

  static const Duration _kEntrance = Duration(milliseconds: 750);
  static const double _kCenterScaleFrom = 0.95; // 95% -> 100%

  static const double _kLogoSize = 240; // logical px (dp) of the whole mark

  static const bool _kGlowEnabled = true;
  static const double _kGlowBlur = 14; // sigma
  static const double _kGlowScale = 1.05;
  static const double _kGlowMinOpacity = 0.10;
  static const double _kGlowMaxOpacity = 0.32;
  static const Duration _kGlowPulse = Duration(milliseconds: 1700);
  // ---------------------------------------------------------------------------

  late final AnimationController _spin;     // continuous ring rotation
  late final AnimationController _entrance; // one-shot fade + scale-in
  late final AnimationController _glow;     // subtle glow pulse

  late final Animation<double> _turns;
  late final Animation<double> _centerScale;
  late final Animation<double> _fade;
  late final Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();

    _spin = AnimationController(vsync: this, duration: _kRevolution)..repeat();
    _turns = Tween<double>(begin: 0, end: _kClockwise ? 1 : -1)
        .animate(CurvedAnimation(parent: _spin, curve: _kRotationCurve));

    _entrance = AnimationController(vsync: this, duration: _kEntrance)..forward();
    _centerScale = Tween<double>(begin: _kCenterScaleFrom, end: 1)
        .animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);

    _glow = AnimationController(vsync: this, duration: _kGlowPulse)
      ..repeat(reverse: true);
    _glowOpacity = Tween<double>(begin: _kGlowMinOpacity, end: _kGlowMaxOpacity)
        .animate(CurvedAnimation(parent: _glow, curve: Curves.easeInOut));

    if (widget.onFinish != null) {
      Future.delayed(widget.minDisplay, () {
        if (mounted) widget.onFinish!.call();
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _entrance.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF), // pure white
      body: Center(
        child: FadeTransition(
          opacity: _fade, // soft fade-in of the whole mark on launch
          child: SizedBox(
            width: _kLogoSize,
            height: _kLogoSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // --- Rotating ring (arcs) + matching colour glow -------------
                RotationTransition(
                  turns: _turns,
                  child: RepaintBoundary(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_kGlowEnabled)
                          FadeTransition(
                            opacity: _glowOpacity,
                            child: Transform.scale(
                              scale: _kGlowScale,
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: _kGlowBlur,
                                  sigmaY: _kGlowBlur,
                                ),
                                child: const Image(
                                  image: AssetImage('assets/nava360_ring.png'),
                                  width: _kLogoSize,
                                  height: _kLogoSize,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                        const Image(
                          image: AssetImage('assets/nava360_ring.png'),
                          width: _kLogoSize,
                          height: _kLogoSize,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        ),
                      ],
                    ),
                  ),
                ),

                // --- Static centre: figures, hands, leaf, icons --------------
                ScaleTransition(
                  scale: _centerScale,
                  child: const Image(
                    image: AssetImage('assets/nava360_center.png'),
                    width: _kLogoSize,
                    height: _kLogoSize,
                    filterQuality: FilterQuality.high,
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

// =============================================================================
//  pubspec.yaml — add the assets:
//
//  flutter:
//    assets:
//      - assets/nava360_ring.png
//      - assets/nava360_center.png
//
// -----------------------------------------------------------------------------
//  Example usage:
//
//  void main() => runApp(const MyApp());
//
//  class MyApp extends StatelessWidget {
//    const MyApp({super.key});
//    @override
//    Widget build(BuildContext context) {
//      return MaterialApp(
//        debugShowCheckedModeBanner: false,
//        home: Builder(
//          builder: (context) => Nava360SplashScreen(
//            minDisplay: const Duration(seconds: 3),
//            onFinish: () => Navigator.of(context).pushReplacement(
//              MaterialPageRoute(builder: (_) => const HomeScreen()),
//            ),
//          ),
//        ),
//      );
//    }
//  }
//
//  Tip: to remove the brief white flash before the first Flutter frame, pair
//  this with the `flutter_native_splash` package using the same white (#FFFFFF)
//  background and the full logo as the native splash image.
// =============================================================================
