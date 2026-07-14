// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Collection (route /mis/collection). Daily collection summary with a
//  region → division → area → branch → officer drill-down, product filter and
//  a card / table toggle. Ports CollectionScreen.tsx. Drill is via card taps +
//  breadcrumb (the web's cascading dropdown ScopeFilter is folded into these).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart';
import 'mis_format.dart';
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
  bool _table = false;
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
    // The officer level is a leaf — no further drill grid.
    final showGrid = _emp == null;

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
          Row(
            children: [
              Expanded(
                child: MisDatePicker(
                  value: activeDate,
                  available: dates,
                  onChanged: (v) => setState(() => _date = v),
                ),
              ),
              const SizedBox(width: 10),
              MisViewToggle(
                  table: _table, onChanged: (t) => setState(() => _table = t)),
            ],
          ),
          const SizedBox(height: 12),
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
            data: (s) => _summary(s),
          ),
          if (showGrid) ...[
            const SizedBox(height: 18),
            MisSectionTitle('By ${_levelHeader[q.level]!.toLowerCase()}'),
            _grid(q),
          ],
        ],
      ),
    );
  }

  Widget _summary(CollectionSummary s) {
    var d = 0.0, c = 0.0;
    for (final b in s.dpd) {
      if (_partition.contains(b.bucketName)) {
        d += b.demandCount;
        c += b.collectionCount;
      }
    }
    // ignore: unused_local_variable  (used by the hidden snapshot cards below)
    final demand = d + s.npaCases;
    // ignore: unused_local_variable  (used by the hidden snapshot cards below)
    final collection = c + (s.npa.isNotEmpty ? s.npa.first.accounts : 0);

    final donut = [
      for (final b in s.dpd)
        if (_partition.contains(b.bucketName))
          MisSlice(misBucketLabel(b.bucketName), b.collectionCount,
              MisPalette.risk(b.bucketName)),
    ];

    // DPD bucket detail cards (on_date → pnpa), plus a synthetic NPA bucket.
    final act = s.action('activation')?.accounts ?? 0;
    final clo = s.action('closure')?.accounts ?? 0;
    final order = ['on_date', 'regular', '1_30', '31_60', '61_90', 'pnpa'];
    final buckets = [
      for (final name in order)
        if (s.bucket(name) != null) s.bucket(name)!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top three snapshot cards — hidden for now (commented per request).
        // Uncomment to restore.
        // MisSnapshotGrid(cards: [
        //   MisSnapshotCard(
        //       accent: 'indigo',
        //       icon: Icons.layers_rounded,
        //       label: 'Total regular demand',
        //       value: misNum(demand),
        //       sub: 'Regular + buckets + NPA'),
        //   MisSnapshotCard(
        //       accent: 'emerald',
        //       icon: Icons.trending_up_rounded,
        //       label: 'Collection',
        //       value: misNum(collection)),
        //   MisSnapshotCard(
        //       accent: 'sky',
        //       icon: Icons.percent_rounded,
        //       label: 'Collection %',
        //       value: misPct(collection, demand)),
        // ]),
        if (donut.any((s) => s.value > 0)) ...[
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Collection by DPD bucket',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 12),
                MisDonutChart(data: donut),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const MisSectionTitle('DPD Buckets'),
        for (final b in buckets) ...[
          MisUnitCard(
            title: misBucketLabel(b.bucketName),
            demand: b.demandCount,
            collection: b.collectionCount,
          ),
          const SizedBox(height: 8),
        ],
        MisUnitCard(
          title: 'NPA',
          subtitle: 'Activation ${misNum(act)} · Closure ${misNum(clo)}',
          demand: s.npaCases,
          collection: act,
        ),
      ],
    );
  }

  Widget _grid(CollectionQuery q) {
    final listAsync = ref.watch(misCollectionListProvider(q));
    return listAsync.when(
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(misCollectionListProvider(q)),
      ),
      data: (rows) {
        if (rows.isEmpty) return const MisInlineEmpty('No data at this level.');
        String unitOf(CollectionRow r) => (q.level == 'region'
                ? r.region
                : q.level == 'division'
                    ? r.division
                    : q.level == 'area'
                        ? r.area
                        : q.level == 'branch'
                            ? r.branch
                            : (r.name ?? r.empId)) ??
            '—';
        String? subOf(CollectionRow r) =>
            q.level == 'employee' ? r.empId : null;
        String? parentOf(CollectionRow r) => q.level == 'division'
            ? r.region
            : q.level == 'area'
                ? r.division
                : q.level == 'branch'
                    ? r.area
                    : q.level == 'employee'
                        ? r.branch
                        : null;

        if (_table) {
          return MisTable<CollectionRow>(
            onRowTap: _drill,
            columns: [
              MisColumn(_levelHeader[q.level]!, (r) => Text(unitOf(r))),
              MisColumn('Demand', (r) => Text(misNum(r.demandCount)),
                  right: true),
              MisColumn('Collection', (r) => Text(misNum(r.collectionCount)),
                  right: true),
              MisColumn('Balance', (r) => Text(misNum(r.balance)), right: true),
              MisColumn(
                  'Coll %',
                  (r) => Text(misPct(r.collectionCount, r.demandCount)),
                  right: true),
            ],
            rows: rows,
          );
        }
        return Column(
          children: [
            for (final r in rows) ...[
              MisUnitCard(
                title: unitOf(r),
                subtitle: subOf(r),
                parent: parentOf(r),
                demand: r.demandCount,
                collection: r.collectionCount,
                onTap: () => _drill(r),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
