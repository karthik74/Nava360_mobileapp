// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — Dashboard (mirrors web AuditDashboardPage).
//
//  Loads every plan + finding the caller may see (same endpoints as the web
//  dashboard), rolls the KPIs up locally (audit_kpis.dart) so the month / org
//  filters slice instantly, and adds the server-side category scores.
//  Charts are plain CustomPaint / Containers — no chart package.
//  The wide performance tables of the web page are omitted on mobile.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/branding.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../requisitions/requisition_models.dart';
import 'audit_detail_screen.dart';
import 'audit_kpis.dart';
import 'audit_models.dart';
import 'audit_repository.dart';
import 'audit_widgets.dart';
import 'findings_list_screen.dart';
import 'finding_detail_screen.dart';
import 'my_audits_screen.dart';

class _DashData {
  final List<AuditPlan> plans;
  final List<AuditFinding> findings;
  final bool truncated;
  final String? plansError;
  final String? findingsError;
  const _DashData({
    required this.plans,
    required this.findings,
    required this.truncated,
    this.plansError,
    this.findingsError,
  });
}

/// Plans + findings sweeps. Each side fails independently (a role may be allowed
/// one list but not the other) — the dashboard only errors out when both fail.
final _dashDataProvider = FutureProvider.autoDispose<_DashData>((ref) async {
  final repo = ref.watch(auditRepositoryProvider);
  var plans = <AuditPlan>[];
  var findings = <AuditFinding>[];
  var truncated = false;
  String? pe, fe;
  await Future.wait([
    repo.sweepPlans().then((r) {
      plans = r.rows;
      truncated = truncated || r.truncated;
    }).catchError((Object e) {
      pe = '$e';
    }),
    repo.sweepFindings().then((r) {
      findings = r.rows;
      truncated = truncated || r.truncated;
    }).catchError((Object e) {
      fe = '$e';
    }),
  ]);
  if (pe != null && fe != null) throw Exception(pe);
  return _DashData(
    plans: plans,
    findings: findings,
    truncated: truncated,
    plansError: pe,
    findingsError: fe,
  );
});

final _categoryScoresProvider = FutureProvider.autoDispose
    .family<List<AuditCategoryScore>, (int?, int?)>(
  (ref, my) => ref
      .watch(auditRepositoryProvider)
      .categoryScores(month: my.$1, year: my.$2),
);

const _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _kBandColor = {
  'critical': Color(0xFFD03B3B),
  'needs_improvement': Color(0xFFEC835A),
  'good': Color(0xFFFAB219),
  'excellent': Color(0xFF0CA30C),
};
const _kSeverityColor = {
  'HIGH': Color(0xFF1B3A5C),
  'MODERATE': Color(0xFFEB8B34),
  'LOW': Color(0xFF7EC8E3),
};
const _kSeverityLabel = {'HIGH': 'High', 'MODERATE': 'Moderate', 'LOW': 'Low'};

/// Dashboard content (no Scaffold — hosted by the audit home tabs).
class AuditDashboardBody extends ConsumerStatefulWidget {
  const AuditDashboardBody({super.key});

  @override
  ConsumerState<AuditDashboardBody> createState() => _AuditDashboardBodyState();
}

class _AuditDashboardBodyState extends ConsumerState<AuditDashboardBody> {
  int? _month = DateTime.now().month;
  int? _year = DateTime.now().year;
  String? _region, _division, _area;
  int? _branchId;
  bool _filtersOpen = false;

  bool get _orgActive =>
      _region != null || _division != null || _area != null || _branchId != null;
  bool get _periodActive => _month != null || _year != null;

  Set<int>? _branchScope(List<BranchOption> all) {
    if (!_orgActive) return null;
    return all
        .where((b) {
          if (_branchId != null && b.id != _branchId) return false;
          if (_region != null && b.regionLabel != _region) return false;
          if (_division != null && b.divisionLabel != _division) return false;
          if (_area != null && b.areaLabel != _area) return false;
          return true;
        })
        .map((b) => b.id)
        .toSet();
  }

  Future<void> _refresh() async {
    ref.invalidate(_dashDataProvider);
    ref.invalidate(_categoryScoresProvider);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void _openPlans({String? status}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MyAuditsScreen(
        initialStatus: status,
        initialBranchId: _branchId,
      ),
    ));
  }

  void _openFindings({String? status, String? severity, bool? overdue}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FindingsListScreen(
        initialStatus: status,
        initialSeverity: severity,
        initialOverdue: overdue,
        initialBranchId: _branchId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_dashDataProvider);
    final branches =
        ref.watch(auditBranchesProvider).asData?.value ?? const <BranchOption>[];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _filterCard(branches),
          const SizedBox(height: 14),
          data.when(
            loading: () => const AppLoadingBlock(height: 320),
            error: (e, __) => AppErrorPanel(
              message: 'Could not load the audit dashboard.\n$e',
              onRetry: () => ref.invalidate(_dashDataProvider),
            ),
            data: (d) => _content(d, branches),
          ),
        ],
      ),
    );
  }

  Widget _content(_DashData d, List<BranchOption> branches) {
    final scope = _branchScope(branches);
    final periodPlans =
        d.plans.where((p) => isPlanInPeriod(p, _month, _year)).toList();
    final plans = scope == null
        ? periodPlans
        : periodPlans
            .where((p) => p.branchId != null && scope.contains(p.branchId))
            .toList();
    final planIds = plans.map((p) => p.id).toSet();
    final findings = d.findings
        .where((f) => f.planId != null && planIds.contains(f.planId))
        .toList();

    final k = computeAuditKpis(plans, findings);
    final funnel = computeFunnel(plans);
    final side = computeFunnelSide(plans);
    final dist = computeScoreDistribution(plans);
    final trend = computeTrend(plans);
    final recent = computeRecentActivity(plans);
    final attention = computeAttentionGroups(plans, findings);

    String? pct(int n, int total) =>
        total > 0 ? '${(n / total * 100).toStringAsFixed(1)}% of total' : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.truncated)
          _note('Only the most recent ${d.plans.length} audits and '
              '${d.findings.length} findings were loaded — totals may be incomplete.'),
        if (d.plansError != null)
          _note('Audits could not be loaded: ${d.plansError}'),
        if (d.findingsError != null)
          _note('Findings could not be loaded: ${d.findingsError}'),
        const AppSectionHeader(title: 'Audit Progress'),
        const SizedBox(height: 8),
        _kpiGrid([
          _Kpi('Total Audits', '${k.totalAudits}', Icons.assignment_rounded,
              AppColors.primary, null, () => _openPlans()),
          _Kpi('Planned', '${k.plannedAudits}', Icons.event_available_rounded,
              AppColors.info, pct(k.plannedAudits, k.totalAudits),
              () => _openPlans(status: 'PLANNED')),
          _Kpi('In Progress', '${k.inProgressAudits}',
              Icons.pending_actions_rounded, AppColors.warning,
              pct(k.inProgressAudits, k.totalAudits),
              () => _openPlans(status: 'IN_PROGRESS')),
          _Kpi('Submitted', '${k.submittedAudits}', Icons.send_rounded,
              AppColors.pink, pct(k.submittedAudits, k.totalAudits),
              () => _openPlans(status: 'SUBMITTED')),
          _Kpi('Completed', '${k.completedAudits}',
              Icons.check_circle_rounded, AppColors.success,
              pct(k.completedAudits, k.totalAudits),
              () => _openPlans(status: 'CLOSED')),
          _Kpi('Overdue', '${k.overdueAudits}', Icons.warning_amber_rounded,
              AppColors.danger, pct(k.overdueAudits, k.totalAudits), null),
        ]),
        const SizedBox(height: 16),
        const AppSectionHeader(title: 'Findings & Compliance'),
        const SizedBox(height: 8),
        _kpiGrid([
          _Kpi('Total Findings', '${k.totalFindings}',
              Icons.report_problem_rounded, AppColors.primary, null,
              () => _openFindings()),
          _Kpi('Open', '${k.openFindings}', Icons.report_problem_rounded,
              const Color(0xFFEA580C), pct(k.openFindings, k.totalFindings),
              () => _openFindings(status: 'OPEN')),
          _Kpi('Critical', '${k.criticalFindings}',
              Icons.local_fire_department_rounded, AppColors.danger,
              pct(k.criticalFindings, k.totalFindings),
              () => _openFindings(severity: 'HIGH', status: 'OPEN')),
          _Kpi('Overdue', '${k.overdueFindings}', Icons.warning_amber_rounded,
              AppColors.danger, pct(k.overdueFindings, k.totalFindings),
              () => _openFindings(overdue: true)),
          _Kpi(
              'Avg Score',
              k.averageScore == null
                  ? '—'
                  : '${k.averageScore!.toStringAsFixed(1)}%',
              Icons.speed_rounded,
              AppColors.primary,
              null,
              null),
        ]),
        const SizedBox(height: 16),
        _attentionCard(attention),
        const SizedBox(height: 14),
        _categoryCard(),
        const SizedBox(height: 14),
        _pipelineCard(funnel, side),
        const SizedBox(height: 14),
        _scoreCard(dist),
        const SizedBox(height: 14),
        _severityCard(k),
        const SizedBox(height: 14),
        _trendCard(trend),
        const SizedBox(height: 14),
        _recentCard(recent),
      ],
    );
  }

  // ── Filters ────────────────────────────────────────────────────────────────

  Widget _filterCard(List<BranchOption> all) {
    List<String> distinct(Iterable<String?> v) =>
        v.where((s) => s != null && s.trim().isNotEmpty).cast<String>().toSet().toList()
          ..sort();
    final regions = distinct(all.map((b) => b.regionLabel));
    final divisions = distinct(all
        .where((b) => _region == null || b.regionLabel == _region)
        .map((b) => b.divisionLabel));
    final areas = distinct(all
        .where((b) =>
            (_region == null || b.regionLabel == _region) &&
            (_division == null || b.divisionLabel == _division))
        .map((b) => b.areaLabel));
    final inScope = all.where((b) {
      if (_region != null && b.regionLabel != _region) return false;
      if (_division != null && b.divisionLabel != _division) return false;
      if (_area != null && b.areaLabel != _area) return false;
      return true;
    }).toList();

    final tRegion = Branding.current.term('region');
    final tDivision = Branding.current.term('division');
    final tArea = Branding.current.term('area');
    final tBranch = Branding.current.term('branch');
    final year = DateTime.now().year;

    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: _dd<int>(
                hint: 'All months',
                value: _month,
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('All months')),
                  for (var i = 0; i < 12; i++)
                    DropdownMenuItem<int>(value: i + 1, child: Text(_kMonths[i])),
                ],
                onChanged: (v) => setState(() => _month = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dd<int>(
                hint: 'All years',
                value: _year,
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('All years')),
                  for (var y = year; y >= year - 5; y--)
                    DropdownMenuItem<int>(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() => _year = v),
              ),
            ),
          ]),
          if (all.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _filtersOpen = !_filtersOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.tune_rounded, size: 16, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Text('Filter by $tBranch',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                  const Spacer(),
                  Icon(
                      _filtersOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: AppColors.muted),
                ]),
              ),
            ),
            if (_filtersOpen) ...[
              _dd<String>(
                hint: 'All ${_pl(tRegion)}',
                value: _region,
                items: _strItems(regions, 'All ${_pl(tRegion)}'),
                onChanged: (v) => setState(() {
                  _region = v;
                  _division = null;
                  _area = null;
                  _branchId = null;
                }),
              ),
              const SizedBox(height: 8),
              _dd<String>(
                hint: 'All ${_pl(tDivision)}',
                value: _division,
                items: _strItems(divisions, 'All ${_pl(tDivision)}'),
                onChanged: (v) => setState(() {
                  _division = v;
                  _area = null;
                  _branchId = null;
                }),
              ),
              const SizedBox(height: 8),
              _dd<String>(
                hint: 'All ${_pl(tArea)}',
                value: _area,
                items: _strItems(areas, 'All ${_pl(tArea)}'),
                onChanged: (v) => setState(() {
                  _area = v;
                  _branchId = null;
                }),
              ),
              const SizedBox(height: 8),
              _dd<int>(
                hint: 'All ${_pl(tBranch)}',
                value: _branchId,
                items: [
                  DropdownMenuItem<int>(
                      value: null, child: Text('All ${_pl(tBranch)}')),
                  for (final b in inScope)
                    DropdownMenuItem<int>(
                        value: b.id,
                        child: Text(b.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _branchId = v),
              ),
            ],
          ],
          if (_orgActive || _periodActive) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(_scopeText(),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _month = null;
                  _year = null;
                  _region = _division = _area = null;
                  _branchId = null;
                }),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('Clear filters', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  String _scopeText() {
    final parts = <String>[
      if (_region != null) _region!,
      if (_division != null) _division!,
      if (_area != null) _area!,
    ];
    final period = _month != null
        ? '${_kMonths[_month! - 1]} ${_year ?? DateTime.now().year}'
        : (_year != null ? '$_year' : null);
    return [
      if (parts.isNotEmpty) parts.join(' → '),
      if (_branchId != null) 'selected ${Branding.current.term('branch').toLowerCase()}',
      if (period != null) period,
    ].join(' · ');
  }

  static String _pl(String t) => t.endsWith('s') ? t : '${t}s';

  static List<DropdownMenuItem<String>> _strItems(
          List<String> o, String allLabel) =>
      [
        DropdownMenuItem<String>(value: null, child: Text(allLabel)),
        for (final s in o)
          DropdownMenuItem<String>(
              value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
      ];

  Widget _dd<T>({
    required String hint,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          icon: const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.muted),
          hint: Text(hint,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted)),
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
          ),
          child: Text(text,
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
        ),
      );

  // ── KPI cards ──────────────────────────────────────────────────────────────

  Widget _kpiGrid(List<_Kpi> items) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final i in items) SizedBox(width: w, child: _KpiCard(kpi: i)),
        ],
      );
    });
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _attentionCard(List<AttentionGroup> groups) {
    return AuditSectionCard(
      title: 'Attention Required',
      icon: Icons.notification_important_rounded,
      children: [
        if (groups.isEmpty)
          const _EmptyLine('Nothing needs attention right now.')
        else
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text('${g.label} (${g.count})',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ),
            for (final it in g.items)
              InkWell(
                onTap: () {
                  if (it.planId != null) {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AuditDetailScreen(planId: it.planId!)));
                  } else if (it.findingId != null) {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            FindingDetailScreen(findingId: it.findingId!)));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${it.code}  ${it.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                          Text(
                              [
                                if ((it.branchName ?? '').isNotEmpty) it.branchName!,
                                it.detail
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(
                      label: it.statusLabel,
                      color: it.high ? AppColors.danger : AppColors.warning,
                    ),
                  ]),
                ),
              ),
          ],
      ],
    );
  }

  Widget _categoryCard() {
    final async = ref.watch(_categoryScoresProvider((_month, _year)));
    return AuditSectionCard(
      title: 'Branch Administration Observations',
      icon: Icons.bar_chart_rounded,
      children: [
        const Text('Average score per category.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
        const SizedBox(height: 8),
        async.when(
          loading: () => const AppLoadingBlock(height: 100),
          // Not every dashboard role may read this endpoint — degrade quietly.
          error: (e, __) => const _EmptyLine('Category scores are not available.'),
          data: (rows) {
            if (rows.isEmpty) {
              return const _EmptyLine(
                  'No categories found under Branch Administration Observations.');
            }
            if (rows.every((r) => r.averagePercentage == null)) {
              return const _EmptyLine(
                  'No question-level responses recorded yet for these categories.');
            }
            return Column(children: [
              for (final r in rows)
                _HBar(
                  label: r.sectionName,
                  fraction: (r.averagePercentage ?? 0) / 100,
                  color: const Color(0xFF2A78D6),
                  trailing: r.averagePercentage == null
                      ? 'Not scored'
                      : '${r.averagePercentage!.toStringAsFixed(1)}% · ${r.auditCount}',
                ),
            ]);
          },
        ),
      ],
    );
  }

  Widget _pipelineCard(List<FunnelStage> funnel, Map<String, int> side) {
    final max = funnel.fold<int>(1, (m, s) => math.max(m, s.count));
    return AuditSectionCard(
      title: 'Audit Progress',
      icon: Icons.account_tree_rounded,
      children: [
        const Text('Tap a stage to see those audits.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
        const SizedBox(height: 6),
        for (final s in funnel)
          InkWell(
            onTap: s.count > 0 ? () => _openPlans(status: s.status) : null,
            child: _HBar(
              label: s.label,
              fraction: s.count / max,
              color: (s.status == 'BM_ACTION_PENDING' ||
                      s.status == 'BM_ACTION_SUBMITTED' ||
                      s.status == 'VERIFICATION_PENDING')
                  ? AppColors.warning
                  : AppColors.primary,
              trailing: '${s.count}',
            ),
          ),
        if (side.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in side.entries)
                ActionChip(
                  label: Text('${auditStatusTone(e.key).label}: ${e.value}',
                      style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _openPlans(status: e.key),
                ),
            ]),
          ),
      ],
    );
  }

  Widget _scoreCard(ScoreDistribution dist) {
    return AuditSectionCard(
      title: 'Audit Performance',
      icon: Icons.speed_rounded,
      children: [
        if (dist.scoredCount == 0)
          const _EmptyLine('No scored audits yet.')
        else ...[
          Text(auditPct(dist.averageScore),
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          Text('average score across ${dist.scoredCount} scored audits',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 8),
          for (final b in dist.bands)
            _HBar(
              label: b.label,
              fraction: dist.scoredCount == 0 ? 0 : b.count / dist.scoredCount,
              color: _kBandColor[b.key] ?? AppColors.primary,
              trailing: '${b.count} audits',
            ),
          if (dist.unscoredCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${dist.unscoredCount} audit(s) not yet scored.',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ),
        ],
      ],
    );
  }

  Widget _severityCard(AuditKpis k) {
    final rows = [
      for (final s in kSeverityOrder)
        if ((k.findingsBySeverity[s] ?? 0) > 0) (s, k.findingsBySeverity[s]!),
    ];
    final total = rows.fold<int>(0, (a, r) => a + r.$2);
    return AuditSectionCard(
      title: 'Findings by Severity',
      icon: Icons.donut_large_rounded,
      children: [
        if (rows.isEmpty)
          const _EmptyLine('No findings recorded yet.')
        else
          Row(children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _DonutPainter([
                  for (final r in rows)
                    (r.$2.toDouble(), _kSeverityColor[r.$1] ?? AppColors.muted),
                ]),
                child: Center(
                  child: Text('$total',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(children: [
                for (final r in rows)
                  InkWell(
                    onTap: () => _openFindings(severity: r.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: _kSeverityColor[r.$1],
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_kSeverityLabel[r.$1] ?? r.$1,
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.ink))),
                        Text(
                            '${r.$2} (${(r.$2 / total * 100).toStringAsFixed(0)}%)',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSoft)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ]),
      ],
    );
  }

  Widget _trendCard(List<TrendPoint> trend) {
    final has = trend.any((t) => t.planned > 0 || t.completed > 0);
    return AuditSectionCard(
      title: 'Audit Progress Trend',
      icon: Icons.show_chart_rounded,
      children: [
        if (!has)
          _EmptyLine('No planned/completed audits in the last ${trend.length} months.')
        else ...[
          SizedBox(
            height: 180,
            child: CustomPaint(
              size: Size.infinite,
              painter: _TrendPainter(trend),
            ),
          ),
          const SizedBox(height: 8),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Legend(color: Color(0xFF6366F1), label: 'Planned (start date)'),
            SizedBox(width: 14),
            _Legend(color: Color(0xFF10B981), label: 'Completed (end date)'),
          ]),
        ],
      ],
    );
  }

  Widget _recentCard(List<AuditPlan> recent) {
    return AuditSectionCard(
      title: 'Recent Audit Activity',
      icon: Icons.history_rounded,
      children: [
        if (recent.isEmpty)
          const _EmptyLine('No recent audit activity.')
        else
          for (final p in recent)
            InkWell(
              onTap: p.id == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AuditDetailScreen(planId: p.id!))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.code ?? ''}  ${p.title ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                        Text(
                            '${p.branchName ?? '—'} · created ${_fmtDt(p.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AuditStatusChip(status: p.status),
                ]),
              ),
            ),
      ],
    );
  }

  static String _fmtDt(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    return d == null ? '—' : DateFormat('dd MMM yyyy').format(d.toLocal());
  }
}

// ── Small widgets / painters ───────────────────────────────────────────────

class _Kpi {
  final String label, value;
  final IconData icon;
  final Color tone;
  final String? hint;
  final VoidCallback? onTap;
  const _Kpi(this.label, this.value, this.icon, this.tone, this.hint, this.onTap);
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});
  final _Kpi kpi;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: kpi.onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        shadow: AppShadows.soft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(kpi.icon, size: 16, color: kpi.tone),
              const SizedBox(width: 6),
              Expanded(
                child: Text(kpi.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(kpi.value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: kpi.tone)),
            if (kpi.hint != null)
              Text(kpi.hint!,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
      ]);
}

/// Label + trailing value over a rounded horizontal bar (fraction 0..1).
class _HBar extends StatelessWidget {
  const _HBar({
    required this.label,
    required this.fraction,
    required this.color,
    required this.trailing,
  });
  final String label, trailing;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft)),
            ),
            Text(trailing,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(children: [
              Container(height: 10, color: AppColors.hairline),
              FractionallySizedBox(
                widthFactor: f,
                child: Container(height: 10, color: color),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);
  final List<(double, Color)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, s) => a + s.$1);
    if (total <= 0) return;
    final stroke = size.shortestSide * 0.22;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke,
        size.height - stroke);
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.$1 / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        math.max(0, sweep - 0.03),
        false,
        Paint()
          ..color = s.$2
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}

/// Grouped bars: planned (indigo) + completed (green) per month.
class _TrendPainter extends CustomPainter {
  _TrendPainter(this.trend);
  final List<TrendPoint> trend;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 18.0;
    const topPad = 14.0;
    final chartH = size.height - labelH - topPad;
    final maxV = trend.fold<int>(
        1, (m, t) => math.max(m, math.max(t.planned, t.completed)));
    final grid = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final slot = size.width / trend.length;
    final barW = math.min(slot * 0.28, 22.0);
    void bar(double cx, int v, Color c) {
      if (v <= 0) return;
      final h = chartH * v / maxV;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, topPad + chartH - h, barW, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(r, Paint()..color = c);
      _text(canvas, '$v', Offset(cx + barW / 2, topPad + chartH - h - 12),
          AppColors.inkSoft, 9.5);
    }

    for (var i = 0; i < trend.length; i++) {
      final t = trend[i];
      final center = slot * i + slot / 2;
      bar(center - barW - 1, t.planned, const Color(0xFF6366F1));
      bar(center + 1, t.completed, const Color(0xFF10B981));
      final parts = t.month.split('-');
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
      _text(canvas, DateFormat("MMM yy").format(d),
          Offset(center, size.height - labelH + 3), AppColors.muted, 10);
    }
  }

  void _text(Canvas canvas, String s, Offset centerTop, Color color, double fs) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: fs, color: color)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(centerTop.dx - tp.width / 2, centerTop.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.trend != trend;
}
