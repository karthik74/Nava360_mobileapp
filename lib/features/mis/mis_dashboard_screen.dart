// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Grow With Me — dashboard entry (route /mis).
//
//  Auto-logs into the GWM backend using the nava360 identity (emp id = the app
//  username, password derived NL13465 → NL@13465), then shows the NLPL Overview
//  "Month Highlights" dashboard. There is NO manual MIS login: if auto-login
//  fails or there is no nava360 identity, the gate navigates BACK (only a spinner
//  shows while the attempt is in flight). Mirrors the web MisModule.tsx gate.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'mis_auth.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

/// Route entry. Owns the MIS auth gate; renders the dashboard once signed in.
class MisScreen extends ConsumerStatefulWidget {
  const MisScreen({super.key});

  @override
  ConsumerState<MisScreen> createState() => _MisScreenState();
}

class _MisScreenState extends ConsumerState<MisScreen> {
  bool _triggered = false;
  bool _left = false; // guard so we only navigate back once

  @override
  void initState() {
    super.initState();
    // Kick off the silent auto-login after the first frame (once).
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLogin());
  }

  void _autoLogin() {
    if (_triggered) return;
    _triggered = true;
    final empId = ref.read(authUserProvider)?.username ?? '';
    if (empId.isEmpty) {
      // No nava360 identity to derive MIS credentials from → go back.
      _goBack();
      return;
    }
    ref.read(misAuthControllerProvider.notifier).ensureAutoLogin(empId);
  }

  /// Auto-login failed / unavailable → leave MIS. Never show a manual login.
  void _goBack() {
    if (_left) return;
    _left = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(misAuthControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('MIS · Grow With Me')),
      body: auth.when(
        loading: () => const _MisCenterLoader(label: 'Signing in to MIS…'),
        // Auto-login failed → bounce back, only a spinner in the meantime.
        error: (e, _) {
          _goBack();
          return const _MisCenterLoader(label: 'Signing in to MIS…');
        },
        data: (session) {
          if (session?.user == null) {
            _goBack();
            return const _MisCenterLoader(label: 'Signing in to MIS…');
          }
          return _MisDashboardBody(session: session!);
        },
      ),
    );
  }
}

class _MisCenterLoader extends StatelessWidget {
  const _MisCenterLoader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
        ],
      ),
    );
  }
}

// ── Dashboard body ──────────────────────────────────────────────────────────

class _MisDashboardBody extends ConsumerStatefulWidget {
  const _MisDashboardBody({required this.session});
  final MisSession session;

  @override
  ConsumerState<_MisDashboardBody> createState() => _MisDashboardBodyState();
}

class _MisDashboardBodyState extends ConsumerState<_MisDashboardBody> {
  int? _fy; // selected fiscal-year start; null ⇒ latest
  String? _left; // month key for column 1
  String? _right; // month key for column 2
  String? _chartKey; // selected row key for the trend chart
  Set<String> _chartMonths = {}; // which columns feed the chart; empty ⇒ all
  bool _bar = false; // false = line, true = bar

  static const _drill = MisDrill();

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(misOverviewProvider(_drill));
    final user = widget.session.user;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(misOverviewProvider(_drill)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, MediaQuery.of(context).padding.bottom + 24),
        children: [
          // Greeting
          Row(
            children: [
              Text('${_greeting()}, ',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted)),
              Flexible(
                child: Text(
                  user?.firstName ?? 'there',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [misTierLabel(widget.session.scope?.tier), user?.branch]
                .where((s) => s != null && s.isNotEmpty)
                .join(' · '),
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          // Quick nav to the MIS sub-dashboards.
          const _MisNavRow(),
          const SizedBox(height: 16),
          const AppPageHeader(
            title: 'NLPL Overview',
            subtitle: 'Month Highlights (Amount in Cr.)',
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => const AppLoadingBlock(height: 280),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(misOverviewProvider(_drill)),
            ),
            data: (table) => _content(table),
          ),
        ],
      ),
    );
  }

  Widget _content(OverviewTable table) {
    final allKeys = [...table.months]..sort();
    if (allKeys.isEmpty || table.rows.isEmpty) {
      return const AppEmptyState(
        icon: Icons.query_stats_rounded,
        message: 'No overview data available yet for your scope.',
      );
    }

    // Fiscal-year filter over the returned months.
    final fys = allKeys.map(misFyStart).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final activeFy = (_fy != null && fys.contains(_fy)) ? _fy! : fys.first;
    final displayKeys = allKeys.where((k) => misFyStart(k) == activeFy).toList();
    if (displayKeys.isEmpty) {
      return const AppEmptyState(
        icon: Icons.query_stats_rounded,
        message: 'No data for the selected fiscal year.',
      );
    }

    // Two-month comparison (phones are narrow — mirror the web mobile layout).
    final newest = displayKeys.last;
    final prevNewest =
        displayKeys.length > 1 ? displayKeys[displayKeys.length - 2] : newest;
    var left = (_left != null && displayKeys.contains(_left)) ? _left! : newest;
    var right =
        (_right != null && displayKeys.contains(_right)) ? _right! : prevNewest;

    // Chart row: the selected metric, else the first "strong" row, else row 0.
    final chartRow = table.rows.firstWhere(
      (r) => r.key == _chartKey,
      orElse: () => table.rows.firstWhere((r) => r.strong,
          orElse: () => table.rows.first),
    );
    final money = chartRow.type == 'cr';
    // Columns (months) that feed the chart. Empty selection ⇒ the whole FY;
    // stale keys (e.g. after an FY switch) are filtered out, falling back to all.
    final chartKeys = _chartMonths.isEmpty
        ? displayKeys
        : displayKeys.where(_chartMonths.contains).toList();
    final effectiveKeys = chartKeys.isEmpty ? displayKeys : chartKeys;
    final trend = <_Pt>[
      for (final k in effectiveKeys)
        _Pt(misMonthLabel(k), table.cell(k, chartRow.key)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter row: fiscal year + the two compared months.
        Row(
          children: [
            if (fys.length > 1) ...[
              Expanded(
                child: _LabeledDropdown<int>(
                  label: 'Fiscal Year',
                  value: activeFy,
                  items: [
                    for (final s in fys)
                      DropdownMenuItem(value: s, child: Text(misFyLabel(s))),
                  ],
                  onChanged: (v) => setState(() {
                    _fy = v;
                    _left = null;
                    _right = null;
                    _chartMonths = {}; // months differ per FY → reset to all
                  }),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: MisMonthPicker(
                label: 'Month 1',
                value: left,
                available: displayKeys,
                onChanged: (v) => setState(() {
                  _left = v;
                  if (v == right) _right = left; // keep the two distinct
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MisMonthPicker(
                label: 'Month 2',
                value: right,
                available: displayKeys,
                onChanged: (v) => setState(() {
                  _right = v;
                  if (v == left) _left = right;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Month Highlights table (Parameter | Month 1 | Month 2).
        _HighlightsTable(table: table, left: left, right: right),

        const SizedBox(height: 20),

        // Analytics — trend of the selected metric across the FY.
        Row(
          children: [
            const Text('Analytics',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const Spacer(),
            _ChartTypeToggle(
              bar: _bar,
              onChanged: (b) => setState(() => _bar = b),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LabeledDropdown<String>(
                label: 'Parameter',
                value: chartRow.key,
                items: [
                  for (final r in table.rows)
                    DropdownMenuItem(value: r.key, child: Text(r.label)),
                ],
                onChanged: (v) => setState(() => _chartKey = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MonthsMultiSelect(
                label: 'Months',
                all: displayKeys,
                selected: _chartMonths,
                onChanged: (sel) => setState(() {
                  // Full selection is stored as empty ⇒ "all".
                  _chartMonths =
                      sel.length == displayKeys.length ? <String>{} : sel;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${chartRow.label} — ${_bar ? 'by month' : 'trend'}',
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 200,
                child: _MisMetricChart(
                    points: trend, bar: _bar, money: money, type: chartRow.type),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Month Highlights table ──────────────────────────────────────────────────

class _HighlightsTable extends StatelessWidget {
  const _HighlightsTable({
    required this.table,
    required this.left,
    required this.right,
  });
  final OverviewTable table;
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          children: [
            // Header
            _Row(
              cells: ['Parameters', misMonthLabel(left), misMonthLabel(right)],
              header: true,
            ),
            for (var i = 0; i < table.rows.length; i++)
              _Row(
                cells: [
                  table.rows[i].label,
                  misCell(table.rows[i].type, table.cell(left, table.rows[i].key)),
                  misCell(
                      table.rows[i].type, table.cell(right, table.rows[i].key)),
                ],
                strong: table.rows[i].strong,
                zebra: i.isOdd,
                negatives: [
                  false,
                  (table.cell(left, table.rows[i].key) ?? 0) < 0,
                  (table.cell(right, table.rows[i].key) ?? 0) < 0,
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cells,
    this.header = false,
    this.strong = false,
    this.zebra = false,
    this.negatives = const [false, false, false],
  });
  final List<String> cells;
  final bool header;
  final bool strong;
  final bool zebra;
  final List<bool> negatives;

  @override
  Widget build(BuildContext context) {
    final bg = header
        ? AppColors.primary
        : (zebra ? AppColors.surfaceAlt : AppColors.surface);
    final labelColor = header ? Colors.white : AppColors.ink;
    final valueColor = header ? Colors.white : AppColors.inkSoft;

    Widget cell(String text, {required bool first, bool neg = false}) {
      return Expanded(
        flex: first ? 5 : 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Text(
            text,
            textAlign: first ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: header || strong ? FontWeight.w700 : FontWeight.w500,
              color: neg ? AppColors.danger : (first ? labelColor : valueColor),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: header
            ? null
            : const Border(
                top: BorderSide(color: AppColors.hairline, width: 0.5)),
      ),
      child: Row(
        children: [
          cell(cells[0], first: true),
          cell(cells[1], first: false, neg: negatives[1]),
          cell(cells[2], first: false, neg: negatives[2]),
        ],
      ),
    );
  }
}

// ── Small controls ──────────────────────────────────────────────────────────

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.muted)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.muted),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Multi-select of overview-table columns (months) that feed the chart. Styled
/// like [_LabeledDropdown]; opens a checklist sheet. An empty [selected] set
/// means "all months".
class _MonthsMultiSelect extends StatelessWidget {
  const _MonthsMultiSelect({
    required this.label,
    required this.all,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final List<String> all;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final isAll = selected.isEmpty || selected.length == all.length;
    final summary =
        isAll ? 'All (${all.length})' : '${selected.length} of ${all.length}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.muted)),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () => _open(context),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context) {
    // Start from the effective set: empty ⇒ everything is currently on.
    final working = <String>{...(selected.isEmpty ? all : selected)};
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          void apply() {
            // Never let the chart go empty — no selection means "all".
            onChanged(working.isEmpty ? <String>{} : working);
            Navigator.pop(sheetCtx);
          }

          final allOn = working.length == all.length;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Chart months',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink)),
                      ),
                      TextButton(
                        onPressed: () => setSheet(() {
                          if (allOn) {
                            working
                              ..clear()
                              ..add(all.last); // keep at least one
                          } else {
                            working
                              ..clear()
                              ..addAll(all);
                          }
                        }),
                        child: Text(allOn ? 'Clear' : 'Select all'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final k in all)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.primary,
                          value: working.contains(k),
                          title: Text(misMonthLabel(k),
                              style: const TextStyle(
                                  fontSize: 13.5, color: AppColors.ink)),
                          onChanged: (on) => setSheet(() {
                            if (on == true) {
                              working.add(k);
                            } else if (working.length > 1) {
                              working.remove(k); // keep at least one selected
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 8, 20, 12 + MediaQuery.of(sheetCtx).padding.bottom),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: apply,
                      child: const Text('Apply'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChartTypeToggle extends StatelessWidget {
  const _ChartTypeToggle({required this.bar, required this.onChanged});
  final bool bar;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool active, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.muted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Line', !bar, () => onChanged(false)),
          seg('Bar', bar, () => onChanged(true)),
        ],
      ),
    );
  }
}

// ── Chart ───────────────────────────────────────────────────────────────────

/// Quick-nav tiles to the MIS sub-dashboards.
class _MisNavRow extends StatelessWidget {
  const _MisNavRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Collection', Icons.payments_rounded, '/mis/collection', AppColors.success),
      ('Portfolio', Icons.pie_chart_rounded, '/mis/portfolio', AppColors.primary),
      ('Disbursement', Icons.account_balance_rounded, '/mis/disbursement',
          AppColors.warning),
      ('Hourly', Icons.schedule_rounded, '/mis/hourly', AppColors.accent),
      ('Comparison', Icons.compare_arrows_rounded, '/mis/comparison',
          AppColors.pink),
      ('Analytical', Icons.query_stats_rounded, '/mis/analytical',
          AppColors.danger),
      ('Daily Plan', Icons.edit_note_rounded, '/mis/daily-plan',
          AppColors.primary),
      ('Directory', Icons.contacts_rounded, '/mis/employees', AppColors.accent),
      ('Locations', Icons.map_rounded, '/mis/locations', AppColors.success),
      ('Feedback', Icons.forum_rounded, '/mis/feedback', AppColors.success),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final w = (c.maxWidth - gap * 2) / 3;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final it in items)
            SizedBox(
              width: w,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push(it.$3),
                  child: GlassCard(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                    shadow: AppShadows.soft,
                    child: Column(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: it.$4.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: it.$4.withOpacity(0.22)),
                          ),
                          child: Icon(it.$2, color: it.$4, size: 20),
                        ),
                        const SizedBox(height: 8),
                        Text(it.$1,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _Pt {
  final String label;
  final double value;
  _Pt(this.label, double? v) : value = (v == null || v.isNaN) ? 0 : v;
}

class _MisMetricChart extends StatelessWidget {
  const _MisMetricChart({
    required this.points,
    required this.bar,
    required this.money,
    required this.type,
  });
  final List<_Pt> points;
  final bool bar;
  final bool money;
  final String type;

  String _axis(double v) {
    if (type == 'pct') return '${v.toStringAsFixed(0)}%';
    if (v.abs() >= 1000) return misNum(v.round());
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Text('No data', style: TextStyle(color: AppColors.muted)),
      );
    }
    final maxV = points.map((p) => p.value).fold<double>(0, (a, b) => b > a ? b : a);
    final minV = points.map((p) => p.value).fold<double>(0, (a, b) => b < a ? b : a);
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    final bottom = minV < 0 ? minV * 1.15 : 0.0;

    final bottomTitles = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        getTitlesWidget: (value, meta) {
          final i = value.toInt();
          if (i < 0 || i >= points.length) return const SizedBox.shrink();
          // Thin the labels if crowded.
          final step = (points.length / 6).ceil();
          if (points.length > 7 && i % step != 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(points[i].label,
                style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
          );
        },
      ),
    );
    final leftTitles = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 40,
        getTitlesWidget: (value, meta) => Text(_axis(value),
            style: const TextStyle(fontSize: 9, color: AppColors.muted)),
      ),
    );
    final grid = FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: top / 4 <= 0 ? null : top / 4,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: AppColors.hairline, strokeWidth: 0.6),
    );
    final border = FlBorderData(show: false);

    if (bar) {
      return BarChart(
        BarChartData(
          maxY: top,
          minY: bottom,
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: points[i].value,
                  color: AppColors.primary,
                  width: points.length > 8 ? 8 : 14,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3)),
                ),
              ]),
          ],
          titlesData: FlTitlesData(
            bottomTitles: bottomTitles,
            leftTitles: leftTitles,
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
          ),
          gridData: grid,
          borderData: border,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                money
                    ? misRupees(rod.toY)
                    : (type == 'pct'
                        ? '${rod.toY.toStringAsFixed(2)}%'
                        : misNum(rod.toY)),
                const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5),
              ),
            ),
          ),
        ),
      );
    }

    return LineChart(
      LineChartData(
        maxY: top,
        minY: bottom,
        titlesData: FlTitlesData(
          bottomTitles: bottomTitles,
          leftTitles: leftTitles,
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
        gridData: grid,
        borderData: border,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      money
                          ? misRupees(s.y)
                          : (type == 'pct'
                              ? '${s.y.toStringAsFixed(2)}%'
                              : misNum(s.y)),
                      const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.primary,
            barWidth: 2.6,
            dotData: FlDotData(
              show: points.length <= 12,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.primary,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}
