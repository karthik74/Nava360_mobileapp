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
import 'mis_hourly_series.dart';
import 'mis_hourly_widgets.dart';
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
    // Live-snapshot freshness for the header. Metadata only — it never gates
    // the screen, so a missing/failed snapshot simply hides the badge.
    final snapshot = ref.watch(misHourlySnapshotProvider(activeDate)).valueOrNull;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(misHourlySnapshotProvider(activeDate));
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
          if (snapshot != null && !snapshot.isEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: MisSnapshotClock(
                // Re-key on the hour so the odometer replays whenever a fresh
                // snapshot lands.
                key: ValueKey('${snapshot.periodDate}-${snapshot.periodHour}'),
                periodHour: snapshot.hour!,
                asOf: snapshot.asOf,
              ),
            ),
          ],
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
          // Intra-day build-up for the current scope. Reads the same drill
          // provider the grid below uses (same family key ⇒ no extra request),
          // and renders nothing until the feed carries per-hour columns.
          ref.watch(misHourlyListProvider(q)).maybeWhen(
                data: (rows) {
                  final agg =
                      misAggregateHourSeries([for (final r in rows) r.raw]);
                  if (agg.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: _intraday(agg),
                  );
                },
                orElse: () => const SizedBox.shrink(),
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

        // ── Intra-day breakdown — only when the feed carries per-hour columns.
        // Everything below degrades to the classic table/cards when it doesn't,
        // so the screen keeps working before the API's hour columns land.
        final seriesByRow = [
          for (final r in sorted) misHourSeries(r.raw),
        ];
        final hasHourly = seriesByRow.any((s) => s.isNotEmpty);
        final aggregate =
            misAggregateHourSeries([for (final r in sorted) r.raw]);

        if (_table) {
          if (hasHourly) {
            return MisHourlyHeatTable(
              unitHeader: _levelHeader[_level]!,
              hours: aggregate,
              rows: [
                for (var i = 0; i < sorted.length; i++)
                  MisHeatRow(
                    unit: unitOf(sorted[i]),
                    sub: subOf(sorted[i]),
                    demand: sorted[i].demandCount,
                    collected: sorted[i].collectionCount,
                    byHour: {
                      for (final p in seriesByRow[i]) p.hour: p.value,
                    },
                    onTap: _canDrill ? () => _drill(sorted[i]) : null,
                  ),
              ],
            );
          }
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
            for (var i = 0; i < sorted.length; i++) ...[
              MisUnitCard(
                title: unitOf(sorted[i]),
                subtitle: subOf(sorted[i]),
                demand: sorted[i].demandCount,
                collection: sorted[i].collectionCount,
                onTap: _canDrill ? () => _drill(sorted[i]) : null,
                footer: hasHourly && seriesByRow[i].isNotEmpty
                    ? _sparkFooter(seriesByRow[i])
                    : null,
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  /// The intra-day sparkline shown under a unit card's metrics.
  Widget _sparkFooter(List<MisHourPoint> series) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'INTRA-DAY',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: AppColors.muted,
              ),
            ),
            const Spacer(),
            Text(
              '${series.first.label} – ${series.last.label}',
              style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        MisSparkline(values: [for (final p in series) p.value]),
      ],
    );
  }

  /// The intra-day summary strip + hour-by-hour chart for the current scope.
  Widget _intraday(List<MisHourPoint> aggregate) {
    final peak = misPeakHour(aggregate);
    final collectedToday =
        aggregate.fold<double>(0, (s, p) => s + p.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const MisSectionTitle('Intra-day collection'),
            const SizedBox(width: 8),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'accounts collected by hour',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ),
          ],
        ),
        LayoutBuilder(builder: (context, c) {
          const gap = 10.0;
          final w = (c.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              SizedBox(
                width: w,
                child: MisHourKpi(
                  label: 'Collected today',
                  value: misNum(collectedToday),
                  sub: 'accounts',
                ),
              ),
              if (peak != null)
                SizedBox(
                  width: w,
                  child: MisHourKpi(
                    label: 'Peak hour',
                    value: peak.label,
                    sub: '${misNum(peak.value)} accounts',
                  ),
                ),
              SizedBox(
                width: w,
                child: MisHourKpi(
                  label: 'Active hours',
                  value: '${aggregate.length}',
                  sub: 'with collection',
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 12),
        GlassCard(
          child: MisBarChart(
            bars: [for (final p in aggregate) MisBar(p.label, p.value)],
            color: MisPalette.seriesCollection,
            showValues: true,
            height: 210,
          ),
        ),
      ],
    );
  }
}
