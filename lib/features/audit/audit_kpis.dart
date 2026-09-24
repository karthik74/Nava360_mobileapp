// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — dashboard KPI rollups (port of web lib/auditKpis.ts).
//
//  `GET /api/audit/dashboard` has no scope filter, so — exactly like the web
//  dashboard — every plan and finding the caller may see is loaded and rolled up
//  here, which lets the org / month filters slice the numbers instantly.
//  Counting rules mirror AuditDashboardService.kpis(); keep them in sync.
// ─────────────────────────────────────────────────────────────────────────────

import 'audit_models.dart';

const kSeverityOrder = ['HIGH', 'MODERATE', 'LOW'];

const kPendingStates = <String>{
  'SUBMITTED',
  'SUPERVISOR_APPROVAL_PENDING',
  'BM_ACTION_PENDING',
  'BM_ACTION_SUBMITTED',
  'VERIFICATION_PENDING',
  'REOPENED',
};
const _terminalStates = <String>{'CLOSED', 'CANCELLED'};
const _openFindingStates = <String>{
  'OPEN',
  'ACTION_PENDING',
  'ACTION_SUBMITTED',
  'VERIFICATION_PENDING',
  'REOPENED',
  'ESCALATED',
  'OVERDUE',
};

bool isFindingOpen(AuditFinding f) => _openFindingStates.contains(f.status);

String _two(int n) => n.toString().padLeft(2, '0');

/// Today as YYYY-MM-DD (local) — plannedEndDate is a local date, not an instant.
String localToday([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${n.year}-${_two(n.month)}-${_two(n.day)}';
}

String _day(String s) => s.length > 10 ? s.substring(0, 10) : s;

bool isPlanOverdue(AuditPlan p, [String? today]) {
  final end = p.plannedEndDate;
  if (end == null || end.isEmpty) return false;
  final t = today ?? localToday();
  return _day(end).compareTo(t) < 0 && !_terminalStates.contains(p.status);
}

/// Inclusive YYYY-MM-DD bounds of a month (or whole year when [month] is null).
({String start, String end}) periodBounds(int? month, int year) {
  final y = year.toString().padLeft(4, '0');
  if (month == null) return (start: '$y-01-01', end: '$y-12-31');
  final last = DateTime(year, month + 1, 0).day;
  return (start: '$y-${_two(month)}-01', end: '$y-${_two(month)}-${_two(last)}');
}

/// True when the plan belongs to the month/year window. A CLOSED plan belongs to
/// the month it was closed in; open plans fall back to their covered period.
bool isPlanInPeriod(AuditPlan p, int? month, int? year) {
  if (month == null && year == null) return true;
  final b = periodBounds(month, year ?? DateTime.now().year);
  if (p.status == 'CLOSED' && (p.closedAt ?? '').isNotEmpty) {
    final c = _day(p.closedAt!);
    return c.compareTo(b.start) >= 0 && c.compareTo(b.end) <= 0;
  }
  final ps = p.periodFrom ?? p.plannedStartDate;
  final pe = p.periodTo ?? p.plannedEndDate ?? ps;
  if (ps == null || ps.isEmpty) return false;
  return _day(ps).compareTo(b.end) <= 0 &&
      _day(pe ?? ps).compareTo(b.start) >= 0;
}

class AuditKpis {
  int totalAudits = 0,
      plannedAudits = 0,
      inProgressAudits = 0,
      submittedAudits = 0,
      completedAudits = 0,
      pendingAudits = 0,
      overdueAudits = 0;
  int totalFindings = 0,
      openFindings = 0,
      criticalFindings = 0,
      overdueFindings = 0;
  double? averageScore;
  final Map<String, int> findingsBySeverity = {
    for (final s in kSeverityOrder) s: 0,
  };
}

AuditKpis computeAuditKpis(List<AuditPlan> plans, List<AuditFinding> findings) {
  final k = AuditKpis();
  final today = localToday();
  var sum = 0.0, cnt = 0;
  for (final p in plans) {
    final s = p.status;
    if (s == 'PLANNED' || s == 'ASSIGNED') k.plannedAudits++;
    if (s == 'IN_PROGRESS') k.inProgressAudits++;
    if (s == 'SUBMITTED') k.submittedAudits++;
    if (s == 'CLOSED') k.completedAudits++;
    if (kPendingStates.contains(s)) k.pendingAudits++;
    if (isPlanOverdue(p, today)) k.overdueAudits++;
    if (p.finalScore != null) {
      sum += p.finalScore!;
      cnt++;
    }
  }
  k.totalAudits = plans.length;
  k.totalFindings = findings.length;
  for (final f in findings) {
    final sev = f.severity ?? '';
    k.findingsBySeverity[sev] = (k.findingsBySeverity[sev] ?? 0) + 1;
    final open = isFindingOpen(f);
    if (open) k.openFindings++;
    if (open && f.severity == 'HIGH') k.criticalFindings++;
    if (f.status == 'OVERDUE') k.overdueFindings++;
  }
  k.averageScore = cnt == 0 ? null : (sum / cnt * 100).round() / 100;
  return k;
}

// ── Funnel ──

class FunnelStage {
  final String status;
  final String label;
  final int count;
  const FunnelStage(this.status, this.label, this.count);
}

const _funnelDefs = <(String, String)>[
  ('PLANNED', 'Planned'),
  ('ASSIGNED', 'Assigned'),
  ('IN_PROGRESS', 'In Progress'),
  ('SUBMITTED', 'Submitted'),
  ('SUPERVISOR_APPROVAL_PENDING', 'Supervisor Approval'),
  ('BM_ACTION_PENDING', 'BM Action Pending'),
  ('BM_ACTION_SUBMITTED', 'BM Action Submitted'),
  ('VERIFICATION_PENDING', 'Verification'),
  ('CLOSED', 'Completed'),
];

List<FunnelStage> computeFunnel(List<AuditPlan> plans) => [
      for (final d in _funnelDefs)
        FunnelStage(d.$1, d.$2, plans.where((p) => p.status == d.$1).length),
    ];

/// Side statuses reported outside the main flow.
Map<String, int> computeFunnelSide(List<AuditPlan> plans) => {
      for (final s in const ['REOPENED', 'CANCELLED', 'DRAFT'])
        if (plans.any((p) => p.status == s))
          s: plans.where((p) => p.status == s).length,
    };

// ── Score distribution ──

class ScoreBand {
  final String key, label;
  final int count;
  const ScoreBand(this.key, this.label, this.count);
}

class ScoreDistribution {
  final List<ScoreBand> bands;
  final double? averageScore;
  final int scoredCount, unscoredCount;
  const ScoreDistribution(
      this.bands, this.averageScore, this.scoredCount, this.unscoredCount);
}

const _bandDefs = <(String, String, double, double)>[
  ('critical', 'Critical / Low Score', 0, 49.999),
  ('needs_improvement', 'Needs Improvement', 50, 69.999),
  ('good', 'Good', 70, 84.999),
  ('excellent', 'Excellent', 85, 100),
];

ScoreDistribution computeScoreDistribution(List<AuditPlan> plans) {
  final scored = plans.where((p) => p.finalScore != null).toList();
  final bands = [
    for (final b in _bandDefs)
      ScoreBand(
        b.$1,
        b.$2,
        scored
            .where((p) => p.finalScore! >= b.$3 && p.finalScore! <= b.$4)
            .length,
      ),
  ];
  final avg = scored.isEmpty
      ? null
      : (scored.fold<double>(0, (a, p) => a + p.finalScore!) /
                  scored.length *
                  100)
              .round() /
          100;
  return ScoreDistribution(
      bands, avg, scored.length, plans.length - scored.length);
}

// ── Attention ──

class AttentionItem {
  final String code, title, detail, statusLabel;
  final String? branchName;
  final bool high;
  final int? planId;
  final int? findingId;
  const AttentionItem({
    required this.code,
    required this.title,
    required this.detail,
    required this.statusLabel,
    required this.high,
    this.branchName,
    this.planId,
    this.findingId,
  });
}

class AttentionGroup {
  final String key, label;
  final int count;
  final List<AttentionItem> items;
  const AttentionGroup(this.key, this.label, this.count, this.items);
}

List<AttentionGroup> computeAttentionGroups(
    List<AuditPlan> plans, List<AuditFinding> findings,
    {int limit = 5}) {
  final today = localToday();
  final overduePlans = plans.where((p) => isPlanOverdue(p, today)).toList();
  final critical =
      findings.where((f) => f.severity == 'HIGH' && isFindingOpen(f)).toList();
  final overdueF = findings.where((f) => f.status == 'OVERDUE').toList();
  final bm = plans.where((p) => p.status == 'BM_ACTION_PENDING').toList();
  final ver = plans.where((p) => p.status == 'VERIFICATION_PENDING').toList();
  final reop = plans.where((p) => p.status == 'REOPENED').toList();

  AttentionItem planItem(AuditPlan p, String detail, bool high) =>
      AttentionItem(
        code: p.code ?? '',
        title: p.title ?? 'Audit',
        detail: detail,
        statusLabel: (p.status ?? '').replaceAll('_', ' '),
        high: high,
        branchName: p.branchName,
        planId: p.id,
      );
  AttentionItem findingItem(AuditFinding f, String detail) => AttentionItem(
        code: f.code ?? '',
        title: f.title ?? 'Finding',
        detail: detail,
        statusLabel: (f.status ?? '').replaceAll('_', ' '),
        high: true,
        findingId: f.id,
      );

  final groups = [
    AttentionGroup('overdue_audits', 'Overdue Audits', overduePlans.length, [
      for (final p in overduePlans.take(limit))
        planItem(p, 'Planned end ${p.plannedEndDate}', true),
    ]),
    AttentionGroup('critical_findings', 'Critical Findings', critical.length, [
      for (final f in critical.take(limit))
        findingItem(f, f.category ?? f.sectionCode ?? 'High severity'),
    ]),
    AttentionGroup('overdue_findings', 'Overdue Findings', overdueF.length, [
      for (final f in overdueF.take(limit))
        findingItem(f, f.dueDate != null ? 'Due ${f.dueDate}' : 'Past due'),
    ]),
    AttentionGroup('bm_action_pending', 'Pending BM Action', bm.length, [
      for (final p in bm.take(limit))
        planItem(p, 'Awaiting branch manager compliance', false),
    ]),
    AttentionGroup('verification_pending', 'Pending Verification', ver.length, [
      for (final p in ver.take(limit))
        planItem(p, 'Awaiting auditor verification', false),
    ]),
    AttentionGroup('reopened', 'Reopened Audits', reop.length, [
      for (final p in reop.take(limit))
        planItem(p, 'Reopened after verification', false),
    ]),
  ];
  return groups.where((g) => g.count > 0).toList();
}

// ── Trend ──

class TrendPoint {
  final String month; // YYYY-MM
  final int planned, completed;
  const TrendPoint(this.month, this.planned, this.completed);
}

List<TrendPoint> computeTrend(List<AuditPlan> plans, {int monthsBack = 6}) {
  final now = DateTime.now();
  String? bucket(String? iso) =>
      (iso == null || iso.length < 7) ? null : iso.substring(0, 7);
  return [
    for (var i = monthsBack - 1; i >= 0; i--)
      () {
        final d = DateTime(now.year, now.month - i, 1);
        final m = '${d.year}-${_two(d.month)}';
        return TrendPoint(
          m,
          plans.where((p) => bucket(p.plannedStartDate) == m).length,
          plans
              .where((p) =>
                  p.status == 'CLOSED' && bucket(p.plannedEndDate) == m)
              .length,
        );
      }(),
  ];
}

/// Most recently created plans.
List<AuditPlan> computeRecentActivity(List<AuditPlan> plans, {int limit = 8}) {
  final sorted = [...plans]
    ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
  return sorted.take(limit).toList();
}
