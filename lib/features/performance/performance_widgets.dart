// ─────────────────────────────────────────────────────────────────────────────
//  FO Scorecard Performance — reusable presentation widgets.
//
//  Card-first, no wide tables. All percentage inputs are RATIOS (1.0 == 100%).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'performance_models.dart';

// ── Formatting / tone helpers ────────────────────────────────────────────────

/// Ratio (1.0 == 100%) → "73.0%". Null → "—".
String perfPct(double? ratio) =>
    ratio == null ? '—' : '${(ratio * 100).toStringAsFixed(1)}%';

/// Status color for a ratio: >=0.9 success, >=0.6 warning, else danger.
Color perfTone(double? ratio) {
  if (ratio == null) return AppColors.muted;
  if (ratio >= 0.9) return AppColors.success;
  if (ratio >= 0.6) return AppColors.warning;
  return AppColors.danger;
}

/// The same banding as [perfTone], in the brighter tints that read on the
/// deep hero surface.
Color perfToneOnDark(double? ratio) {
  if (ratio == null) return Colors.white54;
  if (ratio >= 0.9) return AppColors.live;
  if (ratio >= 0.6) return const Color(0xFFF2B347);
  return const Color(0xFFE5484D);
}

/// Tinted % pill toned to the ratio.
ProPill perfPctPill(double? ratio) {
  final tone = perfTone(ratio);
  if (tone == AppColors.success) return ProPill.ok(perfPct(ratio));
  if (tone == AppColors.warning) return ProPill.warn(perfPct(ratio));
  if (tone == AppColors.danger) return ProPill.bad(perfPct(ratio));
  return ProPill.neutral(perfPct(ratio));
}

String _intOrDash(int? v) => v == null ? '—' : '$v';

// ── Compact KPI card ─────────────────────────────────────────────────────────

/// Small headline KPI tile (label + value + tinted icon).
class PerfKpiCard extends StatelessWidget {
  const PerfKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProIconWell(icon: icon, color: color, size: 32),
          const SizedBox(height: 10),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.15,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (sub != null) ...[
            const SizedBox(height: 1),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Metric card with progress bar + colored % badge ──────────────────────────

/// A collection-metric row: label, a tinted % badge, an optional subtitle and a
/// progress bar whose fill is toned to the ratio.
class PerfMetricCard extends StatelessWidget {
  const PerfMetricCard({
    super.key,
    required this.label,
    required this.ratio,
    this.sub,
    this.icon,
  });

  final String label;
  final double? ratio;
  final String? sub;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = perfTone(ratio);
    final clamped = (ratio ?? 0).clamp(0.0, 1.0).toDouble();
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                ProIconWell(icon: icon!, color: tone),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              perfPctPill(ratio),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!, style: AppText.caption),
          ],
          const SizedBox(height: 10),
          ProBar(value: clamped, color: tone, height: 6),
        ],
      ),
    );
  }
}

// ── Ring progress (overall score) ────────────────────────────────────────────

/// A circular progress ring with the centred % value, toned to the ratio.
class PerfRingProgress extends StatelessWidget {
  const PerfRingProgress({
    super.key,
    required this.ratio,
    this.size = 92,
    this.label,
  });

  final double? ratio;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tone = perfTone(ratio);
    final clamped = (ratio ?? 0).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: v,
                strokeWidth: size >= 80 ? 7 : 6,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.hairlineSoft,
                valueColor: AlwaysStoppedAnimation(tone),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    perfPct(ratio),
                    style: TextStyle(
                      fontSize: size * 0.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: AppColors.ink,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    label!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rank badge ───────────────────────────────────────────────────────────────

/// A rank tile (e.g. "NLPL rank #4").
class PerfRankBadge extends StatelessWidget {
  const PerfRankBadge({
    super.key,
    required this.label,
    required this.rank,
    this.icon = Icons.emoji_events_rounded,
    this.color,
  });

  final String label;
  final int? rank;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ProIconWell(icon: icon, color: c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                const SizedBox(height: 1),
                Text(
                  rank == null ? '—' : '#${rank!}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.15,
                    letterSpacing: -0.4,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Month selector ───────────────────────────────────────────────────────────

/// A dropdown that picks one of the available scorecard periods. Pass
/// [raised] when it straddles a hero (`ProHero(overlap: ...)`).
class PerfMonthSelector extends StatelessWidget {
  const PerfMonthSelector({
    super.key,
    required this.periods,
    required this.selected,
    required this.onChanged,
    this.lastSyncedLabel,
    this.raised = false,
  });

  final List<PeriodOption> periods;
  final PeriodOption? selected;
  final ValueChanged<PeriodOption> onChanged;
  final String? lastSyncedLabel;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    const valueStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: AppColors.ink,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.hairline),
        boxShadow: raised ? AppShadows.lifted : AppShadows.card,
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: periods.isEmpty
                ? Text(
                    selected?.label ?? 'No periods available',
                    style: valueStyle,
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<PeriodOption>(
                      isExpanded: true,
                      isDense: true,
                      borderRadius: BorderRadius.circular(14),
                      value: periods.contains(selected) ? selected : null,
                      hint: const Text('Select period', style: valueStyle),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.muted),
                      style: valueStyle,
                      items: [
                        for (final p in periods)
                          DropdownMenuItem<PeriodOption>(
                            value: p,
                            child: Text(p.label),
                          ),
                      ],
                      onChanged: (p) {
                        if (p != null) onChanged(p);
                      },
                    ),
                  ),
          ),
          if (lastSyncedLabel != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                lastSyncedLabel!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Compare card ─────────────────────────────────────────────────────────────

/// A small comparison row: a metric, its A and B values, and a tinted delta with
/// an up/down arrow. [higherIsBetter] flips the tone (rank deltas improve when
/// negative).
class PerfCompareRow extends StatelessWidget {
  const PerfCompareRow({
    super.key,
    required this.label,
    required this.valueA,
    required this.valueB,
    required this.delta,
    required this.deltaText,
    this.higherIsBetter = true,
  });

  final String label;
  final String valueA;
  final String valueB;
  final num? delta;
  final String deltaText;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final improved = delta == null || delta == 0
        ? null
        : (higherIsBetter ? delta! > 0 : delta! < 0);
    final tone = improved == null
        ? AppColors.muted
        : (improved ? AppColors.success : AppColors.danger);
    final tint = improved == null
        ? AppColors.neutralTint
        : (improved ? AppColors.successTint : AppColors.dangerTint);
    final arrow = (delta == null || delta == 0)
        ? Icons.remove_rounded
        : ((delta! > 0)
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '$valueA → $valueB',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(arrow, size: 12, color: tone),
                const SizedBox(width: 2),
                Text(
                  deltaText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: tone,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ─────────────────────────────────────────────────────────────

/// A titled white card, matching the employee-detail section style. Hairline
/// dividers separate consecutive [PerfCompareRow]s.
class PerfSectionCard extends StatelessWidget {
  const PerfSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(title: title, trailing: trailing),
          const SizedBox(height: 8),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 &&
                children[i] is PerfCompareRow &&
                children[i - 1] is PerfCompareRow)
              const Divider(
                  height: 1, thickness: 1, color: AppColors.hairlineSoft),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A 2-per-row grid of equal-height tiles (mirrors `_statGrid`).
Widget perfGrid(List<Widget> tiles) {
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += 2) {
    final a = tiles[i];
    final b = (i + 1 < tiles.length) ? tiles[i + 1] : null;
    rows.add(Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b ?? const SizedBox.shrink()),
          ],
        ),
      ),
    ));
  }
  return Column(children: rows);
}

/// A coloured grade chip (e.g. branch grade "A").
class PerfGradeChip extends StatelessWidget {
  const PerfGradeChip({super.key, required this.grade});
  final String grade;

  @override
  Widget build(BuildContext context) {
    return ProPill('Grade $grade', color: AppColors.primary);
  }
}

String perfIntOrDash(int? v) => _intOrDash(v);
