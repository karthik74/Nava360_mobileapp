
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

// ------------------------------------------------------------------
// Linkified text
// ------------------------------------------------------------------

/// Plain text whose http(s) URLs are tappable and open in the external
/// browser. Only http/https ever launches — never intent:/file: schemes.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style, this.linkColor});

  final String text;
  final TextStyle? style;
  final Color? linkColor;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  static final RegExp _urlRe = RegExp("https?://[^\\s<>\"')]+");
  static final RegExp _trailingPunct = RegExp(r'[.,;:!?]+$');

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Spans are rebuilt every build; retire the previous taps' recognizers.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final matches = _urlRe.allMatches(widget.text).toList();
    if (matches.isEmpty) return Text(widget.text, style: widget.style);

    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final linkStyle = base.copyWith(
      color: widget.linkColor ?? AppColors.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      final raw = m.group(0)!;
      // Trailing sentence punctuation belongs to the prose, not the URL.
      final url = raw.replaceFirst(_trailingPunct, '');
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          final uri = Uri.tryParse(url);
          if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        };
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: url, style: linkStyle, recognizer: recognizer));
      if (url.length < raw.length) {
        spans.add(TextSpan(text: raw.substring(url.length)));
      }
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

// ------------------------------------------------------------------
// Empty / Error / Loading states
// ------------------------------------------------------------------

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkSoft,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

class AppErrorPanel extends StatelessWidget {
  const AppErrorPanel({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.dangerTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class AppLoadingBlock extends StatelessWidget {
  const AppLoadingBlock({super.key, this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.hairline),
        ),
        padding: const EdgeInsets.all(16),
        clipBehavior: Clip.hardEdge,
        // Content keeps its natural height and is clipped to [height], so
        // any requested height renders without an overflow stripe.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _bone(40, 40, 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bone(double.infinity, 12, 6, widthFactor: 0.7),
                      const SizedBox(height: 8),
                      _bone(double.infinity, 10, 5, widthFactor: 0.45),
                    ],
                  ),
                ),
              ],
            ),
            if (height > 90) ...[
              const SizedBox(height: 14),
              _bone(double.infinity, 10, 5),
              const SizedBox(height: 8),
              _bone(double.infinity, 10, 5, widthFactor: 0.8),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _bone(double w, double h, double r, {double widthFactor = 1}) {
    final box = Container(
      width: w == double.infinity ? null : w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(r),
      ),
    );
    if (w != double.infinity) return box;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: box,
    );
  }
}

/// Soft sweeping shimmer for skeleton placeholders.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final t = _c.value * 2 - 0.5;
          return LinearGradient(
            begin: Alignment(-1 + t * 2, 0),
            end: Alignment(t * 2, 0),
            colors: const [
              Color(0x00FFFFFF),
              Color(0x99FFFFFF),
              Color(0x00FFFFFF),
            ],
          ).createShader(rect);
        },
        child: child,
      ),
    );
  }
}

// ------------------------------------------------------------------
// Typography / Sections
// ------------------------------------------------------------------

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onDark = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Use white/translucent-white text. Pass true when this header sits
  /// directly on a deep surface.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : AppColors.ink;
    final subtitleColor =
        onDark ? Colors.white.withOpacity(0.72) : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                    letterSpacing: -0.24,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              letterSpacing: -0.7,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Buttons & Chips
// ------------------------------------------------------------------

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = 0,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  icon,
                  size: 19,
                  color: color ?? AppColors.ink,
                ),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.bg, width: 2),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppQuickAction extends StatelessWidget {
  const AppQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TappableGlass(
      onTap: onTap,
      radius: AppRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.15,
                color: AppColors.ink,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Color(0xFFB3C0C3),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Cards
// ------------------------------------------------------------------

/// Premium deep card (brand-derived surface with soft glows).
class AnimatedGradientCard extends StatelessWidget {
  const AnimatedGradientCard({
    super.key,
    required this.child,
    this.gradient,
    this.height,
  });

  final Widget child;
  final Gradient? gradient;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.lifted,
      ),
      child: gradient != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: gradient),
                child: Padding(padding: const EdgeInsets.all(20), child: child),
              ),
            )
          : _DeepCard(radius: 22, padding: const EdgeInsets.all(20), child: child),
    );
  }
}

/// Deep brand surface with glows and rings (card form).
class _DeepCard extends StatelessWidget {
  const _DeepCard({required this.child, required this.radius, required this.padding});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.heroGradient),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(1.05, -1.1),
                      radius: 1.3,
                      colors: [
                        Colors.white.withOpacity(0.28),
                        Colors.white.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-1.1, 1.2),
                      radius: 1.0,
                      colors: [
                        AppColors.glow.withOpacity(0.42),
                        AppColors.glow.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -60,
              top: -60,
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _TappableGlass(
      onTap: onTap,
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFFB3C0C3)),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 21,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                letterSpacing: -0.45,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Internal: tappable card surface used by StatTile etc.
// ------------------------------------------------------------------

class _TappableGlass extends StatelessWidget {
  const _TappableGlass({
    required this.child,
    required this.padding,
    required this.radius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: br,
          side: const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withOpacity(0.08),
          highlightColor: AppColors.primary.withOpacity(0.04),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Dashboard widgets
// ------------------------------------------------------------------

/// Deep hero card at the top of the employee dashboard: live clock / timer,
/// check-in & check-out tiles and a slide-to-confirm check in / out.
class AttendanceHeroCard extends StatelessWidget {
  const AttendanceHeroCard({
    super.key,
    required this.timerText,
    required this.hasCheckedIn,
    required this.hasCheckedOut,
    required this.checkInTime,
    required this.checkOutTime,
    required this.onTap,
    this.busy = false,
    this.location = '—',
  });

  final String timerText;
  final bool hasCheckedIn;
  final bool hasCheckedOut;
  final String checkInTime;
  final String checkOutTime;
  final VoidCallback onTap;

  /// While a check-in/out request is in flight — shows a spinner and blocks taps.
  final bool busy;
  final String location;

  @override
  Widget build(BuildContext context) {
    final onClock = hasCheckedIn && !hasCheckedOut;
    final pillLabel = hasCheckedOut
        ? 'Checked out'
        : hasCheckedIn
            ? 'Checked in'
            : 'Not checked in';
    final pillColor = hasCheckedOut
        ? AppColors.muted
        : hasCheckedIn
            ? AppColors.checkIn
            : AppColors.warning;
    final caption = hasCheckedOut
        ? 'Shift complete · well done'
        : hasCheckedIn
            ? 'On the clock since $checkInTime'
            : 'Slide below when you reach work';

    // Soft theme: a white card floating on the canvas; colour carries meaning
    // only — green to check in, red to check out.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Today's shift",
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: pillColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulseDot(color: pillColor, animate: onClock),
                    const SizedBox(width: 7),
                    Text(
                      pillLabel,
                      style: TextStyle(
                        color: pillColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              timerText,
              key: ValueKey(timerText.length),
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
                height: 1.1,
                letterSpacing: -1.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  location == '—' ? caption : '$caption · $location',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HeroMiniCard(
                  label: 'Check-in',
                  value: checkInTime,
                  icon: Icons.login_rounded,
                  color: AppColors.checkIn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniCard(
                  label: 'Check-out',
                  value: checkOutTime,
                  icon: Icons.logout_rounded,
                  color: AppColors.checkOut,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasCheckedOut)
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.successTint,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                  SizedBox(width: 8),
                  Text(
                    'Done for today',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            _SlideToConfirm(
              label: hasCheckedIn ? 'Slide to check out' : 'Slide to check in',
              color: hasCheckedIn ? AppColors.checkOut : AppColors.checkIn,
              icon: hasCheckedIn ? Icons.logout_rounded : Icons.login_rounded,
              busy: busy,
              onConfirmed: onTap,
            ),
        ],
      ),
    );
  }
}

class _HeroMiniCard extends StatelessWidget {
  const _HeroMiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide-to-confirm used by the hero card (check in / check out).
class _SlideToConfirm extends StatefulWidget {
  const _SlideToConfirm({
    required this.label,
    required this.onConfirmed,
    required this.color,
    required this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback onConfirmed;

  /// Action colour — green to check in, red to check out.
  final Color color;
  final IconData icon;
  final bool busy;

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  double _from = 0;
  late final AnimationController _back;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy controller first built inside dispose() throws.
    _back = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() {
        setState(() => _drag = _from * (1 - Curves.easeOutBack.transform(_back.value)));
      });
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const knob = 46.0;
      final max = (c.maxWidth - knob - 8).clamp(1.0, double.infinity);
      final p = (_drag / max).clamp(0.0, 1.0);
      return Semantics(
        button: true,
        label: widget.label,
        onTap: widget.busy ? null : widget.onConfirmed,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: widget.color.withOpacity(0.35)),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: knob + 8 + _drag,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(colors: [
                      widget.color.withOpacity(0),
                      widget.color.withOpacity(0.3),
                    ]),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: (1 - p * 1.8).clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Text(
                      widget.busy ? 'Please wait…' : widget.label,
                      style: TextStyle(
                        color: Color.lerp(widget.color, Colors.black, 0.18),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 3 + _drag,
                top: 3,
                child: GestureDetector(
                  onTap: widget.busy ? null : widget.onConfirmed,
                  onHorizontalDragUpdate: widget.busy
                      ? null
                      : (d) => setState(() => _drag = (_drag + d.delta.dx).clamp(0.0, max)),
                  onHorizontalDragEnd: widget.busy
                      ? null
                      : (_) {
                          if (_drag >= max * 0.9) {
                            HapticFeedback.heavyImpact();
                            widget.onConfirmed();
                          }
                          _from = _drag;
                          _back.forward(from: 0);
                        },
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      color: widget.color,
                      // Glossy knob: highlight top-left over the action colour.
                      gradient: RadialGradient(
                        center: const Alignment(-0.4, -0.55),
                        radius: 0.9,
                        colors: [
                          Color.lerp(widget.color, Colors.white, 0.45)!,
                          widget.color,
                          Color.lerp(widget.color, Colors.black, 0.12)!,
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withOpacity(0.45),
                          blurRadius: 14,
                          spreadRadius: -4,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: widget.busy
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Icon(widget.icon, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.animate});
  final Color color;
  final bool animate;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.animate)
                Container(
                  width: 7 + 9 * t,
                  height: 7 + 9 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withOpacity(1 - t),
                      width: 1.6,
                    ),
                  ),
                ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Stat tile used in the dashboard grid.
class StatTileV2 extends StatelessWidget {
  const StatTileV2({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      label: label,
      value: value,
      icon: icon,
      color: color,
      onTap: onTap,
    );
  }
}

/// Quick action row used under "Quick actions".
class QuickActionRow extends StatelessWidget {
  const QuickActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TappableGlass(
      onTap: onTap,
      radius: AppRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.15,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Color(0xFFB3C0C3),
          ),
        ],
      ),
    );
  }
}

class TodayScheduleItem {
  const TodayScheduleItem({
    required this.time,
    required this.title,
    required this.meta,
    required this.tone,
    this.onTap,
  });
  final String time;
  final String title;
  final String meta;
  final Color tone;
  final VoidCallback? onTap;
}

/// Card with hairline-divided rows used under "Today".
class TodayScheduleList extends StatelessWidget {
  const TodayScheduleList({super.key, required this.items});
  final List<TodayScheduleItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.event_available_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Nothing scheduled for today. Enjoy the calm.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.inkSoft,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.hairlineSoft,
                indent: 70,
              ),
            _TodayRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.item});
  final TodayScheduleItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: Text(
                  item.time,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: item.tone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.meta,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (item.onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFFB3C0C3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.size = 38,
    this.radius = 11,
    this.imageUrl,
  });

  final String name;
  final double size;
  final double radius;

  /// Optional absolute photo URL. When set, the image is shown with the
  /// initial as a fallback (during load or on error).
  final String? imageUrl;

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final initialText = Text(
      initial,
      style: TextStyle(
        color: AppColors.deep,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.hairline),
      ),
      alignment: Alignment.center,
      child: hasImage
          ? Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(child: initialText),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : Center(child: initialText),
            )
          : initialText,
    );
  }
}
