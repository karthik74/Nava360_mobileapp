// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Daily Plan — the manager READ surfaces: the custom report builder, the
//  aggregated plan / plan-and-achievement report table, and the branches-pending
//  follow-up list. Ports DailyPlanScreen.tsx's ReportBuilder + PendingModal and
//  DailyPlanTable.tsx.
//
//  Uploading is Branch-Manager-only (the API 403s every non-branch writer), so
//  an AM and above get these read surfaces instead of the entry form.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_export.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

// ── Roles & levels ───────────────────────────────────────────────────────────

/// scope.tier → role bucket. all→CEO, region→RM, division→DM, area→AM,
/// branch→BM, self→FO. An explicit branch-side designation always wins.
String misRoleFromScope(String? tier, String role, [String? designation]) {
  final r = role.trim().toUpperCase();
  final d = (designation ?? '').trim().toLowerCase();
  if (r == 'BM' || d == 'branch manager' || d.contains('branch manager')) return 'BM';
  switch (tier) {
    case 'self':
      return 'FO';
    case 'branch':
      return 'BM';
    case 'area':
      return 'AM';
    case 'division':
      return 'DM';
    case 'region':
      return 'RM';
    case 'all':
    default:
      return 'CEO';
  }
}

/// Which report levels a role may pick (mirrors the live `allowedLevels()`).
List<String> misAllowedLevels(String role) {
  if (role == 'BM' || role == 'FO') return const ['BRANCH'];
  if (role == 'AM') return const ['AREA', 'BRANCH'];
  if (role == 'DM' || role == 'DvM') {
    return const ['DIVISION', 'AREA', 'BRANCH'];
  }
  return const ['REGION', 'DIVISION', 'AREA', 'BRANCH']; // CEO / RM / SM
}

/// Roles that may chase branches which haven't filed yet.
bool misCanSeePending(String role) =>
    const ['CEO', 'RM', 'SM', 'DM', 'DvM', 'AM'].contains(role);

const Map<String, String> _levelLabels = {
  'REGION': 'Region',
  'DIVISION': 'Division',
  'AREA': 'Area',
  'BRANCH': 'Branch',
};

/// The row field each report level groups by. The live site walks a
/// region→division→area→branch hierarchy; with the flat /rows feed we group by
/// the matching column.
const Map<String, String> _levelField = {
  'REGION': 'region',
  'DIVISION': 'division',
  'AREA': 'area',
  'BRANCH': 'branch_name',
};

// ── Metric columns ───────────────────────────────────────────────────────────

class _Metric {
  final String key;
  final String header;
  final String group;

  /// Renders as a rupee amount (crores) rather than a plain count.
  final bool amount;
  const _Metric(this.key, this.header, this.group, {this.amount = false});
}

/// The 14 metric columns the live generated report shows per side (plan /
/// achievement), in order. Amounts render in Crores — one unit across MIS.
const List<_Metric> _metrics = [
  _Metric('ftod', 'FTOD', 'FTOD'),
  _Metric('feb', '1-30 DPD', 'DPD'),
  _Metric('dpd31', '31-60 DPD', 'DPD'),
  _Metric('pnpa', '61-90 DPD', 'DPD'),
  _Metric('npa_act', 'Act', 'NPA'),
  _Metric('npa_clo', 'Clo', 'NPA'),
  _Metric('ns', 'NS Acc', 'FY'),
  _Metric('ns_plan', 'NS Plan', 'FY'),
  _Metric('disb_iglfig_acc', 'IGL&FIG Acc', 'Disb'),
  _Metric('disb_iglfig_amt', 'IGL&FIG Amt', 'Disb', amount: true),
  _Metric('disb_il_acc', 'IL Acc', 'Disb'),
  _Metric('disb_il_amt', 'IL Amt', 'Disb', amount: true),
  _Metric('kyc_figIgl', 'FIG&IGL', 'KYC'),
  _Metric('kyc_il', 'IL', 'KYC'),
];

/// Grouped header spans, in order.
const List<(String, int)> _groups = [
  ('FTOD', 1),
  ('DPD', 3),
  ('NPA', 2),
  ('FY', 2),
  ('Disb', 4),
  ('KYC', 2),
];

/// Per-row achievement% sums these count columns on each side.
const List<String> _pctCols = [
  'ftod',
  'feb',
  'dpd31',
  'pnpa',
  'ns',
  'disb_iglfig_acc',
  'disb_il_acc',
];

/// One aggregated report row: a level name plus the 14 metric totals.
class _ReportRow {
  final String name;
  final Map<String, double> m;
  _ReportRow(this.name, this.m);

  double get(String k) => m[k] ?? 0;
}

Map<String, double> _zero() => {for (final c in _metrics) c.key: 0};

/// Map one `/rows` record into the report's 14 aggregated metric fields.
/// The API returns 0 (not null) for the side that doesn't apply, so an
/// achievement row's `ftod_plan` of 0 must fall through to `ftod_actual`.
Map<String, double> _metricsFromRow(DailyPlanReportRow d) {
  double either(String a, String b) {
    final v = d.n(a);
    return v != 0 ? v : d.n(b);
  }

  return {
    'ftod': either('ftod_plan', 'ftod_actual'),
    'feb': either('dpd_1_30_plan', 'dpd_1_30_actual'),
    'dpd31': either('dpd_31_60_plan', 'dpd_31_60_actual'),
    'pnpa': either('dpd_61_90_plan', 'dpd_61_90_actual'),
    'npa_act': d.n('npa_activation'),
    'npa_clo': d.n('npa_closure'),
    'ns': d.n('fy_non_start_acc'),
    'ns_plan': d.n('fy_non_start_plan'),
    'disb_iglfig_acc': d.n('disb_igl_acc') + d.n('disb_fig_acc'),
    'disb_iglfig_amt': d.n('disb_igl_amt') + d.n('disb_fig_amt'),
    'disb_il_acc': d.n('disb_il_acc'),
    'disb_il_amt': d.n('disb_il_amt'),
    'kyc_figIgl': d.n('kyc_igl') + d.n('kyc_fig'),
    'kyc_il': d.n('kyc_il'),
  };
}

/// Group + aggregate the flat `/rows` into one report row per level key.
List<_ReportRow> _buildRows(List<DailyPlanReportRow> raw, String level) {
  final field = _levelField[level] ?? 'branch_name';
  final groups = <String, _ReportRow>{};
  for (final d in raw) {
    final key = d.group(field);
    final m = _metricsFromRow(d);
    final g = groups.putIfAbsent(key, () => _ReportRow(key, _zero()));
    for (final c in _metrics) {
      g.m[c.key] = g.get(c.key) + (m[c.key] ?? 0);
    }
  }
  final out = groups.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// Achievement % for one row = SUM(achievement count cols) / SUM(plan count
/// cols). Null when there's no achievement side or nothing was planned.
double? _rowPct(_ReportRow? plan, _ReportRow? ach) {
  if (plan == null || ach == null) return null;
  final p = _pctCols.fold<double>(0, (s, k) => s + plan.get(k));
  final a = _pctCols.fold<double>(0, (s, k) => s + ach.get(k));
  if (p == 0) return null;
  return (a / p * 1000).round() / 10;
}

Color _pctColor(double? p) {
  if (p == null) return AppColors.muted;
  if (p >= 100) return AppColors.success;
  if (p >= 60) return AppColors.muted;
  return AppColors.danger;
}

String _cellText(_ReportRow r, _Metric c) {
  final v = r.get(c.key);
  if (c.amount) return misCrore(v);
  return v == 0 ? '-' : misNum(v);
}

String _todayIso() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

String _shiftIso(String iso, int days) {
  final p = iso.split('-');
  if (p.length < 3) return iso;
  final d = DateTime(
    int.tryParse(p[0]) ?? 2000,
    int.tryParse(p[1]) ?? 1,
    int.tryParse(p[2]) ?? 1,
  ).add(Duration(days: days));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

/// Whole days between [iso] and today — drives which date pill reads active.
int _offsetFromToday(String iso) {
  final p = iso.split('-');
  if (p.length < 3) return 999;
  final d = DateTime(
    int.tryParse(p[0]) ?? 2000,
    int.tryParse(p[1]) ?? 1,
    int.tryParse(p[2]) ?? 1,
  );
  final now = DateTime.now();
  return d.difference(DateTime(now.year, now.month, now.day)).inDays;
}

// ── Report builder ───────────────────────────────────────────────────────────

/// Date + level controls with the three report actions. [autoLoad] renders the
/// plan + achievement table straight away instead of waiting for a Generate tap
/// — used for Area Managers, whose job here is to READ what their branches
/// filed. The Generate buttons stay, to re-run or switch mode.
class MisDailyPlanReport extends ConsumerStatefulWidget {
  const MisDailyPlanReport({
    super.key,
    required this.role,
    this.autoLoad = false,
  });

  final String role;
  final bool autoLoad;

  @override
  ConsumerState<MisDailyPlanReport> createState() =>
      _MisDailyPlanReportState();
}

class _MisDailyPlanReportState extends ConsumerState<MisDailyPlanReport> {
  late String _date = _todayIso();
  late String _level;
  String? _mode; // null = nothing generated yet; 'plan' | 'both'

  @override
  void initState() {
    super.initState();
    final levels = misAllowedLevels(widget.role);
    // Auto-loading opens at BRANCH when the role has it: an AM needs to see
    // WHICH branch filed what, which the area aggregate hides.
    _level = widget.autoLoad && levels.contains('BRANCH')
        ? 'BRANCH'
        : levels.first;
    if (widget.autoLoad) _mode = 'both';
  }

  @override
  Widget build(BuildContext context) {
    final levels = misAllowedLevels(widget.role);
    final offset = _offsetFromToday(_date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assessment_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Custom Report Builder',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Select date & level to generate reports',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
              const SizedBox(height: 14),

              const _FieldLabel('1. Select date'),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        setState(() => _date = _shiftIso(_date, -1)),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Previous day',
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_rounded,
                                size: 17, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                misPrettyDate(_date),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _date = _shiftIso(_date, 1)),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Next day',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in const [
                    (-1, 'Yesterday'),
                    (0, 'Today'),
                    (1, 'Tomorrow'),
                  ])
                    _Pill(
                      label: p.$2,
                      active: offset == p.$1,
                      onTap: () => setState(
                          () => _date = _shiftIso(_todayIso(), p.$1)),
                    ),
                ],
              ),

              const SizedBox(height: 16),
              const _FieldLabel('2. Report level'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lv in levels)
                    _Pill(
                      label: '${_levelLabels[lv]} Level',
                      active: _level == lv,
                      onTap: () => setState(() => _level = lv),
                    ),
                ],
              ),

              const SizedBox(height: 16),
              if (misCanSeePending(widget.role)) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openPending,
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: const Text('Branches Pending'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(color: AppColors.warning),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _mode = 'plan'),
                  icon: const Icon(Icons.assignment_rounded, size: 18),
                  label: const Text('Generate Plan Report'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => setState(() => _mode = 'both'),
                  icon: const Icon(Icons.description_rounded, size: 18),
                  label: const Text('Plan & Achievement'),
                ),
              ),
            ],
          ),
        ),
        if (_mode != null) ...[
          const SizedBox(height: 18),
          MisDailyPlanReportTable(
            level: _level,
            date: _date,
            mode: _mode!,
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate() async {
    final p = _date.split('-');
    final initial = DateTime(
      int.tryParse(p[0]) ?? DateTime.now().year,
      int.tryParse(p.length > 1 ? p[1] : '1') ?? 1,
      int.tryParse(p.length > 2 ? p[2] : '1') ?? 1,
    );
    // A daily report can target any past or (for plans) near-future date, so
    // the calendar is unrestricted — unlike the data-driven MIS pickers.
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 3),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _date = '${picked.year}'
          '-${picked.month.toString().padLeft(2, '0')}'
          '-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  void _openPending() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PendingBranchesSheet(date: _date),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: AppColors.muted,
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
              color: active ? AppColors.primary : AppColors.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

// ── Branches pending ─────────────────────────────────────────────────────────

class _PendingBranchesSheet extends ConsumerStatefulWidget {
  const _PendingBranchesSheet({required this.date});
  final String date;

  @override
  ConsumerState<_PendingBranchesSheet> createState() =>
      _PendingBranchesSheetState();
}

class _PendingBranchesSheetState extends ConsumerState<_PendingBranchesSheet> {
  String _type = 'plan';
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final q = DailyPlanReportQuery(widget.date, _type);
    final async = ref.watch(misDailyPlanPendingProvider(q));
    final label = _type == 'plan' ? 'Plan' : 'Achievement';

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Branches Pending',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          '${misPrettyDate(widget.date)} · $label',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  MisSegmented<String>(
                    options: const [
                      ('plan', 'Plan'),
                      ('achievement', 'Achievement'),
                    ],
                    value: _type,
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Download report',
                    onPressed: _downloading || (async.valueOrNull?.isEmpty ?? true)
                        ? null
                        : _download,
                    icon: _downloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: async.when(
                loading: () => const AppLoadingBlock(height: 200),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(18),
                  child: AppErrorPanel(
                    message: e.toString(),
                    onRetry: () =>
                        ref.invalidate(misDailyPlanPendingProvider(q)),
                  ),
                ),
                data: (branches) => branches.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: AppEmptyState(
                          icon: Icons.celebration_rounded,
                          message:
                              'All branches have uploaded for this date.',
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                        itemCount: branches.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 18, color: AppColors.hairline),
                        itemBuilder: (_, i) => _row(branches[i], i),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(PendingBranch b, int i) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${i + 1}. ${b.branchName}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              if (b.crumb.isNotEmpty)
                Text(b.crumb,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 2),
              Text(b.bmName ?? '—',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.inkSoft)),
            ],
          ),
        ),
        if (b.bmPhone != null && b.bmPhone!.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              final uri = Uri.parse('tel:${b.bmPhone}');
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
            icon: const Icon(Icons.call_rounded, size: 15),
            label: Text(b.bmPhone!,
                style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
          ),
      ],
    );
  }

  /// Formatted .xlsx built server-side — mirrors the web module's
  /// `dailyPlanPendingExport` (src/mis/gwm/api/dailyPlanApi.ts).
  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final (bytes, suggestedName) = await ref
          .read(misRepositoryProvider)
          .dailyPlanPendingExportBytes(widget.date, _type);
      if (!mounted) return;
      await misSaveBytes(
        context,
        suggestedName ?? 'branches-pending_${_type}_${widget.date}.xlsx',
        bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        noun: 'report',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Could not download the report: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}

// ── Report table ─────────────────────────────────────────────────────────────

/// The aggregated daily report: one row per level unit, 14 metric columns per
/// side, plus a Grand Total and an achievement %. [mode] is "plan" (plan only)
/// or "both" (side-by-side PLAN + ACHIEVEMENT).
class MisDailyPlanReportTable extends ConsumerWidget {
  const MisDailyPlanReportTable({
    super.key,
    required this.level,
    required this.date,
    required this.mode,
  });

  final String level;
  final String date;
  final String mode;

  bool get _both => mode == 'both';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planQ = DailyPlanReportQuery(date, 'plan');
    final achQ = DailyPlanReportQuery(date, 'achievement');
    final planAsync = ref.watch(misDailyPlanRowsProvider(planQ));
    final achAsync = _both
        ? ref.watch(misDailyPlanRowsProvider(achQ))
        : const AsyncValue<List<DailyPlanReportRow>>.data([]);

    final colLabel = _levelLabels[level] ?? 'Branch';
    final heading = _both ? 'Plan & Achievement Report' : 'Plan Report';

    if (planAsync.isLoading || achAsync.isLoading) {
      return const AppLoadingBlock(height: 220);
    }
    final err = planAsync.error ?? achAsync.error;
    if (err != null) {
      return AppErrorPanel(
        message: err.toString(),
        onRetry: () {
          ref.invalidate(misDailyPlanRowsProvider(planQ));
          if (_both) ref.invalidate(misDailyPlanRowsProvider(achQ));
        },
      );
    }

    final planRows = _buildRows(planAsync.value ?? const [], level);
    final achRows = _both
        ? _buildRows(achAsync.value ?? const [], level)
        : <_ReportRow>[];
    final achByName = {for (final r in achRows) r.name: r};

    final grandPlan = _ReportRow('Grand Total', _zero());
    final grandAch = _ReportRow('Grand Total', _zero());
    for (final r in planRows) {
      for (final c in _metrics) {
        grandPlan.m[c.key] = grandPlan.get(c.key) + r.get(c.key);
      }
    }
    for (final r in achRows) {
      for (final c in _metrics) {
        grandAch.m[c.key] = grandAch.get(c.key) + r.get(c.key);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$heading · $colLabel Level · ${misPrettyDate(date)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Download report',
              onPressed:
                  planRows.isEmpty ? null : () => _exportReport(context, ref),
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (planRows.isEmpty)
          GlassCard(
            child: Column(
              children: [
                const Icon(Icons.assessment_outlined,
                    size: 40, color: AppColors.muted),
                const SizedBox(height: 10),
                const Text(
                  'No plans for this date',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No branch has entered a daily plan for '
                  '${misPrettyDate(date)}. Ask branch managers to submit their '
                  'targets, or pick another date.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          )
        else ...[
          if (_both && achRows.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No achievements submitted for '
                      '${misPrettyDate(date)} yet.',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          _grid(colLabel, planRows, achByName, grandPlan, grandAch),
        ],
      ],
    );
  }

  // ── Grid ───────────────────────────────────────────────────────────────────
  // A pinned name column beside a horizontally-scrolling metric grid, both built
  // as Columns of identical row heights so nothing can drift out of sync.

  static const double _nameW = 118;
  static const double _cellW = 74;
  static const double _pctW = 62;
  static const double _bandH = 24;
  static const double _rowH = 38;

  double get _headerH => _bandH * (_both ? 3 : 2);

  Widget _grid(
    String colLabel,
    List<_ReportRow> rows,
    Map<String, _ReportRow> achByName,
    _ReportRow grandPlan,
    _ReportRow grandAch,
  ) {
    return GlassCard(
      padding: EdgeInsets.zero,
      shadow: AppShadows.soft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _nameW,
              child: Column(
                children: [
                  Container(
                    height: _headerH,
                    color: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      colLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  for (var i = 0; i < rows.length; i++)
                    _nameCell(rows[i].name,
                        background: i.isOdd
                            ? AppColors.surfaceAlt
                            : AppColors.surface),
                  _nameCell('Grand Total',
                      background: AppColors.surfaceAlt,
                      bold: true,
                      topBorder: true),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._headerBands(),
                    for (var i = 0; i < rows.length; i++)
                      _dataBand(
                        rows[i],
                        _both ? achByName[rows[i].name] : null,
                        i.isOdd ? AppColors.surfaceAlt : AppColors.surface,
                      ),
                    _dataBand(grandPlan, _both ? grandAch : null,
                        AppColors.surfaceAlt,
                        bold: true, topBorder: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameCell(
    String text, {
    required Color background,
    bool bold = false,
    bool topBorder = false,
  }) {
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: background,
        border: topBorder
            ? const Border(
                top: BorderSide(color: AppColors.hairline, width: 1.4))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }

  List<Widget> _headerBands() {
    final sideW = _metrics.length * _cellW;
    return [
      if (_both)
        Row(
          children: [
            _band('PLAN', sideW, AppColors.primary),
            _band('ACHIEVEMENT', sideW, MisAchColor.achievement),
            _band('', _pctW, AppColors.primary),
          ],
        ),
      Row(
        children: [
          for (var s = 0; s < (_both ? 2 : 1); s++)
            for (final g in _groups)
              _band(g.$1, g.$2 * _cellW, AppColors.primaryDark),
          _band('', _pctW, AppColors.primaryDark),
        ],
      ),
      Row(
        children: [
          for (var s = 0; s < (_both ? 2 : 1); s++)
            for (final c in _metrics) _band(c.header, _cellW, AppColors.primary),
          _band('Ach %', _pctW, AppColors.primary),
        ],
      ),
    ];
  }

  Widget _band(String text, double width, Color color, {double? height}) {
    return Container(
      width: width,
      height: height ?? _bandH,
      color: color,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _dataBand(
    _ReportRow plan,
    _ReportRow? ach,
    Color background, {
    bool bold = false,
    bool topBorder = false,
  }) {
    final pct = _both ? _rowPct(plan, ach) : null;
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: background,
        border: topBorder
            ? const Border(
                top: BorderSide(color: AppColors.hairline, width: 1.4))
            : null,
      ),
      child: Row(
        children: [
          for (final c in _metrics) _valueCell(_cellText(plan, c), bold),
          if (_both)
            for (final c in _metrics)
              _valueCell(ach == null ? '-' : _cellText(ach, c), bold),
          SizedBox(
            width: _pctW,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _pctColor(pct).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  pct == null ? '—' : '$pct%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _pctColor(pct),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueCell(String text, bool bold) {
    return SizedBox(
      width: _cellW,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: AppColors.inkSoft,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  /// Formatted .xlsx built server-side — mirrors the web module's
  /// `dailyPlanExport` (src/mis/gwm/api/dailyPlanApi.ts). One sheet per level
  /// the caller's own access allows (not just the on-screen [level]), and
  /// Plan-only vs Plan+Achievement decided by the server from whether
  /// achievement has actually been submitted for the date.
  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    try {
      final (bytes, suggestedName) =
          await ref.read(misRepositoryProvider).dailyPlanExportBytes(date);
      if (!context.mounted) return;
      await misSaveBytes(
        context,
        suggestedName ?? 'daily_${mode}_${level.toLowerCase()}_$date.xlsx',
        bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        noun: 'report',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Could not download the report: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// The achievement side's header tint — deliberately distinct from the plan
/// side so the two halves of the wide table stay tellable apart while scrolling.
class MisAchColor {
  MisAchColor._();
  static const achievement = Color(0xFF0F766E); // teal-700
}

