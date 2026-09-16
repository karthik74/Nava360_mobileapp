// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Collection (route /mis/collection). Daily collection summary with a
//  region → division → area → branch → officer drill-down, product filter and an
//  Accounts/Amount switch. Ports CollectionScreen.tsx.
//
//  Structure, matching the web top to bottom:
//    scope chip · date · Accounts/Amount · product · breadcrumb
//    Demand-vs-collection chart + Collection-by-DPD donut
//    Regular Demand vs Collection (Demand / Collection / FTOD / Coll %)
//    DPD Buckets matrix
//    Mode of Collection
//    the per-unit drill table
//
//  Like the web there is NO cards/table toggle: the drill is always a table,
//  because cards cannot line units up for comparison down a column.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_auth.dart';
import 'mis_charts.dart';
import 'mis_collection_widgets.dart';
import 'mis_format.dart';
import 'mis_matrix_table.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

// DPD buckets that partition the book (exclude on_date, which overlaps regular).
const _partition = {'regular', '1_30', '31_60', '61_90', 'pnpa'};

const _products = [('', 'All'), ('igl', 'IGL'), ('fig', 'FIG'), ('il', 'IL')];
const _levelHeader = {
  'region': 'Region',
  'division': 'Division',
  'area': 'Area',
  'branch': 'Branch',
  'employee': 'Officer',
};

class MisCollectionScreen extends ConsumerStatefulWidget {
  const MisCollectionScreen({super.key});

  @override
  ConsumerState<MisCollectionScreen> createState() =>
      _MisCollectionScreenState();
}

class _MisCollectionScreenState extends ConsumerState<MisCollectionScreen> {
  String? _date;
  String _product = '';
  /// Accounts (live-site parity, the default) vs rupee Amount. Both ride on the
  /// SAME /collection/* responses — Amount just reads the `_amt` fields.
  MisMetric _metric = MisMetric.count;
  String? _region, _division, _area, _branch, _emp, _empName;

  void _drill(CollectionRow r) {
    setState(() {
      if (_region == null) {
        _region = r.region;
      } else if (_division == null) {
        _division = r.division;
      } else if (_area == null) {
        _area = r.area;
      } else if (_branch == null) {
        _branch = r.branch;
      } else {
        _emp = r.empId;
        _empName = r.name ?? r.empId;
      }
    });
  }

  void _resetTo(String? level) {
    setState(() {
      switch (level) {
        case null:
          _region = _division = _area = _branch = _emp = _empName = null;
          break;
        case 'region':
          _division = _area = _branch = _emp = _empName = null;
          break;
        case 'division':
          _area = _branch = _emp = _empName = null;
          break;
        case 'area':
          _branch = _emp = _empName = null;
          break;
        case 'branch':
          _emp = _empName = null;
          break;
      }
    });
  }

  List<MisCrumb> _crumbs() {
    return [
      MisCrumb('All regions', onTap: () => _resetTo(null)),
      if (_region != null) MisCrumb(_region!, onTap: () => _resetTo('region')),
      if (_division != null)
        MisCrumb(_division!, onTap: () => _resetTo('division')),
      if (_area != null) MisCrumb(_area!, onTap: () => _resetTo('area')),
      if (_branch != null) MisCrumb(_branch!, onTap: () => _resetTo('branch')),
      if (_emp != null) MisCrumb(_empName ?? _emp!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final datesAsync = ref.watch(misCollectionDatesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Collection')),
      body: datesAsync.when(
        loading: () => const AppLoadingBlock(height: 240),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misCollectionDatesProvider),
          ),
        ),
        data: (dates) {
          final active = _date ?? (dates.isNotEmpty ? dates.first : null);
          return _body(dates, active);
        },
      ),
    );
  }

  Widget _body(List<String> dates, String? activeDate) {
    final q = CollectionQuery(
      date: activeDate,
      product: _product,
      region: _region,
      division: _division,
      area: _area,
      branch: _branch,
      emp: _emp,
    );
    final summaryAsync = ref.watch(misCollectionSummaryProvider(q));
    final summary = summaryAsync.valueOrNull;
    // The officer level is a leaf — no further drill grid.
    final showGrid = _emp == null;

    // The Amount switch only appears when this date actually HAS rupee figures,
    // and degrades to counts when it doesn't, so the screen can never render a
    // page of ₹0.00 Cr.
    final summaryHasAmounts = summary?.hasAmounts ?? false;
    final metric = summaryHasAmounts ? _metric : MisMetric.count;
    final tier = ref.watch(misSessionProvider)?.scope?.tier;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(misCollectionSummaryProvider(q));
        ref.invalidate(misCollectionListProvider(q));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
        children: [
          if (tier != null && tier.isNotEmpty && tier != 'all') ...[
            Align(
              alignment: Alignment.centerLeft,
              child: MisScopeChip(tier: tier),
            ),
            const SizedBox(height: 10),
          ],
          MisDatePicker(
            value: activeDate,
            available: dates,
            onChanged: (v) => setState(() => _date = v),
          ),
          const SizedBox(height: 12),
          // Accounts vs Amount — shown ONLY when this date carries rupees. No
          // extra request: both ride on the responses the screen already makes.
          if (summaryHasAmounts) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: MisSegmented<MisMetric>(
                options: const [
                  (MisMetric.count, 'Accounts'),
                  (MisMetric.amount, '₹ Amount'),
                ],
                value: metric,
                onChanged: (v) => setState(() => _metric = v),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: MisSegmented<String>(
              options: _products,
              value: _product,
              onChanged: (v) => setState(() => _product = v),
            ),
          ),
          const SizedBox(height: 12),
          MisBreadcrumb(crumbs: _crumbs()),
          const SizedBox(height: 14),
          summaryAsync.when(
            loading: () => const AppLoadingBlock(height: 180),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(misCollectionSummaryProvider(q)),
            ),
            data: (s) => _summary(s, metric, q, showGrid),
          ),
          if (showGrid) ...[
            const SizedBox(height: 18),
            MisSectionTitle(_levelHeader[q.level]!),
            _grid(q, metric),
          ],
        ],
      ),
    );
  }

  /// Everything driven by `/collection/summary`, in the web's order: the two
  /// charts, the Regular headline card, the DPD matrix, then Mode of Collection.
  Widget _summary(
    CollectionSummary s,
    MisMetric metric,
    CollectionQuery q,
    bool showCharts,
  ) {
    final isAmount = metric == MisMetric.amount;
    // Legend % is each bucket's Collection % (collection ÷ demand) — the SAME
    // figure the DPD table shows, not the slice's share of total collection.
    final donut = [
      for (final b in s.dpd)
        if (_partition.contains(b.bucketName))
          MisSlice(misBucketLabel(b.bucketName), b.collection(metric),
              MisPalette.risk(b.bucketName)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCharts) ...[
          _demandVsCollectionChart(q, metric),
          if (donut.any((x) => x.value > 0)) ...[
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Collection ${isAmount ? "amount" : "accounts"} by DPD bucket',
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Slice size = share of total collection',
                    style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  MisDonutChart(data: donut, money: isAmount),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
        MisRegularCollectionCard(summary: s, metric: metric),
        const SizedBox(height: 16),
        MisBucketMatrix(summary: s, metric: metric),
        const SizedBox(height: 16),
        // Mode of Collection — live from /collection/summary's `modes`, scoped
        // and drilled by the same filters as everything above. Renders nothing
        // when no channel file has been uploaded for this date.
        MisCollectionModeTable(summary: s),
      ],
    );
  }

  /// Demand vs collection per sub-unit, in the active metric.
  Widget _demandVsCollectionChart(CollectionQuery q, MisMetric metric) {
    final rows = ref.watch(misCollectionListProvider(q)).valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    final level = q.level;
    final isAmount = metric == MisMetric.amount &&
        rows.any((r) => r.hasAmount);
    final m = isAmount ? MisMetric.amount : MisMetric.count;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demand vs collection ${isAmount ? "amount" : "accounts"} by '
            '${level == 'employee' ? 'officer' : level}',
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink),
          ),
          const SizedBox(height: 12),
          MisGroupedBarChart(
            groups: [
              for (final r in rows)
                MisBarGroup(_unitOf(r, level), [
                  r.demand(m),
                  r.collection(m),
                ]),
            ],
            seriesNames: const ['Demand', 'Collection'],
            seriesColors: const [
              MisPalette.seriesDemand,
              MisPalette.seriesCollection,
            ],
            money: isAmount,
          ),
        ],
      ),
    );
  }

  String _unitOf(CollectionRow r, String level) =>
      (level == 'region'
          ? r.region
          : level == 'division'
              ? r.division
              : level == 'area'
                  ? r.area
                  : level == 'branch'
                      ? r.branch
                      : (r.name ?? r.empId)) ??
      '—';

  Widget _grid(CollectionQuery q, MisMetric metric) {
    final listAsync = ref.watch(misCollectionListProvider(q));
    return listAsync.when(
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(misCollectionListProvider(q)),
      ),
      data: (rows) {
        if (rows.isEmpty) return const MisInlineEmpty('No data at this level.');

        // The by-<level> feed can lack amounts even when /summary has them, so
        // the drill table keeps showing counts instead of a page of ₹0.00 Cr —
        // and says why the Amount view is unavailable at this level.
        final rowsHaveAmounts = rows.any((r) => r.hasAmount);
        final unitMetric =
            (metric == MisMetric.amount && rowsHaveAmounts)
                ? MisMetric.amount
                : MisMetric.count;

        String? subOf(CollectionRow r) => q.level == 'employee'
            ? r.empId
            : q.level == 'division'
                ? r.region
                : q.level == 'area'
                    ? r.division
                    : q.level == 'branch'
                        ? r.area
                        : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (metric == MisMetric.amount && !rowsHaveAmounts)
              MisWarnBanner(
                'The /collection/by-${q.level} feed returned no demand_amt / '
                'collection_amt for this date, so the table below stays on '
                'Accounts. Re-sync this date to load its rupee figures. The '
                'bucket table above is unaffected.',
              ),
            MisCollectionUnitTable(
              rows: rows,
              levelLabel: _levelHeader[q.level]!,
              metric: unitMetric,
              unitOf: (r) => _unitOf(r, q.level),
              subOf: subOf,
              onRowTap: _drill,
            ),
          ],
        );
      },
    );
  }
}
