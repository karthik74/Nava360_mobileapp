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

  // Cascading scope filter (Region → Division → Area → Branch). The `id` loads
  // the next level; the NAMES scope the overview via MisDrill.
  HierOption? _region, _division, _area, _branch;

  MisDrill get _drill => MisDrill(
        region: _region?.name,
        division: _division?.name,
        area: _area?.name,
        branch: _branch?.name,
      );

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
    // Show the user's actual designation/role from the login response. The
    // scope `tier` is only a data-access level (e.g. "all"), so labelling it
    // "CEO / Director" mislabels everyone who can see org-wide data — fall back
    // to it only when the response carries no designation or role.
    final roleLabel = (user?.designation?.trim().isNotEmpty ?? false)
        ? user!.designation!.trim()
        : (user?.role?.trim().isNotEmpty ?? false)
            ? user!.role!.trim()
            : misTierLabel(widget.session.scope?.tier);

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
            [roleLabel, user?.branch]
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
          _scopeFilter(),
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

  // ── Cascading scope filter (Region → Division → Area → Branch) ───────────────

  Widget _scopeFilter() {
    final regions = ref.watch(misRegionsProvider);
    final divisions = _region == null
        ? const AsyncValue<List<HierOption>>.data([])
        : ref.watch(misDivisionsProvider(_region!.id));
    final areas = _division == null
        ? const AsyncValue<List<HierOption>>.data([])
        : ref.watch(misAreasProvider(_division!.id));
    final branches = _area == null
        ? const AsyncValue<List<HierOption>>.data([])
        : ref.watch(misBranchesProvider(_area!.id));

    final cells = <Widget>[
      _hierDropdown('Region', _region, regions, (o) {
        setState(() {
          _region = o;
          _division = _area = _branch = null;
        });
      }),
      if (_region != null)
        _hierDropdown('Division', _division, divisions, (o) {
          setState(() {
            _division = o;
            _area = _branch = null;
          });
        }),
      if (_division != null)
        _hierDropdown('Area', _area, areas, (o) {
          setState(() {
            _area = o;
            _branch = null;
          });
        }),
      if (_area != null)
        _hierDropdown('Branch', _branch, branches, (o) {
          setState(() => _branch = o);
        }),
    ];

    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final w = (c.maxWidth - gap) / 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final cell in cells) SizedBox(width: w, child: cell)],
          ),
          if (_region != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() {
                _region = _division = _area = _branch = null;
              }),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('Reset filter',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _hierDropdown(String label, HierOption? value,
      AsyncValue<List<HierOption>> opts, ValueChanged<HierOption?> onChanged) {
    final list = opts.asData?.value ?? const <HierOption>[];
    final ids = list.map((o) => o.id).toSet();
    final current = (value != null && ids.contains(value.id)) ? value.id : '';
    return MisDropdown<String>(
      label: label,
      value: current,
      items: [
        DropdownMenuItem(value: '', child: Text('All ${label.toLowerCase()}s')),
        for (final o in list)
          DropdownMenuItem(
              value: o.id,
              child: Text(o.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (id) {
        if (id == null || id.isEmpty) {
          onChanged(null);
          return;
        }
        final match = list.where((o) => o.id == id).toList();
        onChanged(match.isEmpty ? null : match.first);
      },
    );
  }
}

// ── Month Highlights table ──────────────────────────────────────────────────

/// A category the overview rows are grouped under, mirroring the printed
/// "Month Highlights" report: each group has its own accent color that tints
/// the group header, the row's left stripe, and its headline values.
class _MisGroup {
  const _MisGroup(this.title, this.color, this.keys);
  final String title;
  final Color color;
  final Set<String> keys;
}

class _HighlightsTable extends StatelessWidget {
  const _HighlightsTable({
    required this.table,
    required this.left,
    required this.right,
  });
  final OverviewTable table;
  final String left;
  final String right;

  // Row-key → category, in report order. Keys come verbatim from `/overview`.
  static const List<_MisGroup> _groups = [
    _MisGroup('NETWORK OVERVIEW', Color(0xFF0F9AA0),
        {'state', 'branch', 'foCount', 'totalStaff'}),
    _MisGroup('DISBURSEMENT & ACCOUNTS', Color(0xFF2563EB),
        {'disbAcc', 'disbAmt', 'activeAcc'}),
    _MisGroup('COLLECTION PERFORMANCE', Color(0xFF7C3AED), {
      'totalPos',
      'incrPos',
      'regCollPct',
      'ftodAcc',
      'ftodPar',
      'total1Par',
      'incr1Par',
    }),
    _MisGroup('NPA OVERVIEW', Color(0xFFEA580C),
        {'totalNpa', 'incrNpa', 'npaCollAcc', 'npaCollAmt'}),
    _MisGroup('PRODUCTIVITY METRICS', Color(0xFF16A34A), {
      'borrowersPerBranch',
      'posPerBranch',
      'borrowersPerFo',
      'posPerFo',
      'avgLoanDisb',
      'avgLoanOs',
    }),
  ];
  static const _MisGroup _other = _MisGroup('OTHER', AppColors.muted, {});

  _MisGroup _groupFor(String key) {
    for (final g in _groups) {
      if (g.keys.contains(key)) return g;
    }
    return _other;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _Row(
        cells: ['Parameters', misMonthLabel(left), misMonthLabel(right)],
        header: true,
      ),
    ];
    _MisGroup? current;
    for (final row in table.rows) {
      final group = _groupFor(row.key);
      if (group != current) {
        children.add(_GroupHeader(group: group));
        current = group;
      }
      final lv = table.cell(left, row.key);
      final rv = table.cell(right, row.key);
      children.add(_Row(
        cells: [row.label, misCell(row.type, lv), misCell(row.type, rv)],
        // Only the grouping is colored (header band + left stripe); the row
        // text stays neutral and unbolded.
        accent: group.color,
      ));
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(children: children),
      ),
    );
  }
}

/// Colored band that introduces a category of rows.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});
  final _MisGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 8, 12, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            group.color.withOpacity(0.12), AppColors.surface),
        border: Border(
          top: const BorderSide(color: AppColors.hairline, width: 0.6),
          left: BorderSide(color: group.color, width: 3),
        ),
      ),
      child: Text(
        group.title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: group.color,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cells,
    this.header = false,
    this.accent,
  });
  final List<String> cells;
  final bool header;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final bg = header ? AppColors.primary : AppColors.surface;
    final labelColor = header ? Colors.white : AppColors.ink;
    final valueColor = header ? Colors.white : AppColors.inkSoft;
    final divider = header ? Colors.white24 : AppColors.hairline;

    Widget cell(String text, {required bool first}) {
      return Expanded(
        flex: first ? 5 : 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: first
                ? null
                : Border(left: BorderSide(color: divider, width: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Text(
              text,
              textAlign: first ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                // No bold on data rows; the header keeps its weight.
                fontWeight: header ? FontWeight.w700 : FontWeight.w500,
                // Neutral text only — the grouping alone carries color.
                color: first ? labelColor : valueColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
            : Border(
                top: const BorderSide(color: AppColors.hairline, width: 0.6),
                left: BorderSide(color: accent ?? Colors.transparent, width: 3),
              ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell(cells[0], first: true),
            cell(cells[1], first: false),
            cell(cells[2], first: false),
          ],
        ),
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
    final items = [
      ('Portfolio', Icons.pie_chart_rounded, '/mis/portfolio', AppColors.primary),
      ('Collection', Icons.payments_rounded, '/mis/collection', AppColors.success),
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
      // Four tiles per row.
      final w = (c.maxWidth - gap * 3) / 4;
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
                  splashColor: it.$4.withOpacity(0.10),
                  highlightColor: it.$4.withOpacity(0.05),
                  child: GlassCard(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    shadow: AppShadows.soft,
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                it.$4,
                                Color.lerp(it.$4, Colors.white, 0.28)!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: it.$4.withOpacity(0.32),
                                blurRadius: 9,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(it.$2, color: Colors.white, size: 20),
                        ),
                        const SizedBox(height: 8),
                        Text(it.$1,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.15,
                                color: AppColors.inkSoft)),
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

  // Value label shown ON the chart (always visible, and on hover). Matches the
  // Month-Highlights table's units: a `cr` metric is ALREADY in Crore, so it
  // must never go through misRupees (which would misread 1039.60 as ₹1.0K).
  String _fmt(double v) {
    if (type == 'pct') return '${v.toStringAsFixed(2)}%';
    if (money) return v.toStringAsFixed(2); // Crore — mirrors the table cell
    return misNum(v.round());
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Text('No data', style: TextStyle(color: AppColors.muted)),
      );
    }
    final values = points.map((p) => p.value).toList();
    final dataMax = values.reduce((a, b) => a > b ? a : b);
    final dataMin = values.reduce((a, b) => a < b ? a : b);
    final span = dataMax - dataMin;

    // Y-range. Bars keep a 0 baseline (bar heights must stay proportional).
    // Lines zoom to the data band when values are positive and clustered far
    // from 0, so small month-to-month moves are visible instead of a flat line.
    double top, bottom;
    if (!bar && dataMin > 0 && span > 0 && dataMin > span) {
      final pad = span * 0.35;
      top = dataMax + pad;
      bottom = dataMin - pad;
    } else {
      top = dataMax <= 0 ? 1.0 : dataMax * 1.18;
      bottom = dataMin < 0 ? dataMin * 1.18 : 0.0;
    }
    final range = (top - bottom) <= 0 ? 1.0 : top - bottom;
    // Value-label sizing shrinks as months pile up so the pills never merge.
    final dense = points.length > 6;
    final veryDense = points.length > 9;
    final labelFont = veryDense ? 8.5 : (dense ? 9.5 : 11.0);
    final labelStyle = TextStyle(
        color: Colors.white, fontWeight: FontWeight.w700, fontSize: labelFont);

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
      // Vertical guides (one per month) only on the line chart, so 12 months
      // stay distinguishable; bars already read as discrete columns.
      drawVerticalLine: !bar,
      verticalInterval: 1,
      horizontalInterval: range / 4,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: AppColors.hairline, strokeWidth: 0.6),
      getDrawingVerticalLine: (_) =>
          const FlLine(color: AppColors.hairline, strokeWidth: 0.5),
    );
    final border = FlBorderData(show: false);

    if (bar) {
      return BarChart(
        BarChartData(
          maxY: top,
          minY: bottom,
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                // Force the value label to render without a hover.
                showingTooltipIndicators: const [0],
                barRods: [
                  BarChartRodData(
                    toY: points[i].value,
                    color: AppColors.primary,
                    width: points.length > 8 ? 8 : 14,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              ),
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
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.primary,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              tooltipMargin: 2,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              getTooltipItem: (group, _, rod, __) =>
                  BarTooltipItem(_fmt(rod.toY), labelStyle),
            ),
          ),
        ),
      );
    }

    final lineBar = LineChartBarData(
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
    );

    // fl_chart 0.68 does not reliably paint permanent tooltips on a line, so
    // draw the value labels ourselves as pills positioned over each point —
    // giving the line the always-visible labels the Bar chart already shows.
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        const leftPad = 40.0; // == leftTitles.reservedSize
        const bottomPad = 24.0; // == bottomTitles.reservedSize
        final plotW = (w - leftPad).clamp(1.0, double.infinity);
        final plotH = (h - bottomPad).clamp(1.0, double.infinity);
        final n = points.length;
        final boxW = veryDense ? 54.0 : (dense ? 66.0 : 100.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: LineChart(
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
                  lineBarsData: [lineBar],
                  lineTouchData: const LineTouchData(enabled: false),
                ),
              ),
            ),
            for (var i = 0; i < n; i++)
              _pointLabel(
                i: i,
                n: n,
                leftPad: leftPad,
                plotW: plotW,
                plotH: plotH,
                width: w,
                boxW: boxW,
                range: range,
                bottom: bottom,
                labelStyle: labelStyle,
                stagger: dense,
              ),
          ],
        );
      },
    );
  }

  // A permanently-visible value pill centred over line point [i]. Mirrors the
  // Bar chart's always-on labels, since fl_chart 0.68 won't paint permanent
  // line tooltips.
  Widget _pointLabel({
    required int i,
    required int n,
    required double leftPad,
    required double plotW,
    required double plotH,
    required double width,
    required double boxW,
    required double range,
    required double bottom,
    required TextStyle labelStyle,
    required bool stagger,
  }) {
    final xFrac = n == 1 ? 0.5 : i / (n - 1);
    final px = leftPad + xFrac * plotW;
    final yFrac = ((points[i].value - bottom) / range).clamp(0.0, 1.0);
    final py = (1 - yFrac) * plotH;
    // When crowded, lift alternate labels to a second tier so neighbouring
    // pills sit at different heights and never overlap horizontally.
    final tier = stagger ? (i % 2) : 0;
    final left =
        (px - boxW / 2).clamp(0.0, (width - boxW).clamp(0.0, double.infinity));
    final top = (py - 28 - tier * 20).clamp(0.0, plotH);
    return Positioned(
      left: left,
      top: top,
      width: boxW,
      height: 22,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: stagger ? 4 : 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(_fmt(points[i].value), maxLines: 1, style: labelStyle),
        ),
      ),
    );
  }
}
