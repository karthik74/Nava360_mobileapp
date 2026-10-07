import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Nava360 "Pro" component library — the Flutter twin of the redesign canvas.
///
/// Building blocks (use these instead of hand-rolled containers):
///  * [ProHero] — deep brand header (full-bleed) with title, actions and slots
///    for [ProHeroStats], [ProHeroSegmented], [ProLiveLine], [ProHeroActions].
///  * [ProKpiStrip] — white KPI card that overlaps the bottom of a lifted hero.
///  * [ProSearchField] — 50px search field (optionally raised over the hero).
///  * [ProSectionHeader], [ProListGroup] + [ProListRow], [ProIconWell],
///    [ProAvatar], [ProPill], [ProSwipeDecision] for list screens.
///  * [ProFormHeader], [ProStepBar], [ProBottomBar], [ProField] for forms.
///  * [ProNote], [ProEmpty], [ProKeyValue], [ProProgressRow], [ProChipBar].
///  * [ProSlideToConfirm] — slide-to-check-in style confirmation.
///
/// Page structure for a list/detail screen:
/// ```dart
/// ProPage(
///   hero: ProHero(title: 'Travel claims', children: [ProHeroStats(...)],
///                 overlap: ProSearchField(raised: true, ...)),
///   children: [ ...sections... ],
/// )
/// ```

// ─────────────────────────────────────────────────────────────────────────────
// Hero
// ─────────────────────────────────────────────────────────────────────────────

/// Deep premium header used at the top of list, hub and detail screens.
///
/// It always fills its parent's width, so place it OUTSIDE horizontal list
/// padding (see [ProPage]). Pass [overlap] (a [ProKpiStrip] or a raised
/// [ProSearchField]) to have it straddle the hero's bottom edge.
class ProHero extends StatelessWidget {
  const ProHero({
    super.key,
    this.title,
    this.subtitle,
    this.kicker,
    this.leading,
    this.actions = const [],
    this.children = const [],
    this.overlap,
    this.titleWidget,
    this.showBack = false,
    this.onBack,
    this.safeTop = false,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 18),
  });

  /// Large title (24px). Ignored when [titleWidget] is set.
  final String? title;
  final String? subtitle;

  /// Small label above the title (e.g. "My team").
  final String? kicker;

  /// Custom leading widget (defaults to a back button when [showBack]).
  final Widget? leading;
  final List<Widget> actions;

  /// Slots under the title row: stats, segmented switch, live line, actions.
  final List<Widget> children;

  /// Widget that overlaps the bottom edge (KPI strip / raised search).
  final Widget? overlap;
  final Widget? titleWidget;
  final bool showBack;
  final VoidCallback? onBack;

  /// Adds the status-bar inset on top (screens without an AppBar).
  final bool safeTop;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final lead = leading ??
        (showBack
            ? ProHeroIconButton(
                icon: Icons.chevron_left_rounded,
                iconSize: 24,
                tooltip: 'Back',
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
              )
            : null);
    final top = padding.top + (safeTop ? MediaQuery.of(context).padding.top : 0);
    final hasTitleRow = lead != null ||
        titleWidget != null ||
        title != null ||
        kicker != null ||
        subtitle != null ||
        actions.isNotEmpty;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(padding.left, top, padding.right, padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasTitleRow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (lead != null) ...[lead, const SizedBox(width: 10)],
                Expanded(
                  child: titleWidget ??
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (kicker != null)
                            Text(
                              kicker!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          if (title != null)
                            Text(
                              title!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 24,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.65,
                                color: Colors.white,
                              ),
                            ),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: Colors.white70,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                        ],
                      ),
                ),
                for (final a in actions) ...[const SizedBox(width: 8), a],
              ],
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (hasTitleRow || i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: _HeroFrame(
        lift: overlap == null ? 0 : 38,
        children: [
          const _DeepBackground(),
          content,
          if (overlap != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding.left),
              child: overlap,
            ),
        ],
      ),
    );
  }
}

/// Lays out [background, content, overlap?]: the background spans the content
/// plus `lift` px; the overlap starts where the content ends, so it straddles
/// the background's bottom edge. Everything stays inside the box (taps work).
class _HeroFrame extends MultiChildRenderObjectWidget {
  const _HeroFrame({required this.lift, required super.children});
  final double lift;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeroFrame(lift);

  @override
  void updateRenderObject(BuildContext context, _RenderHeroFrame renderObject) {
    renderObject.lift = lift;
  }
}

class _HeroFrameData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeroFrame extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeroFrameData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeroFrameData> {
  _RenderHeroFrame(this._lift);

  double _lift;
  set lift(double v) {
    if (v == _lift) return;
    _lift = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeroFrameData) child.parentData = _HeroFrameData();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 390.0;
    final bg = firstChild!;
    final content = childAfter(bg)!;
    final overlap = childAfter(content);
    content.layout(BoxConstraints(minWidth: w, maxWidth: w), parentUsesSize: true);
    final ch = content.size.height;
    var total = ch;
    var bgH = ch;
    (content.parentData! as _HeroFrameData).offset = Offset.zero;
    if (overlap != null) {
      overlap.layout(BoxConstraints(minWidth: w, maxWidth: w), parentUsesSize: true);
      bgH = ch + _lift;
      (overlap.parentData! as _HeroFrameData).offset = Offset(0, ch);
      total = ch + overlap.size.height;
    }
    bg.layout(BoxConstraints.tightFor(width: w, height: bgH));
    (bg.parentData! as _HeroFrameData).offset = Offset.zero;
    size = constraints.constrain(Size(w, total));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _DeepBackground extends StatelessWidget {
  const _DeepBackground();

  @override
  Widget build(BuildContext context) => const ProDeepSurface(
        padding: EdgeInsets.zero,
        child: SizedBox.expand(),
      );
}

/// Scrollable page body: optional [hero] (full width) followed by padded,
/// evenly spaced [children]. Handles pull-to-refresh and the bottom clearance
/// for the floating tab bar ([clearNav]).
class ProPage extends StatelessWidget {
  const ProPage({
    super.key,
    this.hero,
    required this.children,
    this.onRefresh,
    this.controller,
    this.gap = 14,
    this.clearNav = false,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
    this.topInset = 0,
  });

  final Widget? hero;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final double gap;

  /// Leave room for the shell's floating bottom navigation.
  final bool clearNav;
  final EdgeInsets padding;

  /// Extra space above the hero (e.g. under the shell app bar).
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Inside the shell (extendBody) padding.bottom already includes the
    // floating tab bar; elsewhere it is just the system inset.
    final bottom = padding.bottom +
        (clearNav ? math.max(mq.padding.bottom, AppChrome.bottomNavHeight) : mq.padding.bottom);
    final list = ListView(
      controller: controller,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: topInset, bottom: bottom),
      children: [
        if (hero != null) hero!,
        Padding(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white,
      // Start below the shell app bar when the page sits under it.
      edgeOffset: topInset,
      onRefresh: onRefresh!,
      child: list,
    );
  }
}

/// The deep brand surface with soft brand / lime glows and faint rings.
class ProDeepSurface extends StatelessWidget {
  const ProDeepSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.deep),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(1.05, -1.1),
                      radius: 1.25,
                      colors: [
                        Color.lerp(AppColors.primary, Colors.white, 0.05)!
                            .withOpacity(0.62),
                        AppColors.primary.withOpacity(0),
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
                      center: const Alignment(-1.1, 1.15),
                      radius: 1.0,
                      colors: [
                        AppColors.live.withOpacity(0.2),
                        AppColors.live.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -70,
              top: -40,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(240, 240),
                  painter: _RingsPainter(),
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

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.07);
    canvas.drawCircle(c, size.width / 2, p);
    p.color = Colors.white.withOpacity(0.04);
    canvas.drawCircle(c, size.width / 2 + 32, p);
    p.color = Colors.white.withOpacity(0.03);
    canvas.drawCircle(c, size.width / 2 + 64, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 40×40 translucent icon button for use on deep surfaces.
class ProHeroIconButton extends StatelessWidget {
  const ProHeroIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge = false,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Shows a small red dot (e.g. unread notifications).
  final bool badge;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: iconSize, color: Colors.white),
              if (badge)
                Positioned(
                  top: 8,
                  right: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5484D),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.deep, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Data for one hero stat tile.
class ProStat {
  const ProStat({
    required this.label,
    required this.value,
    this.sub,
    this.dot,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? dot;
  final bool selected;

  /// When set the tile becomes a filter button.
  final VoidCallback? onTap;
}

/// Row of 2–4 stat tiles on a deep surface (they can act as filters).
class ProHeroStats extends StatelessWidget {
  const ProHeroStats({super.key, required this.stats});
  final List<ProStat> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _ProStatTile(stat: stats[i])),
        ],
      ],
    );
  }
}

class _ProStatTile extends StatelessWidget {
  const _ProStatTile({required this.stat});
  final ProStat stat;

  @override
  Widget build(BuildContext context) {
    final on = stat.selected;
    final fg = on ? AppColors.deep : Colors.white;
    return Material(
      color: on ? Colors.white : Colors.white.withOpacity(0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: on ? Colors.white : Colors.white.withOpacity(0.12),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: stat.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (stat.dot != null) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(color: stat.dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      stat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: fg.withOpacity(0.82),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  stat.value,
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (stat.sub != null)
                Text(
                  stat.sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: fg.withOpacity(0.72),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented switch on a deep surface (white pill marks the selection).
class ProHeroSegmented extends StatelessWidget {
  const ProHeroSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.icons,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: i == selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == selected
                        ? const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 12,
                              spreadRadius: -4,
                              offset: Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icons != null && i < icons!.length) ...[
                        Icon(
                          icons![i],
                          size: 15,
                          color: i == selected ? AppColors.deep : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: i == selected ? AppColors.deep : Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Live" status line on a deep surface with a pulsing dot.
class ProLiveLine extends StatelessWidget {
  const ProLiveLine({super.key, required this.text, this.color});
  final String text;

  /// Dot colour (defaults to the lime live accent).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          ProPulseDot(color: color ?? AppColors.live),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Color(0xE0FFFFFF),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small dot with an expanding ring.
class ProPulseDot extends StatefulWidget {
  const ProPulseDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  State<ProPulseDot> createState() => _ProPulseDotState();
}

class _ProPulseDotState extends State<ProPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s + s * 1.4 * t,
                height: s + s * 1.4 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withOpacity(1 - t),
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: s,
                height: s,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One quick action for [ProHeroActions].
class ProAction {
  const ProAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// White filled button (use for the single most important action).
  final bool primary;
}

/// Row of round quick actions on a deep surface.
class ProHeroActions extends StatelessWidget {
  const ProHeroActions({super.key, required this.actions});
  final List<ProAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in actions)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: a.onTap == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      a.onTap!();
                    },
              child: Opacity(
                opacity: a.onTap == null ? 0.45 : 1,
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: a.primary
                            ? Colors.white
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: a.primary
                              ? Colors.white
                              : Colors.white.withOpacity(0.15),
                        ),
                      ),
                      child: Icon(
                        a.icon,
                        size: 21,
                        color: a.primary ? AppColors.deep : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Identity block for detail heroes: avatar/icon + name + role + tags.
class ProHeroIdentity extends StatelessWidget {
  const ProHeroIdentity({
    super.key,
    required this.name,
    this.role,
    this.initials,
    this.icon,
    this.ringColor,
    this.tags = const [],
  });

  final String name;
  final String? role;

  /// Shown in a white squircle with a coloured ring (people/customers).
  final String? initials;

  /// Shown in a translucent squircle (claims, tickets, documents…).
  final IconData? icon;
  final Color? ringColor;
  final List<ProHeroTag> tags;

  @override
  Widget build(BuildContext context) {
    final ring = ringColor ?? AppColors.live;
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: initials != null ? Colors.white : Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: initials != null
                ? null
                : Border.all(color: Colors.white.withOpacity(0.18)),
            boxShadow: initials != null
                ? [
                    // Flutter paints shadows in list order (CSS is the
                    // reverse): outer lime ring first, deep gap on top.
                    BoxShadow(color: ring, spreadRadius: 5),
                    BoxShadow(color: AppColors.deep, spreadRadius: 3),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: initials != null
              ? Text(
                  initials!,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: AppColors.deep,
                  ),
                )
              : Icon(icon ?? Icons.description_outlined,
                  size: 28, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.55,
                  color: Colors.white,
                ),
              ),
              if (role != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    role!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Colors.white70,
                    ),
                  ),
                ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Wrap(spacing: 6, runSpacing: 6, children: tags),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum ProTagTone { neutral, ok, warn, bad }

/// Small tag pill on a deep surface.
class ProHeroTag extends StatelessWidget {
  const ProHeroTag(this.label, {super.key, this.tone = ProTagTone.neutral, this.icon});
  final String label;
  final ProTagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.white.withOpacity(0.1);
    Color border = Colors.white.withOpacity(0.14);
    Color fg = Colors.white;
    switch (tone) {
      case ProTagTone.ok:
        bg = AppColors.live.withOpacity(0.18);
        border = AppColors.live.withOpacity(0.4);
        fg = const Color(0xFFCDEE9E);
        break;
      case ProTagTone.warn:
        bg = const Color(0xFFF2B347).withOpacity(0.18);
        border = const Color(0xFFF2B347).withOpacity(0.45);
        fg = const Color(0xFFFFD690);
        break;
      case ProTagTone.bad:
        bg = const Color(0xFFE5484D).withOpacity(0.2);
        border = const Color(0xFFE5484D).withOpacity(0.45);
        fg = const Color(0xFFFFB3B5);
        break;
      case ProTagTone.neutral:
        break;
    }
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacked proportion bar (e.g. in / out / leave / absent) for deep surfaces.
class ProStackBar extends StatelessWidget {
  const ProStackBar({super.key, required this.parts, this.height = 8});

  /// (value, colour) pairs; widths are proportional to values.
  final List<MapEntry<double, Color>> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (a, p) => a + p.key);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].key > 0)
              Expanded(
                flex: math.max(1, (parts[i].key / (total == 0 ? 1 : total) * 1000).round()),
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 700 + i * 80),
                    curve: Curves.easeOutBack,
                    builder: (_, t, __) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: t.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: parts[i].value,
                          borderRadius: BorderRadius.circular(height / 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI strip, search, sections, lists
// ─────────────────────────────────────────────────────────────────────────────

/// One KPI cell.
class ProKpi {
  const ProKpi({
    required this.value,
    required this.label,
    this.progress,
    this.color,
    this.onTap,
    this.valueColor,
  });
  final String value;
  final String label;

  /// 0–1; draws a thin bar under the label.
  final double? progress;
  final Color? color;
  final Color? valueColor;
  final VoidCallback? onTap;
}

/// White KPI card. Pass it as `ProHero(overlap: ProKpiStrip(...))` to have it
/// straddle the hero's bottom edge, or use it standalone.
class ProKpiStrip extends StatelessWidget {
  const ProKpiStrip({super.key, required this.cells});
  final List<ProKpi> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.lifted,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: VerticalDivider(
                      width: 1, thickness: 1, color: AppColors.hairlineSoft),
                ),
              Expanded(child: _KpiCell(cell: cells[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiCell extends StatelessWidget {
  const _KpiCell({required this.cell});
  final ProKpi cell;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              cell.value,
              style: TextStyle(
                fontSize: 20,
                height: 1.3,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: cell.valueColor ?? AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            cell.label,
            maxLines: 2,
            style: const TextStyle(fontSize: 11.5, height: 1.3, color: AppColors.muted),
          ),
          if (cell.progress != null) ...[
            const SizedBox(height: 9),
            ProBar(value: cell.progress!, color: cell.color, height: 3),
          ],
        ],
      ),
    );
    if (cell.onTap == null) return body;
    return InkWell(
      onTap: cell.onTap,
      borderRadius: BorderRadius.circular(18),
      child: body,
    );
  }
}

/// Thin animated progress bar.
class ProBar extends StatelessWidget {
  const ProBar({super.key, required this.value, this.color, this.height = 4, this.track});
  final double value;
  final Color? color;
  final Color? track;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: track ?? AppColors.hairlineSoft,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutBack,
          builder: (_, v, __) => FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color ?? AppColors.primary,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 50px search field. `raised` adds the floating shadow used when it is passed
/// as `ProHero(overlap: ...)`.
class ProSearchField extends StatelessWidget {
  const ProSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search',
    this.raised = false,
    this.onClear,
    this.trailing,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool raised;
  final VoidCallback? onClear;
  final Widget? trailing;
  final bool autofocus;

  /// Called when the keyboard's search key is pressed (server-side search).
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final field = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: raised ? AppShadows.lifted : null,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, __) => TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: v.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                      onClear?.call();
                    },
                  )
                : trailing,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: raised ? AppColors.hairline : const Color(0xFFDBE3E5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: raised ? AppColors.hairline : const Color(0xFFDBE3E5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
        ),
      ),
    );
    return field;
  }
}

/// Section title (16px) with an optional action on the right.
class ProSectionHeader extends StatelessWidget {
  const ProSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.small = false,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  /// Small grey label style (sits right above a [ProListGroup]).
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: small
                      ? const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        )
                      : AppText.section,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: AppText.caption),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// White grouped list card with hairline dividers between rows.
class ProListGroup extends StatelessWidget {
  const ProListGroup({super.key, required this.children, this.dividerIndent = 60});
  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: dividerIndent,
                color: AppColors.hairlineSoft,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Standard list row: leading (icon well / avatar), title, subtitle, trailing
/// value / pill, chevron. Use inside [ProListGroup].
class ProListRow extends StatelessWidget {
  const ProListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.meta,
    this.leading,
    this.trailing,
    this.value,
    this.valueColor,
    this.pill,
    this.onTap,
    this.chevron = true,
    this.dense = false,
    this.titleMaxLines = 1,
  });

  final String title;
  final String? subtitle;

  /// Third line (e.g. times) in a stronger grey.
  final String? meta;
  final Widget? leading;
  final Widget? trailing;

  /// Right-aligned value (amounts, counts).
  final String? value;
  final Color? valueColor;

  /// Status pill under the value (or alone on the right).
  final Widget? pill;
  final VoidCallback? onTap;
  final bool chevron;
  final bool dense;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, dense ? 9 : 11, 12, dense ? 9 : 11),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.33,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.muted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (meta != null)
                      Text(
                        meta!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkSoft,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null || pill != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (value != null)
                      Text(
                        value!,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: valueColor ?? AppColors.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (value != null && pill != null) const SizedBox(height: 4),
                    if (pill != null) pill!,
                  ],
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (chevron && onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Color(0xFFB3C0C3)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 34px tinted icon square.
class ProIconWell extends StatelessWidget {
  const ProIconWell({
    super.key,
    required this.icon,
    this.color,
    this.background,
    this.size = 34,
  });
  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.inkSoft;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? (color == null ? AppColors.neutralTint : c.withOpacity(0.11)),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.53, color: c),
    );
  }
}

/// Squircle initials avatar with an optional status dot.
class ProAvatar extends StatelessWidget {
  const ProAvatar({
    super.key,
    required this.name,
    this.size = 42,
    this.dot,
    this.color,
    this.dark = false,
  });

  final String name;
  final double size;

  /// Status dot colour (bottom-right).
  final Color? dot;

  /// Base tint; defaults to a colour picked from the name.
  final Color? color;

  /// Deep filled avatar (e.g. "you").
  final bool dark;

  static const _palette = [
    Color(0xFF00748C),
    Color(0xFF4253A8),
    Color(0xFF1D7A3E),
    Color(0xFF6B46A8),
    Color(0xFF9A5B00),
    Color(0xFF2C5FB3),
    Color(0xFF0F766E),
    Color(0xFFB4501F),
  ];

  static String initialsOf(String name) {
    final parts = name
        .replaceAll('.', ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final a = parts.first.characters.first;
    final b = parts.length > 1 ? parts[1].characters.first : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final base = color ??
        _palette[name.isEmpty ? 0 : name.codeUnits.fold<int>(0, (a, c) => a + c) % _palette.length];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: dark ? AppColors.deep : base.withOpacity(0.12),
              borderRadius: BorderRadius.circular(size * 0.31),
            ),
            alignment: Alignment.center,
            child: Text(
              initialsOf(name),
              style: TextStyle(
                fontSize: size * 0.33,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : base,
              ),
            ),
          ),
          if (dot != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: size * 0.29,
                height: size * 0.29,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tinted status pill with explicit colours.
class ProPill extends StatelessWidget {
  const ProPill(this.label, {super.key, required this.color, this.background, this.dot = false});
  final String label;
  final Color color;
  final Color? background;
  final bool dot;

  /// Convenience tones.
  factory ProPill.ok(String l) => ProPill(l, color: AppColors.success, background: AppColors.successTint);
  factory ProPill.warn(String l) => ProPill(l, color: const Color(0xFF9A5B00), background: AppColors.warningTint);
  factory ProPill.bad(String l) => ProPill(l, color: AppColors.danger, background: AppColors.dangerTint);
  factory ProPill.info(String l) => ProPill(l, color: AppColors.info, background: AppColors.infoTint);
  factory ProPill.neutral(String l) => ProPill(l, color: const Color(0xFF43585D), background: AppColors.neutralTint);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: background ?? color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
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
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipe a row to approve (→) or reject (←). The row snaps back and the
/// callback runs; keep the visible buttons too for accessibility.
class ProSwipeDecision extends StatelessWidget {
  const ProSwipeDecision({
    super.key,
    required this.child,
    this.onApprove,
    this.onReject,
    this.approveLabel = 'Approve',
    this.rejectLabel = 'Reject',
    this.approveIcon = Icons.check_rounded,
    this.rejectIcon = Icons.close_rounded,
    this.approveColor,
    this.rejectColor,
  });

  final Widget child;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;
  final String approveLabel;
  final String rejectLabel;
  final IconData approveIcon;
  final IconData rejectIcon;
  final Color? approveColor;
  final Color? rejectColor;

  @override
  Widget build(BuildContext context) {
    if (onApprove == null && onReject == null) return child;
    DismissDirection dir;
    if (onApprove != null && onReject != null) {
      dir = DismissDirection.horizontal;
    } else if (onApprove != null) {
      dir = DismissDirection.startToEnd;
    } else {
      dir = DismissDirection.endToStart;
    }
    return Dismissible(
      key: ObjectKey(child),
      direction: dir,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.32,
        DismissDirection.endToStart: 0.32,
      },
      confirmDismiss: (d) async {
        HapticFeedback.mediumImpact();
        if (d == DismissDirection.startToEnd) {
          await onApprove?.call();
        } else {
          await onReject?.call();
        }
        return false;
      },
      background: _SwipeBg(
        color: approveColor ?? AppColors.success,
        icon: approveIcon,
        label: approveLabel,
        alignStart: true,
      ),
      secondaryBackground: _SwipeBg(
        color: rejectColor ?? AppColors.danger,
        icon: rejectIcon,
        label: rejectLabel,
        alignStart: false,
      ),
      child: child,
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignStart,
  });
  final Color color;
  final IconData icon;
  final String label;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small grey swipe hint ("‹ Swipe to approve or reject").
class ProSwipeHint extends StatelessWidget {
  const ProSwipeHint({super.key, this.text = 'Swipe right to approve, left to reject'});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          const Icon(Icons.swipe_rounded, size: 15, color: AppColors.faint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: AppColors.faint)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Forms
// ─────────────────────────────────────────────────────────────────────────────

/// Light header for forms and wizards: back, title, step / subtitle.
class ProFormHeader extends StatelessWidget {
  const ProFormHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProBackButton(onTap: onBack ?? () => Navigator.of(context).maybePop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.45,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null) Text(subtitle!, style: AppText.caption),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// Light 42px back button (hairline square).
class ProBackButton extends StatelessWidget {
  const ProBackButton({super.key, required this.onTap, this.icon = Icons.chevron_left_rounded});
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: Material(
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
            child: Icon(icon, size: 24, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Segmented step progress (wizards).
class ProStepBar extends StatelessWidget {
  const ProStepBar({super.key, required this.total, required this.current});

  /// Number of steps.
  final int total;

  /// Zero-based current step (steps ≤ current are filled).
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: i <= current ? AppColors.primary : const Color(0xFFDFE7E9),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Sticky bottom action bar (use as `Scaffold.bottomNavigationBar` or at the
/// bottom of a Column). Children are laid out side by side.
class ProBottomBar extends StatelessWidget {
  const ProBottomBar({super.key, required this.children, this.top});
  final List<Widget> children;

  /// Optional line above the buttons (totals, hints).
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0F4F6F6),
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (top != null) ...[top!, const SizedBox(height: 10)],
              Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: children[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled form field wrapper: label above, optional helper / error below.
class ProField extends StatelessWidget {
  const ProField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.error,
    this.required = false,
  });
  final String label;
  final Widget child;
  final String? helper;
  final String? error;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: label),
            if (required)
              const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
          ]),
          style: AppText.label,
        ),
        const SizedBox(height: 6),
        child,
        if (error != null || helper != null) ...[
          const SizedBox(height: 5),
          Text(
            error ?? helper!,
            style: TextStyle(
              fontSize: 12.5,
              color: error != null ? AppColors.danger : AppColors.muted,
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Misc
// ─────────────────────────────────────────────────────────────────────────────

enum ProNoteTone { neutral, info, warn, bad, ok }

/// Inline banner for hints and warnings.
class ProNote extends StatelessWidget {
  const ProNote(this.text, {super.key, this.tone = ProNoteTone.neutral, this.icon});
  final String text;
  final ProNoteTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    IconData ic;
    switch (tone) {
      case ProNoteTone.info:
        bg = const Color(0xFFE8F2F4);
        fg = const Color(0xFF00627A);
        ic = Icons.info_outline_rounded;
        break;
      case ProNoteTone.warn:
        bg = const Color(0xFFFFF6E6);
        fg = const Color(0xFF8A5200);
        ic = Icons.warning_amber_rounded;
        break;
      case ProNoteTone.bad:
        bg = AppColors.dangerTint;
        fg = AppColors.danger;
        ic = Icons.error_outline_rounded;
        break;
      case ProNoteTone.ok:
        bg = AppColors.successTint;
        fg = AppColors.success;
        ic = Icons.check_circle_outline_rounded;
        break;
      case ProNoteTone.neutral:
        bg = AppColors.neutralTint;
        fg = const Color(0xFF43585D);
        ic = Icons.info_outline_rounded;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? ic, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Dashed empty state.
class ProEmpty extends StatelessWidget {
  const ProEmpty({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            ProIconWell(icon: icon, color: AppColors.primary, size: 46),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(message!, textAlign: TextAlign.center, style: AppText.caption),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = const Color(0xFFC6D3D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Key / value rows inside a card.
class ProKeyValue extends StatelessWidget {
  const ProKeyValue({super.key, required this.rows});
  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : const Border(top: BorderSide(color: AppColors.hairlineSoft)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rows[i].key,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rows[i].value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Progress row: icon, label, value and a thin bar (e.g. "October so far").
class ProProgressRow extends StatelessWidget {
  const ProProgressRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
    this.color,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final double progress;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            ProIconWell(icon: icon, color: c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w500)),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ProBar(value: progress, color: c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal filter chips (ink when selected) with optional counts.
class ProChipBar extends StatelessWidget {
  const ProChipBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.counts,
    this.bleed = 16,
  });
  final List<String> labels;
  final List<int>? counts;
  final int selected;
  final ValueChanged<int> onSelected;
  final double bleed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: bleed),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = i == selected;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelected(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on ? AppColors.ink : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? AppColors.ink : const Color(0xFFDBE3E5)),
                boxShadow: on
                    ? const [
                        BoxShadow(
                          color: Color(0x660B1D21),
                          blurRadius: 14,
                          spreadRadius: -8,
                          offset: Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Row(
                children: [
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                  if (counts != null && i < counts!.length) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: on ? Colors.white.withOpacity(0.16) : AppColors.neutralTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${counts![i]}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: on ? Colors.white : const Color(0xFF43585D),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Slide-to-confirm control (check in / check out / pay) on a deep surface.
class ProSlideToConfirm extends StatefulWidget {
  const ProSlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.keyboard_double_arrow_right_rounded,
    this.enabled = true,
    this.busy = false,
  });
  final String label;
  final Future<void> Function() onConfirmed;
  final IconData icon;
  final bool enabled;
  final bool busy;

  @override
  State<ProSlideToConfirm> createState() => _ProSlideToConfirmState();
}

class _ProSlideToConfirmState extends State<ProSlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  bool _done = false;
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _back.addListener(() {
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
      const h = 60.0;
      const knob = 52.0;
      final max = c.maxWidth - knob - 8;
      final p = max <= 0 ? 0.0 : (_drag / max).clamp(0.0, 1.0);
      return Semantics(
        button: true,
        label: widget.label,
        onTap: widget.enabled && !widget.busy ? () => widget.onConfirmed() : null,
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: knob + 8 + _drag,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(colors: [
                      AppColors.live.withOpacity(0),
                      AppColors.live.withOpacity(0.42),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 4 + _drag,
                top: 3,
                child: GestureDetector(
                  onHorizontalDragUpdate: !widget.enabled || widget.busy || _done
                      ? null
                      : (d) => setState(() => _drag = (_drag + d.delta.dx).clamp(0.0, max)),
                  onHorizontalDragEnd: !widget.enabled || widget.busy || _done
                      ? null
                      : (_) async {
                          if (_drag >= max * 0.92) {
                            HapticFeedback.heavyImpact();
                            setState(() {
                              _drag = max;
                              _done = true;
                            });
                            await widget.onConfirmed();
                            if (mounted) {
                              setState(() {
                                _done = false;
                                _drag = 0;
                              });
                            }
                          } else {
                            _from = _drag;
                            _back.forward(from: 0);
                          }
                        },
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      color: _done ? AppColors.live : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8C000000),
                          blurRadius: 16,
                          spreadRadius: -6,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: widget.busy
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Icon(widget.icon, color: AppColors.deep, size: 24),
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

// ─────────────────────────────────────────────────────────────────────────────
// App bars
// ─────────────────────────────────────────────────────────────────────────────

/// Deep app bar that flows straight into a [ProHero] below it (the theme
/// default; use this when you need a subtitle or custom actions).
PreferredSizeWidget proDarkAppBar(
  BuildContext context, {
  String? title,
  String? subtitle,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    backgroundColor: AppColors.deep,
    foregroundColor: Colors.white,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    titleSpacing: 4,
    title: title == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
    actions: actions,
    bottom: bottom,
  );
}

/// Light app bar for forms and wizards (canvas background, ink text).
PreferredSizeWidget proLightAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    backgroundColor: AppColors.bg,
    foregroundColor: AppColors.ink,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    automaticallyImplyLeading: false,
    leadingWidth: canPop ? 62 : 0,
    leading: canPop
        ? Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(child: ProBackButton(onTap: () => Navigator.of(context).maybePop())),
          )
        : null,
    titleSpacing: canPop ? 4 : 16,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: AppColors.ink)),
        if (subtitle != null)
          Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
      ],
    ),
    actions: actions,
    bottom: bottom,
  );
}
