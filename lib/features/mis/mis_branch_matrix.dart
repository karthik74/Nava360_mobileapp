// ─────────────────────────────────────────────────────────────────────────────
//  Branch Matrix — full-access (CEO/Director) only. Ports
//  src/mis/gwm/components/BranchMatrixTable.tsx exactly: pick a FINANCIAL YEAR
//  and ONE parameter (DB Amount, POS, 1+ PAR, …) and see it for every branch at
//  once, across that year's months, with a Total column at the right edge.
//
//  The grid is fully API-driven: FY choices come from `available_fys`,
//  parameter choices from `metrics`, rows from `branches`, columns from
//  `months` — nothing about the data is hardcoded here, only the controls
//  needed to pick which slice of it to show (FY, parameter, search, region /
//  division / area) — see routes/branchMatrix.js on the API side.
//
//  Sits last on the Dashboard, after the Analytics charts, same as the web.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart';
import 'mis_format.dart';
import 'mis_matrix_table.dart' show MisFootNote;
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

String _fmtCell(double? v, String type) {
  if (v == null || v.isNaN) return '—';
  if (type == 'pct') return '${v.toStringAsFixed(2)}%';
  if (type == 'cr') return v.toStringAsFixed(2);
  return misNum(v.round());
}

/// "FY 2026-27" from its start year — matches the dashboard's own fyLabel, so
/// a picked year reads identically wherever it shows up on the page.
String _fyLabel(int y) => 'FY $y-${(y + 1).toString().substring(2)}';

const _products = [
  (null, 'All'),
  ('igl', 'IGL'),
  ('fig', 'FIG'),
  ('il', 'IL'),
];

class MisBranchMatrix extends ConsumerStatefulWidget {
  const MisBranchMatrix({super.key, required this.fullAccess});

  /// This table is CEO/Director-only — the server 403s anyone else, so it
  /// renders nothing at all for anyone without full access.
  final bool fullAccess;

  @override
  ConsumerState<MisBranchMatrix> createState() => _MisBranchMatrixState();
}

class _MisBranchMatrixState extends ConsumerState<MisBranchMatrix> {
  // Purely a DISPLAY toggle — the data (and the region/division/area
  // lookups) fetch in the background as soon as this loads for a full-access
  // user, same as every other MIS section. Ticking this doesn't trigger a
  // fetch; it just reveals the controls + table that were already loading.
  bool _show = false;

  // null = "let the server pick" (the latest FY with data).
  int? _fy;
  String? _metricKey;

  // Loan product filter; null = All products.
  String? _product;
  String _query = '';
  final _searchCtrl = TextEditingController();

  // Two-month comparison, same as the Dashboard's own Month Highlights table —
  // the grid only ever shows two picked months + Total, not the whole FY's
  // columns. Defaults to the newest month vs the one before it; either side
  // can be changed via its own dropdown.
  String? _leftMonth;
  String? _rightMonth;

  // Region → Division → Area picker — narrows which branches appear in the
  // table, same cascading pattern as the Dashboard's own scope filter. No
  // Branch-level dropdown: Area already narrows to a handful of branches, and
  // each one is already its own row here.
  HierOption? _region, _division, _area;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.fullAccess) return const SizedBox.shrink();

    final async = ref.watch(
        misBranchMatrixProvider(BranchMatrixQuery(fy: _fy, product: _product)));

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Branch Matrix',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _show,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _show = v ?? false),
                  ),
                  const Text('Show data',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft)),
                ],
              ),
            ],
          ),
          if (_show)
            async.when(
              loading: () => const AppLoadingBlock(height: 240),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(misBranchMatrixProvider(
                      BranchMatrixQuery(fy: _fy, product: _product))),
                ),
              ),
              data: _body,
            ),
        ],
      ),
    );
  }

  Widget _body(BranchMatrixResponse data) {
    final metrics = data.metrics;
    if (metrics.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: MisInlineEmpty('No branch matrix data available yet.'),
      );
    }
    final metric = metrics.firstWhere(
      (m) => m.key == _metricKey,
      orElse: () => metrics.first,
    );
    final months = data.months;
    final totalLabel = metric.agg == 'avg' ? 'Avg' : 'Total';

    // Two-month comparison — recent data only, same as the Dashboard's own
    // Month Highlights table, not every month of the FY. Defaults to the
    // newest month vs the one before it; either side can be changed.
    final newest = months.isNotEmpty ? months.last : null;
    final prevNewest = months.length > 1 ? months[months.length - 2] : newest;
    final left =
        (_leftMonth != null && months.contains(_leftMonth)) ? _leftMonth! : newest;
    final right =
        (_rightMonth != null && months.contains(_rightMonth)) ? _rightMonth! : prevNewest;
    // Chronological order regardless of which side (Month 1 / Month 2) each
    // was picked from — the table columns and the chart's bars/legend both
    // read left-to-right as a timeline, not "whichever was picked first".
    final shownMonths = [
      if (left != null) left,
      if (right != null && right != left) right,
    ]..sort();
    void pickLeft(String v) {
      setState(() {
        _leftMonth = v;
        if (v == right) _rightMonth = left; // keep the two distinct
      });
    }

    void pickRight(String v) {
      setState(() {
        _rightMonth = v;
        if (v == left) _leftMonth = right;
      });
    }

    // The network-wide Total row isn't a real branch — it never matches a
    // region/division/area drill or a search term, so it's held out of the
    // filtering below and always re-appended last.
    final all = data.branches;
    final total = all.where((b) => b.isTotal).toList();
    var list = all.where((b) => !b.isTotal).toList();
    if (_region != null) {
      list = list.where((b) => b.region == _region!.name).toList();
    }
    if (_division != null) {
      list = list.where((b) => b.division == _division!.name).toList();
    }
    if (_area != null) {
      list = list.where((b) => b.area == _area!.name).toList();
    }
    final term = _query.trim().toLowerCase();
    if (term.isNotEmpty) {
      list = list
          .where((b) =>
              b.branch.toLowerCase().contains(term) ||
              (b.area ?? '').toLowerCase().contains(term) ||
              (b.division ?? '').toLowerCase().contains(term) ||
              (b.region ?? '').toLowerCase().contains(term))
          .toList();
    }
    final rows = total.isNotEmpty && list.isNotEmpty
        ? [...list, ...total]
        : list;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${rows.where((b) => !b.isTotal).length} of ${data.branchCount} branches'
            '${data.fyLabel != null ? ' · ${data.fyLabel}' : ''}',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
          ),
          const SizedBox(height: 10),

          // Loan product filter.
          Align(
            alignment: Alignment.centerLeft,
            child: MisSegmented<String?>(
              options: _products,
              value: _product,
              onChanged: (v) => setState(() => _product = v),
            ),
          ),
          const SizedBox(height: 10),

          // FY + Parameter.
          Row(
            children: [
              if (data.availableFys.length > 1)
                Expanded(
                  child: MisDropdown<int>(
                    label: 'Financial Year',
                    value: _fy ?? data.fy ?? data.availableFys.first,
                    items: [
                      for (final y in data.availableFys)
                        DropdownMenuItem(value: y, child: Text(_fyLabel(y))),
                    ],
                    onChanged: (v) => setState(() => _fy = v),
                  ),
                ),
              if (data.availableFys.length > 1) const SizedBox(width: 10),
              Expanded(
                child: MisDropdown<String>(
                  label: 'Parameter',
                  value: metric.key,
                  items: [
                    for (final m in metrics)
                      DropdownMenuItem(value: m.key, child: Text(m.label)),
                  ],
                  onChanged: (v) => setState(() => _metricKey = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Two-month comparison — same MisMonthPicker the Dashboard's own
          // Month Highlights table uses. Only these two months (+ Total)
          // render below; pick either dropdown to change which ones.
          if (months.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: MisMonthPicker(
                    label: 'Month 1',
                    value: left,
                    available: months,
                    onChanged: pickLeft,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MisMonthPicker(
                    label: 'Month 2',
                    value: right,
                    available: months,
                    onChanged: pickRight,
                  ),
                ),
              ],
            ),
          if (months.isNotEmpty) const SizedBox(height: 10),

          // Search.
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search branch / area / division / region…',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),

          // Region → Division → Area — narrows the branches in the table,
          // same cascading pattern as the rest of the app.
          _hierPickers(),
          const SizedBox(height: 12),

          if (rows.isEmpty)
            MisInlineEmpty('No branches match "$_query".')
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fixedTable(
                    monthCols: shownMonths,
                    totalLabel: totalLabel,
                    rows: rows,
                    metric: metric),
                // Only once drilled down to a single Area — that's the point
                // the branch count is small enough for a per-branch chart to
                // actually read; above that (Region/Division/no drill) it's
                // the whole network's worth of branches, which belongs in
                // the table, not a bar chart.
                if (_area != null) ...[
                  const SizedBox(height: 20),
                  _branchChart(
                      shownMonths: shownMonths, rows: rows, metric: metric),
                ],
              ],
            ),
          if (data.note != null && data.note!.isNotEmpty)
            MisFootNote(data.note!),
        ],
      ),
    );
  }

  /// The grid itself — always exactly Branch + (up to) 2 months + Total, so
  /// unlike the shared [MisMatrixTable] (built for an open-ended column count
  /// and scrolls horizontally) this lays every column out with Expanded/flex
  /// and never scrolls sideways. Only the page around it scrolls, vertically.
  Widget _fixedTable({
    required List<String> monthCols,
    required String totalLabel,
    required List<BranchMatrixRow> rows,
    required BranchMatrixMetric metric,
  }) {
    const branchFlex = 4;
    const numFlex = 3;

    Widget headerCell(String text, int flex, {bool left = false}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: left ? TextAlign.left : TextAlign.right,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
          ),
        );

    Widget dataCell(
      String text,
      int flex, {
      bool left = false,
      FontWeight weight = FontWeight.w600,
      Color? color,
    }) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: left ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: weight,
                color: color ?? AppColors.inkSoft,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          children: [
            // AppColors.primary is runtime-brandable, so this can't be const.
            Container(
              color: AppColors.primary,
              child: Row(
                children: [
                  headerCell('Branch', branchFlex, left: true),
                  for (final m in monthCols)
                    headerCell(misMonthLabel(m), numFlex),
                  headerCell(totalLabel, numFlex),
                ],
              ),
            ),
            for (var i = 0; i < rows.length; i++)
              Container(
                decoration: BoxDecoration(
                  color: rows[i].isTotal
                      ? const Color(0xFFF4B084)
                      : (i.isOdd ? AppColors.surfaceAlt : AppColors.surface),
                  border: const Border(
                      top: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  children: [
                    dataCell(
                      rows[i].branch,
                      branchFlex,
                      left: true,
                      weight: rows[i].isTotal
                          ? FontWeight.w800
                          : FontWeight.w700,
                      color: AppColors.ink,
                    ),
                    for (final m in monthCols)
                      dataCell(
                        _fmtCell(rows[i].cell(m, metric.key), metric.type),
                        numFlex,
                        weight:
                            rows[i].isTotal ? FontWeight.w800 : FontWeight.w500,
                      ),
                    dataCell(
                      _fmtCell(rows[i].totals[metric.key], metric.type),
                      numFlex,
                      weight: FontWeight.w800,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Grouped bar chart of every filtered branch's value for the selected
  /// metric, across [shownMonths] — the same 1-2 months (Total excluded, it's
  /// not a real branch) the table above shows. With 100+ branches possible,
  /// each one gets a fixed minimum slot width and the chart scrolls
  /// horizontally, same idea as the table's own fixed columns not trying to
  /// squeeze everything into one screen width.
  Widget _branchChart({
    required List<String> shownMonths,
    required List<BranchMatrixRow> rows,
    required BranchMatrixMetric metric,
  }) {
    final branches = rows.where((b) => !b.isTotal).toList();
    if (branches.isEmpty) return const SizedBox.shrink();

    final groups = [
      for (final b in branches)
        MisBarGroup(b.branch, [
          for (final m in shownMonths) b.cell(m, metric.key) ?? 0,
        ]),
    ];
    const minSlotWidth = 46.0;
    final chartWidth = (groups.length * minSlotWidth * shownMonths.length)
        .clamp(300.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MisSectionTitle('${metric.label} — by branch'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            child: MisGroupedBarChart(
              groups: groups,
              seriesNames: [for (final m in shownMonths) misMonthLabel(m)],
              seriesColors: const [
                MisPalette.seriesDemand,
                MisPalette.seriesCollection,
              ],
              valueFormatter: (v) => _fmtCell(v, metric.type),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hierPickers() {
    final regions = ref.watch(misRegionsProvider);
    final divisions = _region == null
        ? const AsyncValue<List<HierOption>>.data([])
        : ref.watch(misDivisionsProvider(_region!.id));
    final areas = _division == null
        ? const AsyncValue<List<HierOption>>.data([])
        : ref.watch(misAreasProvider(_division!.id));

    Widget hierDropdown(String label, HierOption? value,
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
                value: o.id, child: Text(o.name, overflow: TextOverflow.ellipsis)),
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

    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final w = (c.maxWidth - gap) / 2;
      final cells = <Widget>[
        hierDropdown('Region', _region, regions, (o) {
          setState(() {
            _region = o;
            _division = _area = null;
          });
        }),
        if (_region != null)
          hierDropdown('Division', _division, divisions, (o) {
            setState(() {
              _division = o;
              _area = null;
            });
          }),
        if (_division != null)
          hierDropdown('Area', _area, areas, (o) {
            setState(() => _area = o);
          }),
      ];
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
                _region = _division = _area = null;
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
}
