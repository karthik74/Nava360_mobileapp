import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralised design tokens — Light Modern Enterprise SaaS theme:
/// white cards on a soft light-gray canvas, a deep-blue primary, slate
/// typography, soft gray borders and minimal shadows. Token names are kept
/// stable so every screen reskins without code changes.
class AppColors {
  AppColors._();

  // Brand — deep blue by default. NOT const: replaced at runtime with the
  // deployment's configured color via [applyBrand] (core/branding.dart), so
  // one build serves every company. Const usages must copy, not reference.
  static const Color _defaultPrimary = Color(0xFF1D4ED8); // blue-700
  static const Color _defaultPrimaryDark = Color(0xFF1E40AF); // blue-800
  static Color primary = _defaultPrimary;
  static Color primaryDark = _defaultPrimaryDark; // hover/darker
  static const accent = Color(0xFF0EA5E9); // sky-500 (secondary, used sparingly)
  static const pink = Color(0xFF7C3AED); // violet-600 (kept token name)

  // Page chrome
  static const bg = Color(0xFFF1F5F9); // slate-100 — soft light gray canvas
  static const surface = Colors.white; // cards / sheets
  static const surfaceAlt = Color(0xFFF8FAFC); // slate-50 — subtle fills

  // Type
  static const ink = Color(0xFF0F172A); // slate-900
  static const inkSoft = Color(0xFF334155); // slate-700
  static const muted = Color(0xFF64748B); // slate-500
  static const hairline = Color(0xFFE2E8F0); // slate-200 — soft border/divider

  // Status (slightly deeper for crisp contrast on white)
  static const success = Color(0xFF16A34A); // green-600
  static const warning = Color(0xFFD97706); // amber-600
  static const danger = Color(0xFFDC2626); // red-600
  static const info = Color(0xFF2563EB); // blue-600

  // ── Surface tokens (kept names; now flat surfaces, not frosted glass) ──
  static const glassFill = Colors.white;
  static const glassFillStrong = Colors.white;
  static const glassFillSubtle = Color(0xFFF8FAFC);
  static const glassBorder = Color(0xFFE2E8F0);
  static const glassBorderSubtle = Color(0xFFEEF2F7);

  // Decorative palette — only used by FieldReadyBackdrop / success art now.
  static const meshA = Color(0xFF6366F1);
  static const meshB = Color(0xFF06B6D4);
  static const meshC = Color(0xFFEC4899);
  static const meshD = Color(0xFF8B5CF6);
  static const meshBase = Color(0xFFF1F5F9);

  // Subtle brand gradient — hero card, avatars (kept names). Recomputed from
  // the runtime brand color by [applyBrand].
  static const LinearGradient _defaultHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E40AF), Color(0xFF2563EB)],
  );
  static LinearGradient heroGradient = _defaultHeroGradient;

  /// Applies the deployment's runtime brand color (null = product default).
  /// Called by the branding bootstrap before/while the first screens build;
  /// widgets pick the new tokens up as they (re)build.
  static void applyBrand(Color? brand) {
    if (brand == null) {
      primary = _defaultPrimary;
      primaryDark = _defaultPrimaryDark;
      heroGradient = _defaultHeroGradient;
      return;
    }
    primary = brand;
    primaryDark = _shiftLightness(brand, -0.08);
    heroGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_shiftLightness(brand, -0.08), _shiftLightness(brand, 0.04)],
    );
  }

  static Color _shiftLightness(Color c, double delta) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.0, 1.0))
        .toColor();
  }

  static const successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
  );

  static const warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
  );

  static const dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
  );
}

class AppShadows {
  AppShadows._();

  // Minimal, soft enterprise shadows.
  static const card = [
    BoxShadow(
      color: Color(0x0D0F172A),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  static const soft = [
    BoxShadow(
      color: Color(0x080F172A),
      blurRadius: 8,
      offset: Offset(0, 1),
    ),
  ];

  static const lifted = [
    BoxShadow(
      color: Color(0x1A1D4ED8),
      blurRadius: 20,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x0D0F172A),
      blurRadius: 4,
      offset: Offset(0, 1),
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

/// Kept for API compatibility. The enterprise theme is flat (no frosted blur),
/// so these are 0 — any remaining `BackdropFilter` that reads them is a no-op.
class GlassBlur {
  GlassBlur._();
  static const card = 0.0;
  static const overlay = 0.0;
  static const chrome = 0.0;
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
      backgroundColor: AppColors.surfaceAlt,
      selectedColor: AppColors.primary,
      secondarySelectedColor: AppColors.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        side: const BorderSide(color: AppColors.hairline),
      ),
      labelStyle: const TextStyle(
        color: AppColors.inkSoft,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
      labelStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
      prefixIconColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: AppColors.primary, width: 1.6),
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
        side: const BorderSide(color: AppColors.hairline),
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
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
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
    // Enterprise theme: a clean, flat soft-gray canvas behind the cards.
    // (`intensity` kept for API compatibility; no longer used.)
    return Container(color: AppColors.bg, child: child);
  }
}

/// Bold cyan-teal-indigo gradient backdrop with a watermark logo and
/// decorative glows. Mirrors the Welcome screen "Field-Ready" treatment;
/// content screens (leaves, attendance) stack their UI on top of this.
class FieldReadyBackdrop extends StatelessWidget {
  const FieldReadyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
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
        Positioned(
          top: -90,
          right: -90,
          child: _Blob(
            size: 300,
            color: const Color(0xFF14B8A6).withOpacity(0.55),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -80,
          child: _Blob(
            size: 260,
            color: const Color(0xFF4F46E5).withOpacity(0.60),
          ),
        ),
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
    final borderRadius = BorderRadius.circular(radius);
    final hasGradient = gradient != null;

    // Flat enterprise card: solid white surface, soft gray border, minimal
    // shadow. Gradient cards (hero) paint their gradient with no border so the
    // brand colour reads cleanly.
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: hasGradient ? null : (color ?? AppColors.surface),
        gradient: gradient,
        borderRadius: borderRadius,
        boxShadow: shadow ?? AppShadows.card,
        border: hasGradient
            ? null
            : (border ?? Border.all(color: AppColors.hairline, width: 1)),
      ),
      child: child,
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
    // Flat solid chrome bar (app bar / bottom nav background).
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: clip,
        border: Border(
          top: borderTop
              ? const BorderSide(color: AppColors.hairline)
              : BorderSide.none,
          bottom: borderBottom
              ? const BorderSide(color: AppColors.hairline)
              : BorderSide.none,
        ),
      ),
      child: child,
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

  /// Today's attendance state for a team member (from /my-team/today-status).
  static StatusTone forTeamState(String s) {
    switch (s) {
      case 'PUNCHED_IN':
        return const StatusTone(AppColors.success, 'Punched In');
      case 'PUNCHED_OUT':
        return const StatusTone(AppColors.info, 'Punched Out');
      case 'LEAVE':
        return const StatusTone(AppColors.warning, 'Leave');
      case 'ABSENT':
        return const StatusTone(AppColors.danger, 'Absent');
      default:
        return const StatusTone(AppColors.muted, 'Not In');
    }
  }
}
