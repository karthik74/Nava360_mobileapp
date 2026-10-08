// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Hourly (route /mis/hourly). The live intra-day collection snapshot by
//  DPD bucket (account counts only) with a region → … → officer drill-down.
//  Ports HourlyScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart';
import 'mis_collection_widgets.dart';
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

  /// Replay hour ("14"). Null = the live grain. Ports the web ?hour= switcher.
  String? _hour;

  /// On Hourly the regular bucket reads "Regular as FTOD" — the same figure IS
  /// the day's FTOD until the evening postings land (web commit 6a6675e).
  String _bucketLabel(String name) =>
      name == 'regular' ? 'Regular as FTOD' : misBucketLabel(name);

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
      appBar: AppBar(title: const Text('MIS')),
      body: datesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AppLoadingBlock(height: 240),
        ),
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
              child: ProEmpty(
                icon: Icons.schedule_rounded,
                title: 'No hourly snapshot',
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
      hour: _hour,
    );
    final summaryAsync = ref.watch(misHourlySummaryProvider(q));
    final summary = summaryAsync.valueOrNull;
    // Live-snapshot freshness for the header. Metadata only — it never gates
    // the screen, so a missing/failed snapshot simply hides the badge.
    final snapshot = ref.watch(misHourlySnapshotProvider(activeDate)).valueOrNull;
    // Stored hour slots for the replay switcher. A failed/missing /hourly/hours
    // (older API build) leaves this empty and simply hides the switcher.
    final hoursMeta = ref.watch(misHourlyHoursProvider(activeDate)).valueOrNull;
    final hourList = hoursMeta?.hours ?? const <HourlyHourInfo>[];
    final liveHour = hoursMeta?.liveHour;

    return ProPage(
      onRefresh: () async {
        ref.invalidate(misHourlySnapshotProvider(activeDate));
        ref.invalidate(misHourlyHoursProvider(activeDate));
        ref.invalidate(misHourlySummaryProvider(q));
        ref.invalidate(misHourlyListProvider(q));
      },
      hero: ProHero(
        titleWidget: MisDeepTitle(
          title: 'Hourly',
          subtitle: 'Live hourly snapshot by DPD bucket — account counts '
              '(no rupee amounts).',
          crumbs: _crumbs(),
        ),
        overlap: MisLiftedField(
          child: MisDatePicker(
            value: activeDate,
            available: dates,
            // A replayed hour belongs to its date — reset on change.
            onChanged: (v) => setState(() {
              _date = v;
              _hour = null;
            }),
          ),
        ),
        children: [
          if (_hour != null)
            MisSnapshotClock(
              key: ValueKey('replay-$_hour'),
              periodHour: int.tryParse(_hour!) ?? 0,
              live: false,
            )
          else if (snapshot != null && !snapshot.isEmpty)
            MisSnapshotClock(
              // Re-key on the hour so the odometer replays whenever a fresh
              // snapshot lands. No asOf: the card reads just LIVE + the hour
              // + "Hourly snapshot" — the capture timestamp confused readers
              // (server clock lag made "as of 6:57 AM" look stale at noon).
              key: ValueKey('${snapshot.periodDate}-${snapshot.periodHour}'),
              periodHour: snapshot.hour!,
            ),
          MisDeepSegmented<String>(
            options: _products,
            value: _product,
            onChanged: (v) => setState(() => _product = v),
          ),
          if (hourList.isNotEmpty) _hourSwitcher(hourList, liveHour),
          // Headline = the regular bucket only, with the floored FTOD stat —
          // matching the web Hourly exactly. The title drops the "Regular"
          // prefix (web commit 1429002); the bucket table below already names
          // the row "Regular as FTOD".
          MisRegularHeroStats(
            summary: (summary != null && summary.dpd.isNotEmpty)
                ? summary
                : null,
            metric: MisMetric.count,
            titleLabel: '',
          ),
        ],
      ),
      children: [
        summaryAsync.when(
          loading: () => const AppLoadingBlock(height: 180),
          error: (e, _) => AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misHourlySummaryProvider(q)),
          ),
          data: (s) => s.dpd.isEmpty
              ? const ProEmpty(
                  icon: Icons.schedule_rounded,
                  title: 'No hourly data for this date.',
                )
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
                  padding: const EdgeInsets.only(top: 8),
                  child: _intraday(agg),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            ProSectionHeader(
              title: 'By ${_levelHeader[_level]!.toLowerCase()}',
              subtitle: _canDrill ? 'Tap a row to drill down.' : null,
              trailing: MisViewToggle(
                  table: _table, onChanged: (t) => setState(() => _table = t)),
            ),
            const SizedBox(height: 10),
            _grid(q),
          ],
        ),
      ],
    );
  }

  Widget _summary(CollectionSummary s) {
    final donut = [
      for (final b in s.dpd)
        if (_partition.contains(b.bucketName))
          MisSlice(_bucketLabel(b.bucketName), b.collectionCount,
              MisPalette.risk(b.bucketName)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (donut.any((x) => x.value > 0)) ...[
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(
                  title: 'Collection by DPD bucket',
                  subtitle: 'Accounts',
                ),
                const SizedBox(height: 12),
                MisDonutChart(data: donut),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        // The exact Collection-screen DPD matrix (same table, same colours),
        // with the regular row named "Regular as FTOD" as everywhere on Hourly.
        MisBucketMatrix(
          summary: s,
          metric: MisMetric.count,
          regularLabel: 'Regular as FTOD',
          regularShortLabel: 'FTOD',
        ),
      ],
    );
  }

  /// The hour-replay chips. The chip matching the live hour renders selected by
  /// default; tapping it clears the replay (back to the live path) rather than
  /// pinning the hour, so an older backend that ignores ?hour= still works.
  Widget _hourSwitcher(List<HourlyHourInfo> hours, String? liveHour) {
    final activeHour = _hour ?? liveHour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MisDeepLabel(
          'Hour',
          trailing: _hour != null ? 'Tap the live hour to go back' : null,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (var i = 0; i < hours.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _hourChip(hours[i].hour, activeHour == hours[i].hour, liveHour),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _hourChip(String hour, bool active, String? liveHour) {
    return MisDeepChip(
      label: misHourLabel(int.tryParse(hour) ?? 0),
      selected: active,
      live: hour == liveHour,
      onTap: () => setState(() => _hour = (hour == liveHour) ? null : hour),
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
        if (rows.isEmpty) {
          return const ProEmpty(
            icon: Icons.table_rows_outlined,
            title: 'No data at this level.',
          );
        }
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

        // Table view = the units × hours heat grid (hourly-specific), when the
        // feed carries per-hour columns. The default view is the EXACT
        // Collection-screen drill table — same matrix, same colours — with the
        // shortfall column named FTOD (floored, mirroring the web).
        if (_table && hasHourly) {
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
        return MisCollectionUnitTable(
          rows: sorted,
          levelLabel: _levelHeader[_level]!,
          metric: MisMetric.count,
          unitOf: unitOf,
          subOf: subOf,
          onRowTap: _canDrill ? _drill : null,
          balanceLabel: 'FTOD',
        );
      },
    );
  }

  /// The intra-day summary strip + hour-by-hour chart for the current scope.
  Widget _intraday(List<MisHourPoint> aggregate) {
    final peak = misPeakHour(aggregate);
    final collectedToday =
        aggregate.fold<double>(0, (s, p) => s + p.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProSectionHeader(
          title: 'Intra-day collection',
          subtitle: 'Accounts collected by hour',
        ),
        const SizedBox(height: 10),
        ProKpiStrip(cells: [
          ProKpi(
            value: misNum(collectedToday),
            label: 'Collected today · accounts',
          ),
          if (peak != null)
            ProKpi(
              value: peak.label,
              label: 'Peak hour · ${misNum(peak.value)} accounts',
            ),
          ProKpi(
            value: '${aggregate.length}',
            label: 'Active hours with collection',
          ),
        ]),
        const SizedBox(height: 12),
        GlassCard(
          child: MisBarChart(
            bars: [for (final p in aggregate) MisBar(p.label, p.value)],
            color: AppColors.primary,
            showValues: true,
            height: 210,
          ),
        ),
      ],
    );
  }
}
