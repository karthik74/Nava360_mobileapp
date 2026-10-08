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

import 'package:flutter/services.dart';

import '../../core/pro_ui.dart';
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ProIconWell(
                      icon: Icons.assessment_rounded,
                      color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: ProSectionHeader(
                      title: 'Custom report builder',
                      subtitle: 'Select date & level to generate reports',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const _FieldLabel('1. Select date'),
              const SizedBox(height: 6),
              Row(
                children: [
                  _StepButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Previous day',
                    onTap: () =>
                        setState(() => _date = _shiftIso(_date, -1)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        side: const BorderSide(color: Color(0xFFDBE3E5)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _pickDate,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.event_rounded,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  misPrettyDate(_date),
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: AppColors.muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StepButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Next day',
                    onTap: () =>
                        setState(() => _date = _shiftIso(_date, 1)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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

              const SizedBox(height: 18),
              const _FieldLabel('2. Report level'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lv in levels)
                    _Pill(
                      label: '${_levelLabels[lv]} level',
                      active: _level == lv,
                      onTap: () => setState(() => _level = lv),
                    ),
                ],
              ),

              const SizedBox(height: 18),
              if (misCanSeePending(widget.role)) ...[
                OutlinedButton.icon(
                  onPressed: _openPending,
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: const Text('Branches pending'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9A5B00),
                    side: const BorderSide(color: Color(0xFFF2D19B)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: () => setState(() => _mode = 'plan'),
                icon: const Icon(Icons.assignment_rounded, size: 18),
                label: const Text('Generate plan report'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => setState(() => _mode = 'both'),
                icon: const Icon(Icons.description_rounded, size: 18),
                label: const Text('Plan & achievement'),
              ),
            ],
          ),
        ),
        if (_mode != null) ...[
          const SizedBox(height: 22),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PendingBranchesSheet(date: _date),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppText.label);
}

/// 42px hairline square for previous / next day.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFDBE3E5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 46,
            child: Icon(icon, size: 22, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
              color: active ? AppColors.ink : const Color(0xFFDBE3E5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? Colors.white : AppColors.inkSoft,
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
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFC6D3D6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Branches pending',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          '${misPrettyDate(widget.date)} · $label',
                          style: AppText.caption,
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
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
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
                        padding: EdgeInsets.all(20),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ProEmpty(
                            icon: Icons.celebration_rounded,
                            title: 'All caught up',
                            message:
                                'All branches have uploaded for this date.',
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        itemCount: branches.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 46,
                            color: AppColors.hairlineSoft),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          const ProIconWell(
            icon: Icons.storefront_outlined,
            color: Color(0xFF9A5B00),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ${b.branchName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                if (b.crumb.isNotEmpty)
                  Text(b.crumb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption),
                Text(b.bmName ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkSoft)),
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
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontFeatures: [FontFeature.tabularFigures()])),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.success,
                backgroundColor: AppColors.successTint,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: const StadiumBorder(),
              ),
            ),
        ],
      ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(
          title: heading,
          subtitle: '$colLabel level · ${misPrettyDate(date)}',
          trailing: IconButton(
            tooltip: 'Download report',
            onPressed:
                planRows.isEmpty ? null : () => _exportReport(context, ref),
            icon: const Icon(Icons.download_rounded),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        if (planRows.isEmpty)
          ProEmpty(
            icon: Icons.assessment_outlined,
            title: 'No plans for this date',
            message: 'No branch has entered a daily plan for '
                '${misPrettyDate(date)}. Ask branch managers to submit their '
                'targets, or pick another date.',
          )
        else ...[
          if (_both && achRows.isEmpty) ...[
            ProNote(
              'No achievements submitted for ${misPrettyDate(date)} yet.',
              tone: ProNoteTone.warn,
            ),
            const SizedBox(height: 12),
          ],
          _grid(colLabel, planRows, achByName, grandPlan, grandAch),
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 8, 2, 0),
            child: Text(
              'Swipe the table sideways for every column. Amounts are in crores.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
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
  static const double _bandH = 26;
  static const double _rowH = 42;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _nameW,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                children: [
                  Container(
                    height: _headerH,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceAlt,
                      border: Border(
                          bottom: BorderSide(color: AppColors.hairline)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        colLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < rows.length; i++)
                    _nameCell(rows[i].name, background: AppColors.surface),
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
                        AppColors.surface,
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
            ? const Border(top: BorderSide(color: AppColors.hairline))
            : const Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
    );
  }

  List<Widget> _headerBands() {
    final sideW = _metrics.length * _cellW;
    final plan = AppColors.primary;
    const ach = MisAchColor.achievement;
    return [
      if (_both)
        Row(
          children: [
            _band('Plan', sideW,
                background: plan.withValues(alpha: 0.08),
                color: plan,
                size: 11.5),
            _band('Achievement', sideW,
                background: ach.withValues(alpha: 0.09),
                color: ach,
                size: 11.5),
            _band('', _pctW),
          ],
        ),
      Row(
        children: [
          for (var s = 0; s < (_both ? 2 : 1); s++)
            for (final g in _groups)
              _band(g.$1, g.$2 * _cellW, color: AppColors.inkSoft),
          _band('', _pctW),
        ],
      ),
      Row(
        children: [
          for (var s = 0; s < (_both ? 2 : 1); s++)
            for (final c in _metrics) _band(c.header, _cellW),
          _band('Ach %', _pctW, last: true),
        ],
      ),
    ];
  }

  Widget _band(
    String text,
    double width, {
    Color background = AppColors.surfaceAlt,
    Color color = AppColors.muted,
    double size = 10.5,
    bool last = false,
  }) {
    return Container(
      width: width,
      height: _bandH,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          bottom: BorderSide(
              color: last ? AppColors.hairline : AppColors.hairlineSoft),
          right: const BorderSide(color: AppColors.hairlineSoft),
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
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
            ? const Border(top: BorderSide(color: AppColors.hairline))
            : const Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _pctColor(pct),
                    fontFeatures: const [FontFeature.tabularFigures()],
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
              fontSize: 11.5,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
              color: bold ? AppColors.ink : AppColors.inkSoft,
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
  static const achievement = Color(0xFF1D7A3E); // success green
}

