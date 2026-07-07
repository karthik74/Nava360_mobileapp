// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Hourly (route /mis/hourly). The live intra-day collection snapshot by
//  DPD bucket (account counts only) with a region → … → officer drill-down.
//  Ports HourlyScreen.tsx.
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

const _partition = {'regular', '1_30', '31_60', '61_90', 'pnpa'};
const _products = [('', 'All'), ('igl', 'IGL'), ('fig', 'FIG'), ('il', 'IL')];
const _levelHeader = {
  'region': 'Region',
  'division': 'Division',
  'area': 'Area',
  'branch': 'Branch',
  'employee': 'Officer',
};

class MisHourlyScreen extends ConsumerStatefulWidget {
  const MisHourlyScreen({super.key});

  @override
  ConsumerState<MisHourlyScreen> createState() => _MisHourlyScreenState();
}

class _MisHourlyScreenState extends ConsumerState<MisHourlyScreen> {
  String? _date;
  String _product = '';
  bool _table = false;
  String? _region, _division, _area, _branch;

  String get _level => _branch != null
      ? 'employee'
      : _area != null
          ? 'branch'
          : _division != null
              ? 'area'
              : _region != null
                  ? 'division'
                  : 'region';

  bool get _canDrill => _level != 'employee';

  void _drill(CollectionRow r) {
    setState(() {
      if (_region == null) {
        _region = r.region;
      } else if (_division == null) {
        _division = r.division;
      } else if (_area == null) {
        _area = r.area;
      } else {
        _branch ??= r.branch;
      }
    });
  }

  void _resetTo(String? level) {
    setState(() {
      switch (level) {
        case null:
          _region = _division = _area = _branch = null;
          break;
        case 'region':
          _division = _area = _branch = null;
          break;
        case 'division':
          _area = _branch = null;
          break;
        case 'area':
          _branch = null;
          break;
      }
    });
  }

  List<MisCrumb> _crumbs() => [
        MisCrumb('All regions', onTap: () => _resetTo(null)),
        if (_region != null) MisCrumb(_region!, onTap: () => _resetTo('region')),
        if (_division != null)
          MisCrumb(_division!, onTap: () => _resetTo('division')),
        if (_area != null) MisCrumb(_area!, onTap: () => _resetTo('area')),
        if (_branch != null) MisCrumb(_branch!),
      ];

  @override
  Widget build(BuildContext context) {
    final datesAsync = ref.watch(misHourlyDatesProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Hourly')),
      body: datesAsync.when(
        loading: () => const AppLoadingBlock(height: 240),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misHourlyDatesProvider),
          ),
        ),
        data: (dates) {
          if (dates.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: AppEmptyState(
                icon: Icons.schedule_rounded,
                message: 'No hourly snapshot is currently loaded.',
              ),
            );
          }
          final active = _date ?? dates.first;
          return _body(dates, active);
        },
      ),
    );
  }

  Widget _body(List<String> dates, String activeDate) {
    final q = CollectionQuery(
      date: activeDate,
      product: _product,
      region: _region,
      division: _division,
      area: _area,
      branch: _branch,
    );
    final summaryAsync = ref.watch(misHourlySummaryProvider(q));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(misHourlySummaryProvider(q));
        ref.invalidate(misHourlyListProvider(q));
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
          const SizedBox(height: 8),
          const Text(
            'Live hourly snapshot by DPD bucket — account counts (no rupee amounts).',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
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
              onRetry: () => ref.invalidate(misHourlySummaryProvider(q)),
            ),
            data: (s) => s.dpd.isEmpty
                ? const MisInlineEmpty('No hourly data for this date.')
                : _summary(s),
          ),
          const SizedBox(height: 18),
          MisSectionTitle('By ${_levelHeader[_level]!.toLowerCase()}'),
          _grid(q),
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
    final donut = [
      for (final b in s.dpd)
        if (_partition.contains(b.bucketName))
          MisSlice(misBucketLabel(b.bucketName), b.collectionCount,
              MisPalette.risk(b.bucketName)),
    ];
    final order = ['on_date', 'regular', '1_30', '31_60', '61_90', 'pnpa'];
    final buckets = [
      for (final name in order)
        if (s.bucket(name) != null) s.bucket(name)!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MisSnapshotGrid(cards: [
          MisSnapshotCard(
              accent: 'indigo',
              icon: Icons.layers_rounded,
              label: 'Demand',
              value: misNum(d)),
          MisSnapshotCard(
              accent: 'emerald',
              icon: Icons.trending_up_rounded,
              label: 'Collected',
              value: misNum(c)),
          MisSnapshotCard(
              accent: 'sky',
              icon: Icons.percent_rounded,
              label: 'Coll %',
              value: misPct(c, d)),
        ]),
        if (donut.any((x) => x.value > 0)) ...[
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
      ],
    );
  }

  Widget _grid(CollectionQuery q) {
    final listAsync = ref.watch(misHourlyListProvider(q));
    return listAsync.when(
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(misHourlyListProvider(q)),
      ),
      data: (rows) {
        if (rows.isEmpty) return const MisInlineEmpty('No data at this level.');
        // Rank by collection % descending.
        final sorted = [...rows]..sort((a, b) {
            final pa = a.demandCount > 0 ? a.collectionCount / a.demandCount : 0;
            final pb = b.demandCount > 0 ? b.collectionCount / b.demandCount : 0;
            return pb.compareTo(pa);
          });
        String unitOf(CollectionRow r) => (_level == 'region'
                ? r.region
                : _level == 'division'
                    ? r.division
                    : _level == 'area'
                        ? r.area
                        : _level == 'branch'
                            ? r.branch
                            : (r.name ?? r.empId)) ??
            '—';
        String? subOf(CollectionRow r) => _level == 'division'
            ? r.region
            : _level == 'area'
                ? r.division
                : _level == 'branch'
                    ? r.area
                    : _level == 'employee'
                        ? r.empId
                        : null;

        if (_table) {
          return MisTable<CollectionRow>(
            onRowTap: _canDrill ? _drill : null,
            columns: [
              MisColumn(_levelHeader[_level]!, (r) => Text(unitOf(r))),
              MisColumn('Demand', (r) => Text(misNum(r.demandCount)),
                  right: true),
              MisColumn('Collected', (r) => Text(misNum(r.collectionCount)),
                  right: true),
              MisColumn(
                  'Coll %',
                  (r) => Text(misPct(r.collectionCount, r.demandCount)),
                  right: true),
            ],
            rows: sorted,
          );
        }
        return Column(
          children: [
            for (final r in sorted) ...[
              MisUnitCard(
                title: unitOf(r),
                subtitle: subOf(r),
                demand: r.demandCount,
                collection: r.collectionCount,
                onTap: _canDrill ? () => _drill(r) : null,
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
