// ─────────────────────────────────────────────────────────────────────────────
//  FO Scorecard Performance — shared scorecard body.
//
//  Renders the card-first scorecard layout for a single FO's [PerformanceDetail]:
//  summary header, rank cards, target-vs-achievement, collection metrics and an
//  optional month-over-month comparison. Reused by both My Performance and the
//  employee-detail Performance tab so the two stay visually identical.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'performance_models.dart';
import 'performance_repository.dart';
import 'performance_widgets.dart';

class PerformanceScorecardBody extends ConsumerWidget {
  const PerformanceScorecardBody({
    super.key,
    required this.detail,
    this.selectedPeriod,
  });

  final PerformanceDetail detail;

  /// The currently-selected period (drives the month-over-month comparison).
  final PeriodOption? selectedPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = detail.summary;
    if (s == null) {
      return const AppEmptyState(
        icon: Icons.insights_rounded,
        message:
            'No scorecard data for this period yet. Try another month once data has synced.',
      );
    }

    final name = s.employeeName ?? detail.employeeName ?? '—';
    final code = s.employeeCode ?? detail.employeeCode;

    return Column(
      children: [
        // ── Summary header ──
        GlassCard(
          shadow: AppShadows.card,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PerfRingProgress(
                ratio: s.overallPercentage,
                size: 84,
                label: 'OVERALL',
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (s.hierarchyLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        s.hierarchyLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if ((code ?? '').isNotEmpty)
                          StatusPill(
                            label: code!,
                            color: AppColors.primary,
                            icon: Icons.badge_rounded,
                          ),
                        if ((s.monthLabel ?? '').isNotEmpty)
                          StatusPill(
                            label: s.monthLabel!,
                            color: AppColors.info,
                            icon: Icons.calendar_month_rounded,
                          ),
                        if ((s.branchGrade ?? '').isNotEmpty)
                          PerfGradeChip(grade: s.branchGrade!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Rank cards ──
        perfGrid([
          PerfRankBadge(
            label: 'NLPL Rank',
            rank: s.nlplRank,
            icon: Icons.emoji_events_rounded,
            color: AppColors.warning,
          ),
          PerfRankBadge(
            label: 'Branch Rank',
            rank: s.branchRank,
            icon: Icons.leaderboard_rounded,
            color: AppColors.primary,
          ),
        ]),

        // ── Target vs achievement ──
        PerfSectionCard(
          title: 'Disbursement (DB)',
          icon: Icons.track_changes_rounded,
          trailing: _PctBadge(ratio: s.dbPercentage),
          children: [
            perfGrid([
              PerfKpiCard(
                label: 'Target',
                value: perfIntOrDash(s.dbTarget),
                icon: Icons.flag_rounded,
                color: AppColors.info,
              ),
              PerfKpiCard(
                label: 'Achievement',
                value: perfIntOrDash(s.dbAchievement),
                icon: Icons.check_circle_rounded,
                color: perfTone(s.dbPercentage),
              ),
            ]),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: (s.dbPercentage ?? 0).clamp(0.0, 1.0).toDouble(),
                minHeight: 7,
                backgroundColor: AppColors.hairline,
                valueColor: AlwaysStoppedAnimation(perfTone(s.dbPercentage)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Collection performance ──
        const AppSectionHeader(title: 'Collection performance'),
        const SizedBox(height: 10),
        PerfMetricCard(
          label: 'Regular collection',
          ratio: s.regularCollectionPercentage,
          icon: Icons.payments_rounded,
        ),
        const SizedBox(height: 10),
        PerfMetricCard(
          label: '1–90 collection',
          ratio: s.oneToNinetyPercentage,
          icon: Icons.schedule_rounded,
        ),
        const SizedBox(height: 10),
        PerfMetricCard(
          label: 'On-date collection',
          ratio: s.onDatePercentage,
          icon: Icons.event_available_rounded,
        ),
        const SizedBox(height: 10),
        PerfMetricCard(
          label: 'NPA recovery',
          ratio: s.npaRecoveryPercentage,
          icon: Icons.restore_rounded,
        ),
        const SizedBox(height: 12),

        // ── Month-over-month comparison ──
        _ComparisonCard(detail: detail, selectedPeriod: selectedPeriod),
      ],
    );
  }
}

/// A small tinted % badge used as a section trailing element.
class _PctBadge extends StatelessWidget {
  const _PctBadge({required this.ratio});
  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final tone = perfTone(ratio);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    );
  }
}

/// Picks the period immediately older than [selectedPeriod] from the available
/// list and shows a delta comparison. Hidden when there's no older period.
class _ComparisonCard extends ConsumerWidget {
  const _ComparisonCard({required this.detail, this.selectedPeriod});
  final PerformanceDetail detail;
  final PeriodOption? selectedPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = detail.availablePeriods;
    final current = selectedPeriod ??
        (detail.summary != null &&
                detail.summary!.month != null &&
                detail.summary!.year != null
            ? PeriodOption(
                month: detail.summary!.month!,
                year: detail.summary!.year!,
                label: detail.summary!.monthLabel ?? '',
              )
            : null);
    if (current == null || periods.length < 2) {
      return const SizedBox.shrink();
    }
    final idx = periods.indexOf(current);
    // availablePeriods is newest-first; the "older" period is the next one.
    final olderIdx = idx >= 0 ? idx + 1 : 1;
    if (olderIdx >= periods.length) return const SizedBox.shrink();
    final older = periods[olderIdx];

    final async = ref.watch(comparePerformanceProvider(ComparePerfQuery(
      employeeId: detail.employeeId,
      monthA: older.month,
      yearA: older.year,
      monthB: current.month,
      yearB: current.year,
    )));

    return async.when(
      loading: () => const AppLoadingBlock(height: 120),
      // A comparison is best-effort — don't surface an error panel here.
      error: (_, __) => const SizedBox.shrink(),
      data: (c) {
        final d = c.deltas;
        final a = c.periodA;
        final b = c.periodB;
        if (a == null || b == null) return const SizedBox.shrink();
        return PerfSectionCard(
          title: 'Vs ${older.label}',
          icon: Icons.compare_arrows_rounded,
          children: [
            PerfCompareRow(
              label: 'Overall',
              valueA: perfPct(a.overallPercentage),
              valueB: perfPct(b.overallPercentage),
              delta: d.overallPercentage,
              deltaText: _pctDelta(d.overallPercentage),
            ),
            PerfCompareRow(
              label: 'Regular collection',
              valueA: perfPct(a.regularCollectionPercentage),
              valueB: perfPct(b.regularCollectionPercentage),
              delta: d.regularCollectionPercentage,
              deltaText: _pctDelta(d.regularCollectionPercentage),
            ),
            PerfCompareRow(
              label: '1–90 collection',
              valueA: perfPct(a.oneToNinetyPercentage),
              valueB: perfPct(b.oneToNinetyPercentage),
              delta: d.oneToNinetyPercentage,
              deltaText: _pctDelta(d.oneToNinetyPercentage),
            ),
            PerfCompareRow(
              label: 'On-date collection',
              valueA: perfPct(a.onDatePercentage),
              valueB: perfPct(b.onDatePercentage),
              delta: d.onDatePercentage,
              deltaText: _pctDelta(d.onDatePercentage),
            ),
            PerfCompareRow(
              label: 'NPA recovery',
              valueA: perfPct(a.npaRecoveryPercentage),
              valueB: perfPct(b.npaRecoveryPercentage),
              delta: d.npaRecoveryPercentage,
              deltaText: _pctDelta(d.npaRecoveryPercentage),
            ),
            PerfCompareRow(
              label: 'NLPL rank',
              valueA: perfIntOrDash(a.nlplRank),
              valueB: perfIntOrDash(b.nlplRank),
              delta: d.nlplRank,
              deltaText: _rankDelta(d.nlplRank),
              higherIsBetter: false,
            ),
            PerfCompareRow(
              label: 'Branch rank',
              valueA: perfIntOrDash(a.branchRank),
              valueB: perfIntOrDash(b.branchRank),
              delta: d.branchRank,
              deltaText: _rankDelta(d.branchRank),
              higherIsBetter: false,
            ),
          ],
        );
      },
    );
  }
}

/// Percentage delta (ratio) → "+3.0" / "-1.5" / "—".
String _pctDelta(double? d) {
  if (d == null) return '—';
  final pts = d * 100;
  final sign = pts > 0 ? '+' : '';
  return '$sign${pts.toStringAsFixed(1)}';
}

/// Rank delta → "+2" / "-1" / "—" (negative = moved up).
String _rankDelta(int? d) {
  if (d == null) return '—';
  final sign = d > 0 ? '+' : '';
  return '$sign$d';
}
