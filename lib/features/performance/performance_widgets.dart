// ─────────────────────────────────────────────────────────────────────────────
//  FO Scorecard Performance — reusable presentation widgets.
//
//  Card-first, no wide tables. All percentage inputs are RATIOS (1.0 == 100%).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

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
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.10)],
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 10),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.1,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 1),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Metric card with progress bar + colored % badge ──────────────────────────

/// A collection-metric row: label, a tinted % badge, an optional subtitle and a
/// linear progress bar whose fill is toned to the ratio.
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
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.muted),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: tone.withValues(alpha: 0.30)),
                ),
                child: Text(
                  perfPct(ratio),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(
              sub!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 7,
              backgroundColor: AppColors.hairline,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
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
            child: CircularProgressIndicator(
              value: clamped,
              strokeWidth: 8,
              backgroundColor: AppColors.hairline,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                perfPct(ratio),
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w800,
                  color: tone,
                  height: 1.0,
                ),
              ),
              if (label != null) ...[
                const SizedBox(height: 2),
                Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Rank badge ───────────────────────────────────────────────────────────────

/// A rank pill (e.g. "NLPL #4"). Grade renders as a coloured chip.
class PerfRankBadge extends StatelessWidget {
  const PerfRankBadge({
    super.key,
    required this.label,
    required this.rank,
    this.icon = Icons.emoji_events_rounded,
    this.color = AppColors.primary,
  });

  final String label;
  final int? rank;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rank == null ? '—' : '#${rank!}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.0,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky month selector ────────────────────────────────────────────────────

/// A dropdown that picks one of the available scorecard periods. Renders as a
/// pill-styled selector intended to sit at the top of the screen.
class PerfMonthSelector extends StatelessWidget {
  const PerfMonthSelector({
    super.key,
    required this.periods,
    required this.selected,
    required this.onChanged,
    this.lastSyncedLabel,
  });

  final List<PeriodOption> periods;
  final PeriodOption? selected;
  final ValueChanged<PeriodOption> onChanged;
  final String? lastSyncedLabel;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shadow: AppShadows.card,
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: periods.isEmpty
                ? Text(
                    selected?.label ?? 'No periods available',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<PeriodOption>(
                      isExpanded: true,
                      isDense: true,
                      value: periods.contains(selected) ? selected : null,
                      hint: const Text(
                        'Select period',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.muted),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
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
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
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
    final arrow = (delta == null || delta == 0)
        ? Icons.remove_rounded
        : ((delta! > 0)
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '$valueA → $valueB',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(arrow, size: 11, color: tone),
                const SizedBox(width: 2),
                Text(
                  deltaText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: tone,
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

// ── Section card (local copy mirroring the team-detail look) ─────────────────

/// A titled white card with an icon and divider, matching the employee-detail
/// section style.
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
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 12),
          ...children,
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
    return StatusPill(
      label: 'Grade $grade',
      color: AppColors.primary,
      icon: Icons.workspace_premium_rounded,
    );
  }
}

String perfIntOrDash(int? v) => _intOrDash(v);
