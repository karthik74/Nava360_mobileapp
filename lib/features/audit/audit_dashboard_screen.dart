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
import '../../core/pro_ui.dart';
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

  /// Plans / findings narrowed to the picked period + org scope.
  ({List<AuditPlan> plans, List<AuditFinding> findings}) _slice(
      _DashData d, List<BranchOption> branches) {
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
    return (plans: plans, findings: findings);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_dashDataProvider);
    final branches =
        ref.watch(auditBranchesProvider).asData?.value ?? const <BranchOption>[];
    final d = data.valueOrNull;
    final slice = d == null ? null : _slice(d, branches);
    final k = slice == null ? null : computeAuditKpis(slice.plans, slice.findings);

    return ProPage(
      onRefresh: _refresh,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      hero: _hero(k, branches),
      children: [
        if (_filtersOpen && branches.isNotEmpty) _orgFilterCard(branches),
        if (_orgActive || _periodActive) _scopeRow(),
        data.when(
          loading: () => const AppLoadingBlock(height: 320),
          error: (e, __) => AppErrorPanel(
            message: 'Could not load the audit dashboard.\n$e',
            onRetry: () => ref.invalidate(_dashDataProvider),
          ),
          data: (d) {
            final s = slice ?? _slice(d, branches);
            return _content(d, s, k ?? computeAuditKpis(s.plans, s.findings));
          },
        ),
      ],
    );
  }

  // ── Hero ───────────────────────────────────────────────────────────────────

  Widget _hero(AuditKpis? k, List<BranchOption> branches) {
    String n(int? v) => v == null ? '—' : '$v';
    String? pct(int v, int total) =>
        total > 0 ? '${(v / total * 100).toStringAsFixed(1)}% of total' : null;
    final tBranch = Branding.current.term('branch');
    final scope = _scopeText();
    return ProHero(
      title: 'Audit dashboard',
      subtitle: scope.isEmpty
          ? 'All periods · every ${tBranch.toLowerCase()} in scope'
          : scope,
      actions: [
        if (branches.isNotEmpty)
          ProHeroIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filter by $tBranch',
            badge: _orgActive,
            onTap: () => setState(() => _filtersOpen = !_filtersOpen),
          ),
      ],
      overlap: ProKpiStrip(cells: [
        ProKpi(
          value: _month == null ? 'All' : _kMonths[_month! - 1],
          label: 'Month',
          onTap: _pickMonth,
        ),
        ProKpi(
          value: _year == null ? 'All' : '$_year',
          label: 'Year',
          onTap: _pickYear,
        ),
        if (branches.isNotEmpty)
          ProKpi(
            value: _branchLabel(branches) ?? 'All',
            label: tBranch,
            onTap: () => _pickBranch(branches),
          ),
      ]),
      children: [
        Column(
          children: [
            ProHeroStats(stats: [
              ProStat(
                label: 'Total',
                value: n(k?.totalAudits),
                sub: 'All statuses',
                dot: const Color(0xFF9FCBD5),
                onTap: () => _openPlans(),
              ),
              ProStat(
                label: 'Planned',
                value: n(k?.plannedAudits),
                sub: k == null ? null : pct(k.plannedAudits, k.totalAudits),
                dot: const Color(0xFF9DB9F0),
                onTap: () => _openPlans(status: 'PLANNED'),
              ),
              ProStat(
                label: 'In progress',
                value: n(k?.inProgressAudits),
                sub: k == null ? null : pct(k.inProgressAudits, k.totalAudits),
                dot: const Color(0xFF5FC3D6),
                onTap: () => _openPlans(status: 'IN_PROGRESS'),
              ),
            ]),
            const SizedBox(height: 8),
            ProHeroStats(stats: [
              ProStat(
                label: 'Submitted',
                value: n(k?.submittedAudits),
                sub: k == null ? null : pct(k.submittedAudits, k.totalAudits),
                dot: const Color(0xFFB79BE0),
                onTap: () => _openPlans(status: 'SUBMITTED'),
              ),
              ProStat(
                label: 'Completed',
                value: n(k?.completedAudits),
                sub: k == null ? null : pct(k.completedAudits, k.totalAudits),
                dot: AppColors.live,
                onTap: () => _openPlans(status: 'CLOSED'),
              ),
              ProStat(
                label: 'Overdue',
                value: n(k?.overdueAudits),
                sub: k == null ? null : pct(k.overdueAudits, k.totalAudits),
                dot: const Color(0xFFE5484D),
              ),
            ]),
          ],
        ),
      ],
    );
  }

  // ── Filters ────────────────────────────────────────────────────────────────

  ({
    List<String> regions,
    List<String> divisions,
    List<String> areas,
    List<BranchOption> inScope,
  }) _orgOptions(List<BranchOption> all) {
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
    return (regions: regions, divisions: divisions, areas: areas, inScope: inScope);
  }

  String? _branchLabel(List<BranchOption> all) {
    if (_branchId == null) return null;
    for (final b in all) {
      if (b.id == _branchId) return b.label;
    }
    return null;
  }

  Future<void> _pick<T>({
    required String title,
    required T? selected,
    required List<({T? value, String label})> options,
    required ValueChanged<T?> onChanged,
  }) async {
    final r = await showAuditPicker<T>(
      context,
      title: title,
      options: options,
      selected: selected,
    );
    if (r == null || !mounted) return;
    onChanged(r.value);
  }

  void _pickMonth() => _pick<int>(
        title: 'Month',
        selected: _month,
        options: [
          (value: null, label: 'All months'),
          for (var i = 0; i < 12; i++) (value: i + 1, label: _kMonths[i]),
        ],
        onChanged: (v) => setState(() => _month = v),
      );

  void _pickYear() {
    final year = DateTime.now().year;
    _pick<int>(
      title: 'Year',
      selected: _year,
      options: [
        (value: null, label: 'All years'),
        for (var y = year; y >= year - 5; y--) (value: y, label: '$y'),
      ],
      onChanged: (v) => setState(() => _year = v),
    );
  }

  void _pickBranch(List<BranchOption> all) {
    final tBranch = Branding.current.term('branch');
    _pick<int>(
      title: tBranch,
      selected: _branchId,
      options: [
        (value: null, label: 'All ${_pl(tBranch)}'),
        for (final b in _orgOptions(all).inScope) (value: b.id, label: b.label),
      ],
      onChanged: (v) => setState(() => _branchId = v),
    );
  }

  Widget _orgFilterCard(List<BranchOption> all) {
    final o = _orgOptions(all);
    final tRegion = Branding.current.term('region');
    final tDivision = Branding.current.term('division');
    final tArea = Branding.current.term('area');
    final tBranch = Branding.current.term('branch');

    List<({String? value, String label})> strOpts(List<String> v, String all) => [
          (value: null, label: all),
          for (final s in v) (value: s, label: s),
        ];

    final region = AuditPickField(
      label: tRegion,
      value: _region ?? 'All ${_pl(tRegion)}',
      active: _region != null,
      onTap: () => _pick<String>(
        title: tRegion,
        selected: _region,
        options: strOpts(o.regions, 'All ${_pl(tRegion)}'),
        onChanged: (v) => setState(() {
          _region = v;
          _division = null;
          _area = null;
          _branchId = null;
        }),
      ),
    );
    final division = AuditPickField(
      label: tDivision,
      value: _division ?? 'All ${_pl(tDivision)}',
      active: _division != null,
      onTap: () => _pick<String>(
        title: tDivision,
        selected: _division,
        options: strOpts(o.divisions, 'All ${_pl(tDivision)}'),
        onChanged: (v) => setState(() {
          _division = v;
          _area = null;
          _branchId = null;
        }),
      ),
    );
    final area = AuditPickField(
      label: tArea,
      value: _area ?? 'All ${_pl(tArea)}',
      active: _area != null,
      onTap: () => _pick<String>(
        title: tArea,
        selected: _area,
        options: strOpts(o.areas, 'All ${_pl(tArea)}'),
        onChanged: (v) => setState(() {
          _area = v;
          _branchId = null;
        }),
      ),
    );
    final branch = AuditPickField(
      label: tBranch,
      value: _branchLabel(all) ?? 'All ${_pl(tBranch)}',
      active: _branchId != null,
      onTap: () => _pickBranch(all),
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: 'Filter by $tBranch',
            trailing: IconButton(
              tooltip: 'Close filter',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
              onPressed: () => setState(() => _filtersOpen = false),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: region),
            const SizedBox(width: 8),
            Expanded(child: division),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: area),
            const SizedBox(width: 8),
            Expanded(child: branch),
          ]),
        ],
      ),
    );
  }

  Widget _scopeRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.filter_alt_outlined, size: 17, color: AppColors.inkSoft),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _scopeText(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.inkSoft,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _month = null;
            _year = null;
            _region = _division = _area = null;
            _branchId = null;
          }),
          child: const Text('Clear filters'),
        ),
      ]),
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

  // ── Content ────────────────────────────────────────────────────────────────

  Widget _content(
    _DashData d,
    ({List<AuditPlan> plans, List<AuditFinding> findings}) s,
    AuditKpis k,
  ) {
    final plans = s.plans;
    final findings = s.findings;
    final funnel = computeFunnel(plans);
    final side = computeFunnelSide(plans);
    final dist = computeScoreDistribution(plans);
    final trend = computeTrend(plans);
    final recent = computeRecentActivity(plans);
    final attention = computeAttentionGroups(plans, findings);

    String? pct(int n, int total) =>
        total > 0 ? '${(n / total * 100).toStringAsFixed(1)}% of total' : null;

    final sections = <Widget>[
      if (d.truncated)
        ProNote(
          'Only the most recent ${d.plans.length} audits and '
          '${d.findings.length} findings were loaded — totals may be incomplete.',
          tone: ProNoteTone.warn,
        ),
      if (d.plansError != null)
        ProNote('Audits could not be loaded: ${d.plansError}',
            tone: ProNoteTone.warn),
      if (d.findingsError != null)
        ProNote('Findings could not be loaded: ${d.findingsError}',
            tone: ProNoteTone.warn),
      _findingsCard(k, pct),
      _attentionBlock(attention),
      _pipelineCard(funnel, side),
      _scoreCard(dist),
      _severityCard(k),
      _trendCard(trend),
      _categoryCard(),
      _recentBlock(recent),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          sections[i],
        ],
      ],
    );
  }

  Widget _findingsCard(AuditKpis k, String? Function(int, int) pct) {
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const SizedBox(width: 10),
              Expanded(child: b),
            ],
          ),
        );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: 'Findings & compliance',
            actionLabel: 'View all',
            onAction: () => _openFindings(),
          ),
          const SizedBox(height: 10),
          pair(
            _MetricTile(
              label: 'Total findings',
              value: '${k.totalFindings}',
              icon: Icons.report_problem_rounded,
              tone: AppColors.primary,
              hint: 'All severities',
              onTap: () => _openFindings(),
            ),
            _MetricTile(
              label: 'Open',
              value: '${k.openFindings}',
              icon: Icons.error_outline_rounded,
              tone: AppColors.warning,
              hint: pct(k.openFindings, k.totalFindings),
              onTap: () => _openFindings(status: 'OPEN'),
            ),
          ),
          const SizedBox(height: 10),
          pair(
            _MetricTile(
              label: 'Critical',
              value: '${k.criticalFindings}',
              icon: Icons.local_fire_department_rounded,
              tone: AppColors.danger,
              valueColor: k.criticalFindings > 0 ? AppColors.danger : null,
              hint: pct(k.criticalFindings, k.totalFindings),
              onTap: () => _openFindings(severity: 'HIGH', status: 'OPEN'),
            ),
            _MetricTile(
              label: 'Overdue',
              value: '${k.overdueFindings}',
              icon: Icons.warning_amber_rounded,
              tone: AppColors.danger,
              hint: pct(k.overdueFindings, k.totalFindings),
              onTap: () => _openFindings(overdue: true),
            ),
          ),
          const SizedBox(height: 10),
          _AvgScoreTile(score: k.averageScore),
        ],
      ),
    );
  }

  void _openAttention(AttentionItem it) {
    if (it.planId != null) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AuditDetailScreen(planId: it.planId!)));
    } else if (it.findingId != null) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FindingDetailScreen(findingId: it.findingId!)));
    }
  }

  Widget _attentionBlock(List<AttentionGroup> groups) {
    if (groups.isEmpty) {
      return const GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(title: 'Attention required'),
            _EmptyLine('Nothing needs attention right now.'),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProSectionHeader(title: 'Attention required'),
        for (final g in groups) ...[
          const SizedBox(height: 12),
          ProSectionHeader(title: '${g.label} · ${g.count}', small: true),
          const SizedBox(height: 8),
          ProListGroup(
            children: [
              for (final it in g.items)
                ProListRow(
                  leading: ProIconWell(
                    icon: it.planId != null
                        ? Icons.fact_check_rounded
                        : Icons.report_problem_rounded,
                    color: it.high ? AppColors.danger : AppColors.warning,
                  ),
                  title: it.title,
                  subtitle: [
                    if (it.code.isNotEmpty) it.code,
                    if ((it.branchName ?? '').isNotEmpty) it.branchName!,
                    it.detail,
                  ].join(' · '),
                  pill: auditPill(
                    _sentence(it.statusLabel),
                    it.high ? AppColors.danger : AppColors.warning,
                  ),
                  onTap: (it.planId != null || it.findingId != null)
                      ? () => _openAttention(it)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _categoryCard() {
    final async = ref.watch(_categoryScoresProvider((_month, _year)));
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(
            title: 'Branch administration observations',
            subtitle: 'Average score per category.',
          ),
          const SizedBox(height: 6),
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
                    color: AppColors.primary,
                    trailing: r.averagePercentage == null
                        ? 'Not scored'
                        : '${r.averagePercentage!.toStringAsFixed(1)}% · ${r.auditCount}',
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _pipelineCard(List<FunnelStage> funnel, Map<String, int> side) {
    final max = funnel.fold<int>(1, (m, s) => math.max(m, s.count));
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(
            title: 'Audit progress',
            subtitle: 'Tap a stage to see those audits.',
          ),
          const SizedBox(height: 6),
          for (final s in funnel)
            _HBar(
              label: s.label,
              fraction: s.count / max,
              color: (s.status == 'BM_ACTION_PENDING' ||
                      s.status == 'BM_ACTION_SUBMITTED' ||
                      s.status == 'VERIFICATION_PENDING')
                  ? AppColors.warning
                  : AppColors.primary,
              trailing: '${s.count}',
              dim: s.count == 0,
              onTap: s.count > 0 ? () => _openPlans(status: s.status) : null,
            ),
          if (side.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in side.entries)
                  _TapPill(
                    label: '${auditStatusTone(e.key).label}: ${e.value}',
                    color: auditStatusTone(e.key).color,
                    onTap: () => _openPlans(status: e.key),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _scoreCard(ScoreDistribution dist) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Audit performance'),
          const SizedBox(height: 10),
          if (dist.scoredCount == 0)
            const _EmptyLine('No scored audits yet.')
          else ...[
            Row(children: [
              AuditScoreRing(score: dist.averageScore, size: 84, label: 'Avg score'),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Average score', style: AppText.title),
                    const SizedBox(height: 2),
                    Text(
                      'across ${dist.scoredCount} scored audits',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            for (final b in dist.bands)
              _HBar(
                label: b.label,
                fraction: dist.scoredCount == 0 ? 0 : b.count / dist.scoredCount,
                color: _kBandColor[b.key] ?? AppColors.primary,
                trailing: '${b.count} audits',
              ),
            if (dist.unscoredCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${dist.unscoredCount} audit(s) not yet scored.',
                    style: AppText.caption),
              ),
          ],
        ],
      ),
    );
  }

  Widget _severityCard(AuditKpis k) {
    final rows = [
      for (final s in kSeverityOrder)
        if ((k.findingsBySeverity[s] ?? 0) > 0) (s, k.findingsBySeverity[s]!),
    ];
    final total = rows.fold<int>(0, (a, r) => a + r.$2);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Findings by severity'),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const _EmptyLine('No findings recorded yet.')
          else
            Row(children: [
              SizedBox(
                width: 116,
                height: 116,
                child: CustomPaint(
                  painter: _DonutPainter([
                    for (final r in rows)
                      (r.$2.toDouble(), _kSeverityColor[r.$1] ?? AppColors.muted),
                  ]),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$total',
                            style: const TextStyle(
                                fontSize: 22,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                                color: AppColors.ink,
                                fontFeatures: [FontFeature.tabularFigures()])),
                        const Text('findings', style: AppText.caption),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(children: [
                  for (final r in rows)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openFindings(severity: r.$1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: _kSeverityColor[r.$1],
                                  borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 9),
                          Expanded(
                              child: Text(_kSeverityLabel[r.$1] ?? r.$1,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.ink))),
                          Text(
                              '${r.$2} (${(r.$2 / total * 100).toStringAsFixed(0)}%)',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSoft,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right_rounded,
                              size: 18, color: Color(0xFFB3C0C3)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _trendCard(List<TrendPoint> trend) {
    final has = trend.any((t) => t.planned > 0 || t.completed > 0);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Audit progress trend'),
          const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 6,
              children: [
                _Legend(color: AppColors.primary, label: 'Planned (start date)'),
                const _Legend(color: AppColors.success, label: 'Completed (end date)'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _recentBlock(List<AuditPlan> recent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProSectionHeader(title: 'Recent audit activity', small: true),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const GlassCard(child: _EmptyLine('No recent audit activity.'))
        else
          ProListGroup(
            children: [
              for (final p in recent)
                ProListRow(
                  leading: ProIconWell(
                    icon: Icons.fact_check_rounded,
                    color: auditStatusTone(p.status).color,
                  ),
                  title: p.title ?? p.code ?? 'Audit',
                  subtitle: [
                    if ((p.code ?? '').isNotEmpty) p.code!,
                    p.branchName ?? '—',
                    'created ${_fmtDt(p.createdAt)}',
                  ].join(' · '),
                  pill: AuditStatusChip(status: p.status),
                  onTap: p.id == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AuditDetailScreen(planId: p.id!))),
                ),
            ],
          ),
      ],
    );
  }

  /// "BM ACTION PENDING" → "BM action pending" (display only).
  static String _sentence(String s) {
    if (s.isEmpty || s != s.toUpperCase()) return s;
    const keep = {'BM', 'CAPA', 'OD', 'NPA', 'NA'};
    final words = [
      for (final w in s.split(' ')) keep.contains(w) ? w : w.toLowerCase(),
    ];
    final first = words.first;
    if (first.isNotEmpty && !keep.contains(first)) {
      words[0] = first[0].toUpperCase() + first.substring(1);
    }
    return words.join(' ');
  }

  static String _fmtDt(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    return d == null ? '—' : DateFormat('dd MMM yyyy').format(d.toLocal());
  }
}

// ── Small widgets / painters ───────────────────────────────────────────────

/// Light metric cell (icon well, label, big value, hint) inside a card.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.hint,
    this.onTap,
    this.valueColor,
  });

  final String label, value;
  final IconData icon;
  final Color tone;
  final String? hint;
  final VoidCallback? onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(icon: icon, color: tone, size: 30),
              const SizedBox(height: 10),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(
                        fontSize: 22,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: valueColor ?? AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              if (hint != null)
                Text(hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.faint,
                        fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width "Avg score" cell with a thin bar.
class _AvgScoreTile extends StatelessWidget {
  const _AvgScoreTile({required this.score});
  final double? score;

  @override
  Widget build(BuildContext context) {
    final tone = auditScoreTone(score);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        ProIconWell(icon: Icons.speed_rounded, color: tone, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Avg score',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted)),
              const SizedBox(height: 7),
              ProBar(value: (score ?? 0) / 100, color: tone),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Text(
          score == null ? '—' : '${score!.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: score == null ? AppColors.ink : auditInk(tone),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ]),
    );
  }
}

/// Tappable tinted pill (status side-counts).
class _TapPill extends StatelessWidget {
  const _TapPill({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: auditPill(label, color),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
      ]);
}

/// Label + trailing value over a rounded horizontal bar (fraction 0..1).
class _HBar extends StatelessWidget {
  const _HBar({
    required this.label,
    required this.fraction,
    required this.color,
    required this.trailing,
    this.onTap,
    this.dim = false,
  });
  final String label, trailing;
  final double fraction;
  final Color color;
  final VoidCallback? onTap;

  /// Greys the label of an empty stage.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: dim ? AppColors.faint : AppColors.inkSoft)),
            ),
            const SizedBox(width: 8),
            Text(trailing,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dim ? AppColors.faint : AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 6),
          ProBar(value: f, color: color, height: 8),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: body,
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
    final stroke = size.shortestSide * 0.16;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke,
        size.height - stroke);
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.$1 / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        math.max(0, sweep - 0.05),
        false,
        Paint()
          ..color = s.$2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}

/// Grouped bars: planned (brand) + completed (green) per month.
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
      ..color = AppColors.hairlineSoft
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
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx, topPad + chartH - h, barW, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(r, Paint()..color = c);
      _text(canvas, '$v', Offset(cx + barW / 2, topPad + chartH - h - 13),
          AppColors.inkSoft, 10);
    }

    for (var i = 0; i < trend.length; i++) {
      final t = trend[i];
      final center = slot * i + slot / 2;
      bar(center - barW - 1, t.planned, AppColors.primary);
      bar(center + 1, t.completed, AppColors.success);
      final parts = t.month.split('-');
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
      _text(canvas, DateFormat("MMM yy").format(d),
          Offset(center, size.height - labelH + 3), AppColors.muted, 10.5);
    }
  }

  void _text(Canvas canvas, String s, Offset centerTop, Color color, double fs) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontFamily: 'Geist',
              fontSize: fs,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()])),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(centerTop.dx - tp.width / 2, centerTop.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.trend != trend;
}
