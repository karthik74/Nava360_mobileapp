import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralised design tokens for the HRMS app — glass morphism revision.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFF4F46E5);
  static const primaryDark = Color(0xFF3730A3);
  static const accent = Color(0xFF06B6D4);
  static const pink = Color(0xFFEC4899);

  // Page chrome (still used in a few "neutral" surfaces inside glass cards).
  static const bg = Color(0xFFEEF1F8);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF4F6FB);

  // Type
  static const ink = Color(0xFF0F172A);
  static const inkSoft = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const hairline = Color(0x33FFFFFF); // glass hairline (white 20%)

  // Status
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);

  // ── Glass tokens ─────────────────────────────────────────────
  // White-tinted frosted surfaces (used by GlassCard).
  static final glassFill = Colors.white.withOpacity(0.45);
  static final glassFillStrong = Colors.white.withOpacity(0.62);
  static final glassFillSubtle = Colors.white.withOpacity(0.28);
  static final glassBorder = Colors.white.withOpacity(0.55);
  static final glassBorderSubtle = Colors.white.withOpacity(0.32);

  // Mesh-background palette (the canvas behind the glass).
  static const meshA = Color(0xFF6366F1); // indigo
  static const meshB = Color(0xFF06B6D4); // cyan
  static const meshC = Color(0xFFEC4899); // hot pink
  static const meshD = Color(0xFF8B5CF6); // violet
  static const meshBase = Color(0xFFEEF1F8);

  // Gradients (kept names for backwards compatibility).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
  );

  static const successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
  );

  static const warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
  );

  static const dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFF87171)],
  );
}

class AppShadows {
  AppShadows._();

  static const card = [
    BoxShadow(
      color: Color(0x0F101828),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x06101828),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const soft = [
    BoxShadow(
      color: Color(0x0C101828),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const lifted = [
    BoxShadow(
      color: Color(0x266366F1),
      blurRadius: 26,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0F101828),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];
}

class AppRadii {
  AppRadii._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
  static const pill = 999.0;
}

class GlassBlur {
  GlassBlur._();
  static const card = 14.0;
  static const overlay = 20.0;
  static const chrome = 18.0;
}

/// Visible heights of the persistent chrome (excluding system insets).
/// Screens use these to compute the top/bottom padding so content aligns
/// cleanly below the app bar and above the bottom navigation.
class AppChrome {
  AppChrome._();
  static const appBarHeight = 46.0;
  static const bottomNavHeight = 56.0;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.meshBase,
    fontFamily: 'Roboto',
  );

  final textTheme = base.textTheme
      .apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      )
      .copyWith(
        headlineMedium: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: AppColors.ink,
        ),
        titleLarge: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
          color: AppColors.ink,
        ),
        titleMedium: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AppColors.inkSoft,
        ),
        labelMedium: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
          letterSpacing: 0.3,
        ),
      );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      iconTheme: IconThemeData(color: AppColors.ink),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withOpacity(0.55),
      selectedColor: AppColors.primary,
      secondarySelectedColor: AppColors.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        side: BorderSide(color: Colors.white.withOpacity(0.55)),
      ),
      labelStyle: const TextStyle(
        color: AppColors.inkSoft,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withOpacity(0.55),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
      labelStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
      prefixIconColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: BorderSide(color: Colors.white.withOpacity(0.55)),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: AppColors.primary.withOpacity(0.16),
      surfaceTintColor: Colors.transparent,
      height: AppChrome.bottomNavHeight,
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.primary : AppColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.primary : AppColors.muted,
          size: 22,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white.withOpacity(0.92),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withOpacity(0.45),
      space: 1,
      thickness: 1,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass background — the colourful mesh canvas the glass surfaces sit on.
// ─────────────────────────────────────────────────────────────────────────────

/// A reusable "wallpaper" that gives every glass card something to refract.
/// Cheap to draw — three large translucent blobs over a base gradient, with
/// a single low-cost white veil over the top to keep contrast reasonable.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child, this.intensity = 1.0});

  final Widget child;

  /// 0.0 → barely tinted; 1.0 → vivid. Use 0.7 on busy screens.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final i = intensity.clamp(0.0, 1.4);
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
        // Indigo blob — top left
        Positioned(
          top: -120,
          left: -100,
          child: _Blob(
            size: 360,
            color: AppColors.meshA.withOpacity(0.32 * i),
          ),
        ),
        // Cyan blob — top right
        Positioned(
          top: -80,
          right: -130,
          child: _Blob(
            size: 320,
            color: AppColors.meshB.withOpacity(0.28 * i),
          ),
        ),
        // Pink blob — bottom centre
        Positioned(
          bottom: -160,
          left: -40,
          child: _Blob(
            size: 380,
            color: AppColors.meshC.withOpacity(0.26 * i),
          ),
        ),
        // Violet blob — middle right
        Positioned(
          bottom: 60,
          right: -120,
          child: _Blob(
            size: 280,
            color: AppColors.meshD.withOpacity(0.24 * i),
          ),
        ),
        // Soft white veil to keep text readable.
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
        child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
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
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GlassCard — the workhorse frosted-glass container.
// ─────────────────────────────────────────────────────────────────────────────

/// Standard frosted-glass container used throughout the app.
///
/// API is backwards-compatible with the previous (non-glass) version. If a
/// solid `color` or `gradient` is provided, the glass blur is skipped so the
/// card paints the colour faithfully (e.g. gradient hero cards).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadii.lg,
    this.gradient,
    this.color,
    this.shadow,
    this.border,
    this.blurSigma = GlassBlur.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Gradient? gradient;
  final Color? color;
  final List<BoxShadow>? shadow;
  final Border? border;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final isOpaque = gradient != null || (color != null && color!.alpha > 240);
    final borderRadius = BorderRadius.circular(radius);
    final effectiveBorder = border ??
        Border.all(color: AppColors.glassBorder, width: 1);

    // Opaque path — preserves prior behaviour for gradient hero cards etc.
    if (isOpaque) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: gradient == null ? color : null,
          gradient: gradient,
          borderRadius: borderRadius,
          boxShadow: shadow ?? AppShadows.card,
          border: border,
        ),
        child: child,
      );
    }

    // True frosted-glass path.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow ?? AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? AppColors.glassFill,
              borderRadius: borderRadius,
              border: effectiveBorder,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.35),
                  Colors.white.withOpacity(0.05),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Convenience: a frosted glass "chrome" bar (app bar / bottom nav background).
class GlassChrome extends StatelessWidget {
  const GlassChrome({
    super.key,
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.borderTop = false,
    this.borderBottom = false,
    this.blurSigma = GlassBlur.chrome,
  });

  final Widget child;
  final BorderRadius? radius;
  final EdgeInsetsGeometry padding;
  final bool borderTop;
  final bool borderBottom;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final clip = radius ?? BorderRadius.zero;
    return ClipRRect(
      borderRadius: clip,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: clip,
            border: Border(
              top: borderTop
                  ? BorderSide(color: Colors.white.withOpacity(0.55))
                  : BorderSide.none,
              bottom: borderBottom
                  ? BorderSide(color: Colors.white.withOpacity(0.55))
                  : BorderSide.none,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper that returns a (color, label) tuple for status strings.
class StatusTone {
  final Color color;
  final String label;
  const StatusTone(this.color, this.label);

  static StatusTone forAttendance(String s) {
    switch (s) {
      case 'PRESENT':
        return const StatusTone(AppColors.success, 'Present');
      case 'HALF_DAY':
        return const StatusTone(AppColors.warning, 'Half day');
      case 'ABSENT':
        return const StatusTone(AppColors.danger, 'Absent');
      case 'ON_LEAVE':
        return const StatusTone(AppColors.info, 'On leave');
      case 'HOLIDAY':
        return const StatusTone(AppColors.accent, 'Holiday');
      default:
        return StatusTone(AppColors.muted, s);
    }
  }

  static StatusTone forLeave(String s) {
    switch (s) {
      case 'APPROVED':
        return const StatusTone(AppColors.success, 'Approved');
      case 'REJECTED':
        return const StatusTone(AppColors.danger, 'Rejected');
      case 'CANCELLED':
        return const StatusTone(AppColors.muted, 'Cancelled');
      default:
        return const StatusTone(AppColors.warning, 'Pending');
    }
  }
}
