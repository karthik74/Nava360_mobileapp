// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Grow With Me — dashboard entry (route /mis).
//
//  Auto-logs into the GWM backend using the nava360 identity (emp id = the app
//  username, password derived XY12345 → XY@12345), then shows the NLPL Overview
//  "Month Highlights" dashboard. There is NO manual MIS login: if auto-login
//  fails or there is no nava360 identity, the gate navigates BACK (only a spinner
//  shows while the attempt is in flight). Mirrors the web MisModule.tsx gate.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'mis_auth.dart';
import 'mis_branch_matrix.dart';
import 'mis_charts.dart';
import 'mis_export.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

const _products = [
  (null, 'All'),
  ('igl', 'IGL'),
  ('fig', 'FIG'),
  ('il', 'IL'),
];

/// Route entry. Owns the MIS auth gate; renders the dashboard once signed in.
class MisScreen extends ConsumerStatefulWidget {
  const MisScreen({super.key});

  @override
  ConsumerState<MisScreen> createState() => _MisScreenState();
}

class _MisScreenState extends ConsumerState<MisScreen> {
  bool _triggered = false;
  bool _left = false; // guard so we only navigate back once

  /// True once THIS screen's auto-login attempt has fully completed. Until
  /// then a stale error / signed-out state from an earlier attempt (e.g. a
  /// network blip during the app-root eager login) must NOT bounce the user —
  /// that was the "MIS sometimes doesn't open" bug: the gate navigated back on
  /// the leftover state before the fresh attempt ever ran.
  bool _attemptFinished = false;

  @override
  void initState() {
    super.initState();
    // Kick off the silent auto-login after the first frame (once).
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLogin());
  }

  Future<void> _autoLogin() async {
    if (_triggered) return;
    _triggered = true;
    final identity = ref.read(authUserProvider);
    // The emp id comes from the nava360 login response, normalised — the raw
    // username can be an email or a lowercased code (see misEmpIdFromIdentity).
    final empId = misEmpIdFromIdentity(
      username: identity?.username,
      email: identity?.email,
    );
    if (empId.isEmpty) {
      // No nava360 identity to derive MIS credentials from → go back.
      _goBack();
      return;
    }
    // Awaits the restore + retries inside; completes with a session or a
    // final error.
    await ref.read(misAuthControllerProvider.notifier).ensureAutoLogin(empId);
    if (!mounted) return;
    setState(() => _attemptFinished = true);
    if (ref.read(misSessionProvider)?.user == null) _goBack();
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
        // Bounce only after THIS screen's attempt (with its retries) is done —
        // a stale error from an earlier background attempt keeps the spinner.
        error: (e, _) {
          if (_attemptFinished) _goBack();
          return const _MisCenterLoader(label: 'Signing in to MIS…');
        },
        data: (session) {
          if (session?.user == null) {
            if (_attemptFinished) _goBack();
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
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        ],
      ),
    );
  }
}

// ── Dashboard body ──────────────────────────────────────────────────────────

/// The overview's resolved period: fiscal year + the two compared months.
class _OverviewView {
  const _OverviewView({
    required this.fys,
    required this.activeFy,
    required this.displayKeys,
    required this.left,
    required this.right,
  });
  final List<int> fys;
  final int activeFy;
  final List<String> displayKeys;
  final String left;
  final String right;
}

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
  String? _product; // null = All; else 'igl' | 'fig' | 'il'

  MisDrill get _drill => MisDrill(
        region: _region?.name,
        division: _division?.name,
        area: _area?.name,
        branch: _branch?.name,
        product: _product,
      );

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Fiscal-year filter over the returned months + the two-month comparison
  /// (phones are narrow — mirror the web mobile layout). Null when there is
  /// nothing to show.
  _OverviewView? _resolve(OverviewTable table) {
    final allKeys = [...table.months]..sort();
    if (allKeys.isEmpty || table.rows.isEmpty) return null;
    final fys = allKeys.map(misFyStart).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final activeFy = (_fy != null && fys.contains(_fy)) ? _fy! : fys.first;
    final displayKeys = allKeys.where((k) => misFyStart(k) == activeFy).toList();
    if (displayKeys.isEmpty) return null;
    final newest = displayKeys.last;
    final prevNewest =
        displayKeys.length > 1 ? displayKeys[displayKeys.length - 2] : newest;
    final left = (_left != null && displayKeys.contains(_left)) ? _left! : newest;
    final right =
        (_right != null && displayKeys.contains(_right)) ? _right! : prevNewest;
    return _OverviewView(
      fys: fys,
      activeFy: activeFy,
      displayKeys: displayKeys,
      left: left,
      right: right,
    );
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

    final table = async.valueOrNull;
    final view = table == null ? null : _resolve(table);

    return ProPage(
      onRefresh: () async => ref.invalidate(misOverviewProvider(_drill)),
      hero: _hero(user, roleLabel, table, view),
      children: [
        // Quick nav to the MIS sub-dashboards.
        const _MisNavRow(),
        _overviewCard(view),
        ...async.when(
          loading: () => const [AppLoadingBlock(height: 280)],
          error: (e, _) => [
            AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(misOverviewProvider(_drill)),
            ),
          ],
          data: (table) => _content(table),
        ),
      ],
    );
  }

  // ── Hero: greeting, product switch, headline figures ─────────────────────────

  Widget _hero(MisUser? user, String roleLabel, OverviewTable? table,
      _OverviewView? view) {
    OverviewRow? rowFor(String key) {
      if (table == null) return null;
      for (final r in table.rows) {
        if (r.key == key) return r;
      }
      return null;
    }

    // Headline figures straight from the Month Highlights table, for Month 1.
    ProStat stat(String key, String label, String sub, Color dot) {
      final row = rowFor(key);
      final value = (table == null || view == null || row == null)
          ? '—'
          : misCell(row.type, table.cell(view.left, key));
      return ProStat(label: label, value: value, sub: sub, dot: dot);
    }

    final productIdx = _products.indexWhere((p) => p.$1 == _product);

    return ProHero(
      title: 'MIS dashboard',
      subtitle: [
        '${_greeting()}, ${user?.firstName ?? 'there'}',
        roleLabel,
        user?.branch,
      ].where((s) => s != null && s.isNotEmpty).join(' · '),
      actions: [
        ProHeroIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh figures',
          onTap: () => ref.invalidate(misOverviewProvider(_drill)),
        ),
      ],
      children: [
        ProHeroSegmented(
          labels: [for (final p in _products) p.$2],
          selected: productIdx < 0 ? 0 : productIdx,
          onChanged: (i) => setState(() => _product = _products[i].$1),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroKicker(
              left: view != null
                  ? '${misMonthLabel(view.left)} at a glance'
                  : 'At a glance',
              right: _scopeLabel,
            ),
            const SizedBox(height: 8),
            ProHeroStats(stats: [
              stat('totalPos', 'Total POS', '₹ Cr',
                  Color.lerp(AppColors.primary, Colors.white, 0.45)!),
              stat('regCollPct', 'Regular coll.', 'of demand', AppColors.live),
              stat('disbAmt', 'Disbursed', '₹ Cr', const Color(0xFFF2B347)),
            ]),
          ],
        ),
      ],
    );
  }

  // ── Overview card: scope filter + period ─────────────────────────────────────

  Widget _overviewCard(_OverviewView? view) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: 'NLPL overview',
            subtitle: 'Month highlights · amounts in ₹ Cr',
            trailing: _region == null
                ? null
                : TextButton.icon(
                    onPressed: () => setState(() {
                      _region = _division = _area = _branch = null;
                    }),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Reset filter'),
                  ),
          ),
          const SizedBox(height: 12),
          _scopeFilter(),
          if (view != null) ...[
            const SizedBox(height: 8),
            // Fiscal year + the two compared months.
            if (view.fys.length > 1) ...[
              MisDropdown<int>(
                label: 'Fiscal year',
                value: view.activeFy,
                items: [
                  for (final s in view.fys)
                    DropdownMenuItem(value: s, child: Text(misFyLabel(s))),
                ],
                onChanged: (v) => setState(() {
                  _fy = v;
                  _left = null;
                  _right = null;
                  _chartMonths = {}; // months differ per FY → reset to all
                }),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: MisMonthPicker(
                    label: 'Month 1',
                    value: view.left,
                    available: view.displayKeys,
                    onChanged: (v) => setState(() {
                      _left = v;
                      if (v == view.right) {
                        _right = view.left; // keep the two distinct
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MisMonthPicker(
                    label: 'Month 2',
                    value: view.right,
                    available: view.displayKeys,
                    onChanged: (v) => setState(() {
                      _right = v;
                      if (v == view.left) _left = view.right;
                    }),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _content(OverviewTable table) {
    final allKeys = [...table.months]..sort();
    if (allKeys.isEmpty || table.rows.isEmpty) {
      return const [
        AppEmptyState(
          icon: Icons.query_stats_rounded,
          message: 'No overview data available yet for your scope.',
        ),
      ];
    }
    final view = _resolve(table);
    if (view == null) {
      return const [
        AppEmptyState(
          icon: Icons.query_stats_rounded,
          message: 'No data for the selected fiscal year.',
        ),
      ];
    }
    final activeFy = view.activeFy;
    final displayKeys = view.displayKeys;
    final left = view.left;
    final right = view.right;

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
    final fullAccess = widget.session.scope?.fullAccess ?? false;

    return [
      // The table renders only the two compared columns; the export is the
      // full picture — every month of an FY the user ticks.
      GlassCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Month highlights',
                              style: AppText.section),
                          Text(
                            '${misMonthLabel(left)} against ${misMonthLabel(right)}',
                            style: AppText.caption.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openExport(table, allKeys, activeFy),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text('Export'),
                    ),
                  ],
                ),
              ),
              // Month Highlights table (Parameter | Month 1 | Month 2).
              _HighlightsTable(table: table, left: left, right: right),
            ],
          ),
        ),
      ),

      // Analytics — trend of the selected metric across the FY.
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(
              title: 'Analytics',
              trailing: _ChartTypeToggle(
                bar: _bar,
                onChanged: (b) => setState(() => _bar = b),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MisDropdown<String>(
                    label: 'Parameter',
                    value: chartRow.key,
                    items: [
                      for (final r in table.rows)
                        DropdownMenuItem(value: r.key, child: Text(r.label)),
                    ],
                    onChanged: (v) => setState(() => _chartKey = v),
                  ),
                ),
                const SizedBox(width: 8),
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
            Container(
              padding: const EdgeInsets.fromLTRB(10, 12, 12, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFBFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairlineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${chartRow.label} — ${_bar ? 'by month' : 'trend'}',
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 210,
                    child: _MisMetricChart(
                        points: trend,
                        bar: _bar,
                        money: money,
                        type: chartRow.type),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // Branch Matrix — full-access (CEO/Director) only; the widget itself
      // renders nothing for anyone else. Sits last, after the charts.
      if (fullAccess) MisBranchMatrix(fullAccess: fullAccess),
    ];
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
      const gap = 8.0;
      final w = (c.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final cell in cells) SizedBox(width: w, child: cell)],
      );
    });
  }

  /// Download panel for the Month Highlights table: pick a FINANCIAL YEAR, tick
  /// the months, take it as CSV. FY (not calendar year) because the table and
  /// its dropdown are already FY-based — a calendar year here would export a
  /// different span from the one on screen and quietly disagree with it.
  void _openExport(OverviewTable table, List<String> allKeys, int activeFy) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OverviewExportSheet(
        table: table,
        allKeys: allKeys,
        initialFy: activeFy,
        scopeLabel: _scopeLabel,
      ),
    );
  }

  /// The drill currently applied to the dashboard, for the export header.
  String get _scopeLabel {
    final parts = [_region?.name, _division?.name, _area?.name, _branch?.name]
        .where((s) => s != null && s.isNotEmpty)
        .join(' › ');
    return parts.isEmpty ? 'All regions' : parts;
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

/// "Sep-26 at a glance · All regions" line above the hero stats.
class _HeroKicker extends StatelessWidget {
  const _HeroKicker({required this.left, required this.right});
  final String left, right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          left,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xBDFFFFFF),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0x94FFFFFF),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Month Highlights table ──────────────────────────────────────────────────

/// A category the overview rows are grouped under, mirroring the printed
/// "Month Highlights" report. [title] is the report's own category name (it
/// also labels the CSV export); [label] is how the table shows it; [color]
/// marks the group's dot.
class _MisGroup {
  const _MisGroup(this.title, this.label, this.color, this.keys);
  final String title;
  final String label;
  final Color color;
  final Set<String> keys;
}

/// Unit column of the CSV, matched to the row type the API declares.
const Map<String, String> _overviewUnits = {
  'count': 'Count',
  'cr': 'Rs Cr',
  'pct': '%',
  'na': '',
};

/// Excel wants a bare number — keep the precision the unit deserves, no symbols.
String _csvNum(String type, double? v) {
  if (v == null || v.isNaN) return '';
  if (type == 'count') return v.round().toString();
  return v.toStringAsFixed(2);
}

/// FY picker + month tick-list over the Month Highlights table, exported as CSV.
class _OverviewExportSheet extends StatefulWidget {
  const _OverviewExportSheet({
    required this.table,
    required this.allKeys,
    required this.initialFy,
    required this.scopeLabel,
  });

  final OverviewTable table;

  /// Every month key the API returned, "YYYY-MM-DD", ascending.
  final List<String> allKeys;
  final int initialFy;
  final String scopeLabel;

  @override
  State<_OverviewExportSheet> createState() => _OverviewExportSheetState();
}

class _OverviewExportSheetState extends State<_OverviewExportSheet> {
  late int _fy = widget.initialFy;
  late Set<String> _selected = _monthsOf(_fy).toSet();
  bool _busy = false;

  List<String> _monthsOf(int fy) =>
      widget.allKeys.where((k) => misFyStart(k) == fy).toList();

  List<int> get _fys {
    final s = widget.allKeys.map(misFyStart).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final months = _monthsOf(_fy);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 14),
            const Text('Export month highlights', style: _sheetTitle),
            const SizedBox(height: 2),
            Text(widget.scopeLabel, style: AppText.caption),
            const SizedBox(height: 16),
            if (_fys.length > 1) ...[
              MisDropdown<int>(
                label: 'Financial year',
                value: _fy,
                items: [
                  for (final s in _fys)
                    DropdownMenuItem(value: s, child: Text(misFyLabel(s))),
                ],
                onChanged: (v) => setState(() {
                  _fy = v ?? _fy;
                  // The month list is rebuilt per FY, so it only ever offers
                  // months that actually have data.
                  _selected = _monthsOf(_fy).toSet();
                }),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                const Text('Months', style: AppText.label),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selected = _selected.length ==
                          months.length
                      ? <String>{}
                      : months.toSet()),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child:
                      Text(_selected.length == months.length ? 'None' : 'All'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in months)
                  FilterChip(
                    label: Text(misMonthLabel(k)),
                    selected: _selected.contains(k),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selected.add(k);
                      } else {
                        _selected.remove(k);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selected.isEmpty || _busy ? null : _export,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(_busy ? 'Exporting…' : 'Export CSV'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      // Selected months in the table's own ascending order.
      final cols = _monthsOf(_fy).where(_selected.contains).toList();
      final lines = <List<Object?>>[
        ['Scope', widget.scopeLabel],
        ['Financial year', misFyLabel(_fy)],
        const [],
        [
          'Category',
          'Parameter',
          'Unit',
          for (final k in cols) misMonthLabel(k),
        ],
        for (final row in widget.table.rows)
          [
            _groupFor(row.key).title,
            row.label,
            _overviewUnits[row.type] ?? '',
            for (final k in cols)
              _csvNum(row.type, widget.table.cell(k, row.key)),
          ],
      ];
      final name =
          'month-highlights_${misSlug(widget.scopeLabel)}_${misFyLabel(_fy)}'
              .replaceAll(' ', '-');
      final ok = await misSaveCsv(context, '$name.csv', misCsvDocument(lines));
      if (ok && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// Row-key → category, in report order. Keys come verbatim from `/overview`.
// File-level so the export sheet can label rows with the same categories the
// table shows — one definition, one source of truth.
const List<_MisGroup> _overviewGroups = [
  _MisGroup('NETWORK OVERVIEW', 'Network overview', Color(0xFF4253A8),
      {'state', 'branch', 'foCount', 'totalStaff'}),
  _MisGroup('DISBURSEMENT & ACCOUNTS', 'Disbursement & accounts',
      AppColors.info, {'disbAcc', 'disbAmt', 'activeAcc'}),
  _MisGroup('COLLECTION PERFORMANCE', 'Collection performance',
      AppColors.success, {
    'totalPos',
    'incrPos',
    'regCollPct',
    'ftodAcc',
    'ftodPar',
    'total1Par',
    'incr1Par',
  }),
  _MisGroup('NPA OVERVIEW', 'NPA overview', AppColors.danger,
      {'totalNpa', 'incrNpa', 'npaCollAcc', 'npaCollAmt'}),
  _MisGroup('PRODUCTIVITY METRICS', 'Productivity metrics', Color(0xFF9A5B00), {
    'borrowersPerBranch',
    'posPerBranch',
    'borrowersPerFo',
    'posPerFo',
    'avgLoanDisb',
    'avgLoanOs',
  }),
];
const _MisGroup _overviewOther =
    _MisGroup('OTHER', 'Other', AppColors.muted, {});

_MisGroup _groupFor(String key) {
  for (final g in _overviewGroups) {
    if (g.keys.contains(key)) return g;
  }
  return _overviewOther;
}

/// Header-row fill of the Pro tables.
const Color _headBg = Color(0xFFF6F8F8);

/// Parameter | Month 1 | Month 2, grouped by category. Each category header
/// folds its rows away on tap (all open by default).
class _HighlightsTable extends StatefulWidget {
  const _HighlightsTable({
    required this.table,
    required this.left,
    required this.right,
  });
  final OverviewTable table;
  final String left;
  final String right;

  @override
  State<_HighlightsTable> createState() => _HighlightsTableState();
}

class _HighlightsTableState extends State<_HighlightsTable> {
  final Set<String> _folded = {};

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    // Category → its rows, in report order.
    final runs = <(_MisGroup, List<OverviewRow>)>[];
    for (final row in table.rows) {
      final group = _groupFor(row.key);
      if (runs.isEmpty || runs.last.$1 != group) {
        runs.add((group, <OverviewRow>[]));
      }
      runs.last.$2.add(row);
    }

    final children = <Widget>[
      _Row(
        cells: [
          'Parameter',
          misMonthLabel(widget.left),
          misMonthLabel(widget.right)
        ],
        header: true,
      ),
    ];
    for (final run in runs) {
      final group = run.$1;
      final open = !_folded.contains(group.title);
      children.add(_GroupHeader(
        group: group,
        count: run.$2.length,
        open: open,
        onTap: () => setState(() {
          if (open) {
            _folded.add(group.title);
          } else {
            _folded.remove(group.title);
          }
        }),
      ));
      if (!open) continue;
      for (final row in run.$2) {
        final lv = table.cell(widget.left, row.key);
        final rv = table.cell(widget.right, row.key);
        children.add(_Row(
          cells: [row.label, misCell(row.type, lv), misCell(row.type, rv)],
        ));
      }
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(children: children),
    );
  }
}

/// Tappable band that introduces (and folds) a category of rows.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.count,
    required this.open,
    required this.onTap,
  });
  final _MisGroup group;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAFBFB),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: group.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: open ? 0 : -0.25,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: AppColors.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells, this.header = false});
  final List<String> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {required bool first}) {
      return Expanded(
        flex: first ? 5 : 3,
        child: Padding(
          padding: EdgeInsets.fromLTRB(first ? 16 : 6, 10, first ? 6 : 14, 10),
          child: Text(
            text,
            textAlign: first ? TextAlign.left : TextAlign.right,
            style: header
                ? const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )
                : TextStyle(
                    fontSize: 13,
                    height: 1.38,
                    fontWeight: first ? FontWeight.w500 : FontWeight.w400,
                    color: first ? AppColors.ink : AppColors.inkSoft,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
          ),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(minHeight: header ? 38 : 44),
      decoration: BoxDecoration(
        color: header ? _headBg : AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          cell(cells[0], first: true),
          cell(cells[1], first: false),
          cell(cells[2], first: false),
        ],
      ),
    );
  }
}

// ── Small controls ──────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFC6D3D6),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      );
}

const TextStyle _sheetTitle = TextStyle(
  fontSize: 19,
  height: 1.3,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.4,
  color: AppColors.ink,
);

/// Multi-select of overview-table columns (months) that feed the chart. Styled
/// like the other pick fields; opens a checklist sheet. An empty [selected] set
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
    return MisPickField(
      label: label,
      value: summary,
      onTap: () => _open(context),
    );
  }

  void _open(BuildContext context) {
    // Start from the effective set: empty ⇒ everything is currently on.
    final working = <String>{...(selected.isEmpty ? all : selected)};
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                const SizedBox(height: 10),
                const _SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Chart months', style: _sheetTitle),
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
                                  fontSize: 15,
                                  color: AppColors.ink,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ])),
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

/// Line ↔ bar switch: a soft grey track with the choice lifted onto white.
class _ChartTypeToggle extends StatelessWidget {
  const _ChartTypeToggle({required this.bar, required this.onChanged});
  final bool bar;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: active
                  ? const [
                      BoxShadow(
                        color: Color(0x240B1D21),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.ink : AppColors.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 128,
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg('Line', !bar, () => onChanged(false)),
          seg('Bar', bar, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// Quick-nav tiles to the MIS sub-dashboards.
class _MisNavRow extends StatelessWidget {
  const _MisNavRow();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Portfolio', Icons.pie_chart_rounded, '/mis/portfolio', AppColors.primary),
      ('Collection', Icons.payments_rounded, '/mis/collection', AppColors.success),
      ('Disbursement', Icons.account_balance_rounded, '/mis/disbursement',
          const Color(0xFF4253A8)),
      ('Hourly', Icons.schedule_rounded, '/mis/hourly', const Color(0xFF9A5B00)),
      ('Comparison', Icons.compare_arrows_rounded, '/mis/comparison',
          AppColors.info),
      ('Analytical', Icons.query_stats_rounded, '/mis/analytical',
          AppColors.pink),
      ('Daily report', Icons.edit_note_rounded, '/mis/daily-plan',
          AppColors.primary),
      ('Branch report', Icons.assessment_rounded, '/mis/branch-report',
          const Color(0xFF43585D)),
      ('Directory', Icons.contacts_rounded, '/mis/employees',
          const Color(0xFF4253A8)),
      ('Locations', Icons.map_rounded, '/mis/locations', AppColors.info),
      ('Feedback', Icons.forum_rounded, '/mis/feedback', AppColors.pink),
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ProSectionHeader(
              title: 'Reports',
              trailing: Text(
                '${items.length} reports',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.faint),
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            const gap = 2.0;
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
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.push(it.$3),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                          child: Column(
                            children: [
                              ProIconWell(icon: it.$2, color: it.$4, size: 46),
                              const SizedBox(height: 7),
                              SizedBox(
                                height: 30,
                                child: Text(
                                  it.$1,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.25,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Chart ───────────────────────────────────────────────────────────────────

class _Pt {
  final String label;
  final double value;
  _Pt(this.label, double? v) : value = (v == null || v.isNaN) ? 0 : v;
}

/// Axis tick / month text: Geist 11, muted.
const TextStyle _axisStyle = TextStyle(
  fontSize: 11,
  color: AppColors.muted,
  fontFeatures: [FontFeature.tabularFigures()],
);

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

  static const double _leftPad = 46; // == leftTitles.reservedSize
  static const double _bottomPad = 24; // == bottomTitles.reservedSize

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
        child: Text('No data', style: AppText.caption),
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
    // Printed-value sizing shrinks as months pile up; MisValueLabels then
    // rotates or thins them so no two can ever merge.
    final dense = points.length > 6;
    final labelFont = points.length > 9 ? 9.0 : (dense ? 10.0 : 11.0);

    final bottomTitles = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: _bottomPad,
        getTitlesWidget: (value, meta) {
          final i = value.toInt();
          if (i < 0 || i >= points.length) return const SizedBox.shrink();
          // Thin the labels if crowded.
          final step = (points.length / 6).ceil();
          if (points.length > 7 && i % step != 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(points[i].label, maxLines: 1, style: _axisStyle),
          );
        },
      ),
    );
    final leftTitles = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: _leftPad,
        getTitlesWidget: (value, meta) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(_axis(value),
              maxLines: 1, textAlign: TextAlign.right, style: _axisStyle),
        ),
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
          const FlLine(color: AppColors.hairlineSoft, strokeWidth: 1),
      getDrawingVerticalLine: (_) =>
          const FlLine(color: AppColors.hairlineSoft, strokeWidth: 1),
    );
    final border = FlBorderData(show: false);

    if (bar) {
      // Values are printed over the chart rather than drawn as fl_chart's
      // floating tooltip pills — with a full financial year of months those
      // pills overlap into an unreadable smear. MisValueLabels rotates or thins
      // the labels instead, so they never merge.
      return LayoutBuilder(builder: (context, c) {
        final plotW = (c.maxWidth - _leftPad).clamp(1.0, double.infinity);
        final barW = points.length > 8 ? 10.0 : 16.0;
        // fl_chart's BarChartAlignment.spaceEvenly geometry (equal gaps
        // before/between/after fixed-width bars), so each printed value sits
        // exactly over its bar.
        final eachSpace =
            (plotW - points.length * barW) / (points.length + 1);
        return Stack(
          children: [
            Positioned.fill(
              child: BarChart(
                BarChartData(
                  maxY: top,
                  minY: bottom,
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: points[i].value,
                            color: AppColors.primary,
                            width: barW,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                                bottom: Radius.circular(2)),
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
                  barTouchData: BarTouchData(enabled: false),
                ),
              ),
            ),
            Positioned.fill(
              child: MisValueLabels(
                leftPad: _leftPad,
                bottomPad: _bottomPad,
                fontSize: labelFont,
                slotWidth: plotW / points.length,
                labels: [
                  for (var i = 0; i < points.length; i++)
                    MisPlotLabel(
                      xFrac: ((i + 1) * eachSpace + (i + 0.5) * barW) / plotW,
                      yFrac: (points[i].value - bottom) / range,
                      text: _fmt(points[i].value),
                      color: AppColors.ink,
                    ),
                ],
              ),
            ),
          ],
        );
      });
    }

    final lineBar = LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          FlSpot(i.toDouble(), points[i].value),
      ],
      isCurved: true,
      preventCurveOverShooting: true,
      color: AppColors.primary,
      barWidth: 2.4,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: points.length <= 12,
        getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
          radius: 3.5,
          color: Colors.white,
          strokeWidth: 2.4,
          strokeColor: AppColors.primary,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.16),
            AppColors.primary.withValues(alpha: 0),
          ],
        ),
      ),
    );

    // fl_chart 0.68 does not paint permanent tooltips on a line, and its
    // floating pills overlap once a full financial year is on screen — so the
    // values are drawn over the chart by MisValueLabels, which rotates or thins
    // them rather than letting any two merge.
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotW =
            (constraints.maxWidth - _leftPad).clamp(1.0, double.infinity);
        final n = points.length;
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
            Positioned.fill(
              child: MisValueLabels(
                leftPad: _leftPad,
                bottomPad: _bottomPad,
                fontSize: labelFont,
                // Line points sit ON the edges, so the gap between neighbours
                // is plotW/(n-1), not plotW/n.
                slotWidth: n > 1 ? plotW / (n - 1) : plotW,
                labels: [
                  for (var i = 0; i < n; i++)
                    MisPlotLabel(
                      xFrac: n == 1 ? 0.5 : i / (n - 1),
                      yFrac: ((points[i].value - bottom) / range)
                          .clamp(0.0, 1.0),
                      text: _fmt(points[i].value),
                      color: AppColors.ink,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
