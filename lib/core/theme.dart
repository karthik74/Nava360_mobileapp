import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralised design tokens — "Soft" theme (Nava360 redesign v2).
///
/// Airy lavender canvas, white rounded cards that float on soft tinted
/// shadows, pill buttons, and a vivid brand-gradient panel for headers and
/// hero cards (white text). One action colour: the deployment's runtime brand
/// colour. Token names are kept stable so every screen reskins without code
/// changes.
class AppColors {
  AppColors._();

  // Brand. NOT const: replaced at runtime with the deployment's configured
  // colour via [applyBrand] (core/branding.dart), so one build serves every
  // company. Const usages must copy, not reference.
  static const Color _defaultPrimary = Color(0xFF00748C); // teal
  static const Color _defaultPrimaryDark = Color(0xFF005B6E);
  static Color primary = _defaultPrimary;
  static Color primaryDark = _defaultPrimaryDark; // hover/darker
  static const accent = Color(0xFF2C5FB3); // secondary blue (used sparingly)
  static const pink = Color(0xFF6B46A8); // violet (kept token name)

  /// Lime "live" accent — success, live and in-progress states only, never
  /// big buttons.
  static const live = Color(0xFF2FBF71);

  /// Attendance actions — always green to check IN and red to check OUT, so
  /// the next action is obvious at a glance (readable on deep and white).
  static const checkIn = Color(0xFF22A35A);
  static const checkOut = Color(0xFFE5484D);

  /// Vivid brand surface for header panels and hero cards (white text on
  /// it). Derived from the brand by [applyBrand]; name kept for API stability.
  static const Color _defaultDeep = Color(0xFF00839E);
  static Color deep = _defaultDeep;

  // Page chrome
  static const bg = Color(0xFFF3F2FA); // lavender canvas
  static const surface = Colors.white; // cards / sheets
  static const surfaceAlt = Color(0xFFF7F6FC); // subtle fills, cells

  // Type
  static const ink = Color(0xFF1D1B38);
  static const inkSoft = Color(0xFF3A3858);
  static const muted = Color(0xFF7A7896);
  static const faint = Color(0xFFA6A4BF);
  static const hairline = Color(0xFFE9E8F3); // card borders
  static const hairlineSoft = Color(0xFFF1F0F8); // in-card dividers

  // Status (ink-strength so they read as text on their tints)
  static const success = Color(0xFF1D7A3E);
  static const warning = Color(0xFFB26B00);
  static const danger = Color(0xFFC2362F);
  static const info = Color(0xFF2C5FB3);

  // Status tints (pill / tile backgrounds)
  static const successTint = Color(0xFFE5F4EA);
  static const warningTint = Color(0xFFFFF1DB);
  static const dangerTint = Color(0xFFFDE8E7);
  static const infoTint = Color(0xFFE3EEFB);
  static const neutralTint = Color(0xFFEFEEF7);

  // ── Surface tokens (kept names; flat surfaces) ──
  static const glassFill = Colors.white;
  static const glassFillStrong = Colors.white;
  static const glassFillSubtle = Color(0xFFF7F6FC);
  static const glassBorder = Color(0xFFE9E8F3);
  static const glassBorderSubtle = Color(0xFFF1F0F8);

  // Decorative palette — glows on deep surfaces.
  static const meshA = Color(0xFF008CA8);
  static const meshB = Color(0xFF3CC2D8);
  static const meshC = Color(0xFF8CC63F);
  static const meshD = Color(0xFF4253A8);
  static const meshBase = Color(0xFFF3F2FA);

  // Deep brand gradient — hero cards, avatars (kept names). Recomputed from
  // the runtime brand colour by [applyBrand].
  static const LinearGradient _defaultHeroGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFF00839E), Color(0xFF3FB0C9)],
  );
  static LinearGradient heroGradient = _defaultHeroGradient;

  /// Soft light accent for glows on the vivid surface (hue-shifted brand).
  static Color glow = const Color(0xFF8FD8F0);

  /// Applies the deployment's runtime brand colour (null = product default).
  /// Called by the branding bootstrap before/while the first screens build;
  /// widgets pick the new tokens up as they (re)build.
  static void applyBrand(Color? brand) {
    if (brand == null) {
      primary = _defaultPrimary;
      primaryDark = _defaultPrimaryDark;
      deep = _defaultDeep;
      heroGradient = _defaultHeroGradient;
      glow = const Color(0xFF8FD8F0);
      return;
    }
    primary = brand;
    primaryDark = _shiftLightness(brand, -0.08);
    deep = _deepOf(brand);
    heroGradient = LinearGradient(
      begin: Alignment.bottomRight,
      end: Alignment.topLeft,
      colors: [deep, _lightOf(deep)],
    );
    glow = _glowOf(brand);
  }

  /// Vivid but white-text-safe version of the brand (lightness 0.32–0.48).
  static Color _deepOf(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness(hsl.lightness.clamp(0.32, 0.48))
        .withSaturation(hsl.saturation.clamp(0.45, 0.9))
        .toColor();
  }

  /// Lighter, slightly hue-shifted end of the panel gradient.
  static Color _lightOf(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withHue((hsl.hue + 14) % 360)
        .withLightness((hsl.lightness + 0.14).clamp(0.0, 0.66))
        .toColor();
  }

  static Color _glowOf(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withHue((hsl.hue + 38) % 360)
        .withSaturation(0.85)
        .withLightness(0.78)
        .toColor();
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
    colors: [Color(0xFF1D7A3E), Color(0xFF2E9E57)],
  );

  static const warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB26B00), Color(0xFFD98A1B)],
  );

  static const dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC2362F), Color(0xFFE5484D)],
  );
}

class AppShadows {
  AppShadows._();

  // Cards float on a soft, cool-tinted shadow (no hairline borders).
  static const card = [
    BoxShadow(
      color: Color(0x142A2470),
      blurRadius: 24,
      spreadRadius: -8,
      offset: Offset(0, 10),
    ),
  ];

  static const soft = [
    BoxShadow(
      color: Color(0x102A2470),
      blurRadius: 16,
      spreadRadius: -6,
      offset: Offset(0, 6),
    ),
  ];

  /// Floating surfaces: overlapping KPI cards, sheets, the bottom nav.
  static const lifted = [
    BoxShadow(
      color: Color(0x262A2470),
      blurRadius: 36,
      spreadRadius: -12,
      offset: Offset(0, 18),
    ),
  ];
}

class AppRadii {
  AppRadii._();
  static const sm = 12.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 26.0;
  static const pill = 999.0;
}

/// Kept for API compatibility. The theme is flat (no frosted blur), so these
/// are 0 — any remaining `BackdropFilter` that reads them is a no-op.
class GlassBlur {
  GlassBlur._();
  static const card = 0.0;
  static const overlay = 0.0;
  static const chrome = 0.0;
}

/// Visible heights of the persistent chrome (excluding system insets).
/// Screens use these to compute the top/bottom padding so content aligns
/// cleanly below the app bar and above the floating bottom navigation.
class AppChrome {
  AppChrome._();
  static const appBarHeight = 48.0;

  /// Floating capsule (56) + its bottom margin (8) + breathing room (8).
  static const bottomNavHeight = 72.0;
}

/// Shared text styles for the Pro components.
class AppText {
  AppText._();
  static const display = TextStyle(
    fontFamily: 'Geist',
    fontSize: 23,
    height: 1.18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.7,
    color: AppColors.ink,
  );
  static const title = TextStyle(
    fontFamily: 'Geist',
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    color: AppColors.ink,
  );
  static const section = TextStyle(
    fontFamily: 'Geist',
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.24,
    color: AppColors.ink,
  );
  static const body = TextStyle(
    fontFamily: 'Geist',
    fontSize: 14,
    height: 1.45,
    color: AppColors.ink,
  );
  static const label = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12.5,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.inkSoft,
  );
  static const caption = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12,
    height: 1.35,
    color: AppColors.muted,
  );
  static const number = TextStyle(
    fontFamily: 'Geist',
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: const Color(0xFFD4DEE0),
    outlineVariant: AppColors.hairline,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.surfaceAlt,
    surfaceContainer: AppColors.surfaceAlt,
    surfaceContainerHigh: AppColors.neutralTint,
    surfaceContainerHighest: AppColors.neutralTint,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Geist',
    splashFactory: InkSparkle.splashFactory,
  );

  final textTheme = base.textTheme
      .apply(
        fontFamily: 'Geist',
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      )
      .copyWith(
        headlineLarge: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
          color: AppColors.ink,
        ),
        headlineMedium: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          color: AppColors.ink,
        ),
        headlineSmall: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.45,
          color: AppColors.ink,
        ),
        titleLarge: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
          color: AppColors.ink,
        ),
        titleMedium: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.15,
          color: AppColors.ink,
        ),
        titleSmall: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        bodyLarge: const TextStyle(
          fontSize: 14,
          height: 1.45,
          color: AppColors.ink,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13.5,
          height: 1.45,
          color: AppColors.inkSoft,
        ),
        bodySmall: const TextStyle(
          fontSize: 12.5,
          height: 1.35,
          color: AppColors.muted,
        ),
        labelLarge: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        labelMedium: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
          letterSpacing: 0.1,
        ),
        labelSmall: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
          letterSpacing: 0.1,
        ),
      )
      // copyWith replaced whole styles above — put the family back on all.
      .apply(fontFamily: 'Geist');

  // Pill buttons (soft theme).
  const buttonShape = StadiumBorder();

  // Glossy finish painted over any filled/elevated button's own colour:
  // a soft top highlight and a faint bottom shade (keeps custom colours,
  // e.g. green check-in / red check-out, and just makes them shine).
  Widget gloss(BuildContext context, Set<WidgetState> states, Widget? child) {
    if (states.contains(WidgetState.disabled)) return child ?? const SizedBox();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x47FFFFFF), Color(0x0AFFFFFF), Color(0x00000000), Color(0x1F000000)],
            stops: [0, 0.48, 0.62, 1],
          ),
        ),
        child: child,
      ),
    );
  }
  const buttonText = TextStyle(
    fontFamily: 'Geist',
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.15,
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    // Every default back button becomes a white rounded square (soft theme).
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const _SquareBackIcon(),
    ),
    // Light, centred app bar on the lavender canvas (soft theme).
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      iconTheme: IconThemeData(color: AppColors.ink, size: 22),
      actionsIconTheme: IconThemeData(color: AppColors.ink, size: 22),
      titleTextStyle: TextStyle(
        fontFamily: 'Geist',
        color: AppColors.ink,
        fontSize: 16.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary,
      secondarySelectedColor: AppColors.primary,
      disabledColor: AppColors.surfaceAlt,
      checkmarkColor: Colors.white,
      showCheckmark: false,
      side: const BorderSide(color: AppColors.hairline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Geist',
        color: AppColors.inkSoft,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: 'Geist',
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.hairlineSoft),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.faint, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      floatingLabelStyle: TextStyle(color: AppColors.primary, fontSize: 14),
      helperStyle: const TextStyle(color: AppColors.muted, fontSize: 12.5),
      errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12.5),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: Color(0xFFE3E2EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: Color(0xFFE3E2EF)),
      ),
      disabledBorder: OutlineInputBorder(
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
        disabledBackgroundColor: AppColors.neutralTint,
        disabledForegroundColor: AppColors.faint,
        textStyle: buttonText,
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        elevation: 0,
        shape: buttonShape,
        backgroundBuilder: gloss,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.neutralTint,
        disabledForegroundColor: AppColors.faint,
        textStyle: buttonText,
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: buttonShape,
        backgroundBuilder: gloss,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: Color(0xFFE0DFEC)),
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(44, 44),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.inkSoft,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.hairline)),
        textStyle: const WidgetStatePropertyAll(TextStyle(
          fontFamily: 'Geist',
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        )),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.muted,
      labelStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.hairline,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.primary, width: 2.5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.primary : const Color(0xFFD5E0E3),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
      ),
      side: const BorderSide(color: Color(0xFFB9C7CA), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.primary : const Color(0xFFB9C7CA),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.inkSoft,
      textColor: AppColors.ink,
      titleTextStyle: TextStyle(
        fontFamily: 'Geist',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.15,
        color: AppColors.ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Geist',
        fontSize: 12.5,
        color: AppColors.muted,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.deep,
      indicatorColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'Geist',
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : Colors.white70,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.deep : Colors.white70,
          size: 22,
        );
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: buttonText,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.hairlineSoft,
      circularTrackColor: AppColors.hairlineSoft,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: 'Geist',
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: AppColors.live,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.35,
        color: AppColors.ink,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 14.5,
        height: 1.45,
        color: AppColors.inkSoft,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0x330B1D21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.hairline),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 14.5,
        color: AppColors.ink,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Color(0xFFC6D3D6),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairlineSoft,
      space: 1,
      thickness: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Geist',
        color: Colors.white,
        fontSize: 12.5,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Backgrounds
// ─────────────────────────────────────────────────────────────────────────────

/// The neutral canvas behind content screens (kept name/API).
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child, this.intensity = 1.0});

  final Widget child;

  /// Kept for API compatibility; no longer used.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Container(color: AppColors.bg, child: child);
  }
}

/// Deep premium backdrop (brand-derived) with soft brand and lime glows and a
/// faint watermark logo. Used behind the Welcome screen and immersive heroes.
class FieldReadyBackdrop extends StatelessWidget {
  const FieldReadyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: AppColors.heroGradient)),
        Positioned(
          top: -120,
          right: -120,
          child: _Blob(
            size: 380,
            color: Colors.white.withOpacity(0.28),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -110,
          child: _Blob(
            size: 320,
            color: AppColors.glow.withOpacity(0.45),
          ),
        ),
        Positioned(
          top: 150,
          right: -150,
          // Faint concentric rings (the logo PNG has an opaque background,
          // so tinting it drew a visible pale square).
          child: const IgnorePointer(
            child: CustomPaint(
              size: Size(460, 460),
              painter: _BackdropRingsPainter(),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackdropRingsPainter extends CustomPainter {
  const _BackdropRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.12);
    for (final r in [90.0, 150.0, 210.0]) {
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
// GlassCard — the workhorse card (kept name/API).
// ─────────────────────────────────────────────────────────────────────────────

/// Standard card: white, 1px hairline, radius 16, barely-there shadow.
/// With a `gradient` it paints a premium surface (no border) instead.
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
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: hasGradient ? null : (color ?? AppColors.surface),
        gradient: gradient,
        borderRadius: borderRadius,
        boxShadow: shadow ?? (hasGradient ? AppShadows.lifted : AppShadows.card),
        border: hasGradient
            ? null
            : border, // soft theme: floats on its shadow, no hairline
      ),
      child: child,
    );
  }
}

/// Flat chrome bar (app bar / bottom nav background) — kept name/API.
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

/// Small status pill: tinted background, ink-strength text, no border.
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
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

/// White rounded square with a chevron — the soft theme's back button icon.
class _SquareBackIcon extends StatelessWidget {
  const _SquareBackIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        boxShadow: AppShadows.soft,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.chevron_left_rounded, size: 24, color: AppColors.ink),
    );
  }
}
