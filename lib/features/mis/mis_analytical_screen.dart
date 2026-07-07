// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Analytical Tool (route /mis/analytical). Ranks units "lowest first" —
//  collection by achievement %, disbursement by amount — and slices to the
//  lowest 10%, scoped to the caller's role tier, with a level drill-down.
//  Ports AnalyticalScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_auth.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

class _Level {
  final String role;
  final String level;
  final String? child;
  final String? parentKey;
  const _Level(this.role, this.level, this.child, this.parentKey);
}

const _levels = [
  _Level('RM', 'region', 'division', 'region'),
  _Level('DM', 'division', 'area', 'division'),
  _Level('AM', 'area', 'branch', 'area'),
  _Level('BM', 'branch', 'employee', 'branch'),
  _Level('FO', 'employee', null, null),
];

int _tierFloor(String? tier) => switch (tier) {
      'region' => 1,
      'division' => 2,
      'area' => 3,
      'branch' => 4,
      'self' => 4,
      _ => 0,
    };

class _Bucket {
  final String key;
  final String label;
  final String d;
  final String c;
  final bool money;
  final String dLabel;
  final String cLabel;
  const _Bucket(
      this.key, this.label, this.d, this.c, this.money, this.dLabel, this.cLabel);
}

const _buckets = [
  _Bucket('regular', 'Regular', 'regular_demand', 'regular_collection', true,
      'Demand', 'Collection'),
  _Bucket('1-30', '1-30', 'demand_1_30', 'collection_1_30', true, 'Demand',
      'Collection'),
  _Bucket('31-60', '31-60', 'demand_31_60', 'collection_31_60', true, 'Demand',
      'Collection'),
  _Bucket('pnpa', 'PNPA', 'pnpa_demand', 'pnpa_collection', true, 'Demand',
      'Collection'),
  _Bucket('npa', 'NPA', 'npa_cases', 'npa_clo_acc', false, 'Cases', 'Closed'),
];

const _attentionPct = 75.0;

int _lowestN(int count) {
  if (count <= 0) return 0;
  final v = count * 0.1;
  return v < 1 ? 1 : v.round();
}

class _DrillItem {
  final String level;
  final String? parentKey;
  final String? value;
  const _DrillItem(this.level, this.parentKey, this.value);
}

class MisAnalyticalScreen extends ConsumerStatefulWidget {
  const MisAnalyticalScreen({super.key});

  @override
  ConsumerState<MisAnalyticalScreen> createState() =>
      _MisAnalyticalScreenState();
}

class _MisAnalyticalScreenState extends ConsumerState<MisAnalyticalScreen> {
  String _mode = 'collection'; // collection | disbursement
  String _range = 'ftd'; // ftd | mtd
  String _bucketKey = 'regular';
  bool _onlyLowest = true;
  int _roleIdx = 3;
  List<_DrillItem> _drill = const [];
  String? _date;
  String? _month;

  @override
  void initState() {
    super.initState();
    final floor = _tierFloor(ref.read(misSessionProvider)?.scope?.tier);
    _roleIdx = floor > 3 ? floor : 3;
  }

  void _selectLevel(int i) => setState(() {
        _roleIdx = i;
        _drill = const [];
      });

  void _drillInto(_Level level, String? unit) {
    if (level.child == null || _roleIdx >= _levels.length - 1) return;
    setState(() {
      _drill = [..._drill, _DrillItem(level.level, level.parentKey, unit)];
      _roleIdx = _roleIdx + 1;
    });
  }

  void _back(int floor) => setState(() {
        _drill = _drill.sublist(0, _drill.length - 1);
        _roleIdx = (_roleIdx - 1) < floor ? floor : _roleIdx - 1;
      });

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(misSessionProvider)?.scope?.tier;
    final floor = _tierFloor(tier);
    final roleIdx = _roleIdx < floor ? floor : _roleIdx;
    final level = _levels[roleIdx];
    final bucket = _buckets.firstWhere((b) => b.key == _bucketKey,
        orElse: () => _buckets.first);

    final datesAsync = ref.watch(misCollectionDatesProvider);
    final monthsAsync = ref.watch(misDisbMonthsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Analytical Tool')),
      body: (_mode == 'collection' ? datesAsync : monthsAsync).when(
        loading: () => const AppLoadingBlock(height: 240),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(message: e.toString()),
        ),
        data: (periods) {
          final activeDate = _mode == 'collection'
              ? (_date ?? (periods.isNotEmpty ? periods.first : null))
              : null;
          final activeMonth = _mode == 'disbursement'
              ? (_month ?? (periods.isNotEmpty ? periods.first : null))
              : null;
          return _body(
              floor, roleIdx, level, bucket, periods, activeDate, activeMonth);
        },
      ),
    );
  }

  Widget _body(int floor, int roleIdx, _Level level, _Bucket bucket,
      List<String> periods, String? activeDate, String? activeMonth) {
    final parent = <String, dynamic>{
      for (final d in _drill)
        if (d.parentKey != null) d.parentKey!: d.value,
    };
    final parentKey = _drill.map((d) => '${d.parentKey}:${d.value}').join('|');
    final q = AnalyticalQuery(
      mode: _mode,
      range: _range,
      level: level.level,
      date: activeDate,
      month: activeMonth,
      parent: parent,
      parentKey: parentKey,
    );
    final rowsAsync = ref.watch(misAnalyticalRowsProvider(q));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
      children: [
        // Period picker — calendar for collection dates, month grid for months.
        if (_mode == 'collection')
          MisDatePicker(
            value: activeDate,
            available: periods,
            onChanged: (v) => setState(() => _date = v),
          )
        else
          MisMonthPicker(
            value: activeMonth,
            available: periods,
            onChanged: (v) => setState(() => _month = v),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MisSegmented<String>(
              options: const [
                ('collection', 'Collection'),
                ('disbursement', 'Disbursement')
              ],
              value: _mode,
              onChanged: (v) => setState(() {
                _mode = v;
                _drill = const [];
              }),
            ),
            if (_mode == 'collection')
              MisSegmented<String>(
                options: const [('ftd', 'FTD'), ('mtd', 'MTD')],
                value: _range,
                onChanged: (v) => setState(() => _range = v),
              ),
            MisSegmented<bool>(
              options: const [(true, 'Lowest 10%'), (false, 'All ranked')],
              value: _onlyLowest,
              onChanged: (v) => setState(() => _onlyLowest = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Level buttons (at/below the caller's tier)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: MisSegmented<int>(
            options: [
              for (var i = floor; i < _levels.length; i++)
                (i, _levels[i].role),
            ],
            value: roleIdx,
            onChanged: _selectLevel,
          ),
        ),
        if (_mode == 'collection') ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MisSegmented<String>(
              options: [for (final b in _buckets) (b.key, b.label)],
              value: bucket.key,
              onChanged: (v) => setState(() => _bucketKey = v),
            ),
          ),
        ],
        if (_drill.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _back(floor),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MisBreadcrumb(crumbs: [
                  for (final d in _drill) MisCrumb(d.value ?? '—'),
                  MisCrumb(level.role),
                ]),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        rowsAsync.when(
          loading: () => const AppLoadingBlock(height: 200),
          error: (e, _) => AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misAnalyticalRowsProvider(q)),
          ),
          data: (rows) => _ranked(q, level, bucket, rows),
        ),
      ],
    );
  }

  Widget _ranked(
      AnalyticalQuery q, _Level level, _Bucket bucket, List<AnalyticalRow> raw) {
    final isEmp = level.level == 'employee';
    final canDrill = level.child != null;

    if (_mode == 'disbursement') {
      final rows = raw
          .where((r) => r.amount > 0 || r.count > 0)
          .toList()
        ..sort((a, b) => a.amount.compareTo(b.amount));
      final total = rows.length;
      final n = _lowestN(total);
      final ranked = _onlyLowest ? rows.take(n).toList() : rows;
      final lowest = ranked.isNotEmpty ? ranked.first.amount : 0.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_onlyLowest && total > 0)
            _sliceNote(n, ranked.length, total, null),
          MisSnapshotGrid(perRow: 2, cards: [
            MisSnapshotCard(
                accent: 'indigo',
                icon: Icons.trending_down_rounded,
                label: '${level.role} · units in scope',
                value: misNum(total)),
            MisSnapshotCard(
                accent: 'red',
                icon: Icons.warning_amber_rounded,
                label: 'Lowest amount in slice',
                value: misRupees(lowest),
                sub: 'Bottom unit'),
          ]),
          const SizedBox(height: 14),
          if (ranked.isEmpty)
            const MisInlineEmpty('No data for this level.')
          else
            for (var i = 0; i < ranked.length; i++) ...[
              MisMetricColumnsCard(
                title: '${i + 1}. ${ranked[i].unit ?? ranked[i].empId ?? '—'}',
                subtitle: isEmp ? ranked[i].empId : null,
                columns: [
                  ('Accounts', misNum(ranked[i].count)),
                  ('Amount', misRupees(ranked[i].amount)),
                ],
                onTap: canDrill
                    ? () => _drillInto(level, ranked[i].unit)
                    : null,
              ),
              const SizedBox(height: 8),
            ],
        ],
      );
    }

    // Collection: rank by achievement % ascending.
    final rows = raw
        .map((r) => (
              row: r,
              demand: r.field(bucket.d),
              collection: r.field(bucket.c),
              pct: r.field(bucket.d) > 0
                  ? r.field(bucket.c) / r.field(bucket.d) * 100
                  : 0.0,
            ))
        .where((e) => e.demand > 0)
        .toList()
      ..sort((a, b) => a.pct.compareTo(b.pct));
    final total = rows.length;
    final n = _lowestN(total);
    final ranked = _onlyLowest ? rows.take(n).toList() : rows;
    final belowAttn = rows.where((e) => e.pct < _attentionPct).length;
    final workingAsync = ref.watch(misAnalyticalWorkingProvider(q));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_onlyLowest && total > 0)
          _sliceNote(n, ranked.length, total, workingAsync.asData?.value,
              bucket: bucket.label),
        MisSnapshotGrid(perRow: 2, cards: [
          MisSnapshotCard(
              accent: 'indigo',
              icon: Icons.trending_down_rounded,
              label: '${bucket.label} · units in scope',
              value: misNum(total)),
          MisSnapshotCard(
              accent: 'red',
              icon: Icons.warning_amber_rounded,
              label: 'Below 75% achieved',
              value: misNum(belowAttn),
              sub: 'Need attention'),
        ]),
        const SizedBox(height: 14),
        if (ranked.isEmpty)
          const MisInlineEmpty('No data for this date / level / bucket.')
        else
          for (var i = 0; i < ranked.length; i++) ...[
            MisUnitCard(
              title: '${i + 1}. ${ranked[i].row.unit ?? ranked[i].row.empId ?? '—'}',
              subtitle: isEmp ? ranked[i].row.empId : null,
              demand: ranked[i].demand,
              collection: ranked[i].collection,
              money: bucket.money,
              onTap:
                  canDrill ? () => _drillInto(level, ranked[i].row.unit) : null,
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _sliceNote(int sliceN, int shown, int total, int? working,
      {String? bucket}) {
    final parts = <String>[
      'Showing lowest ${misNum(sliceN < shown ? sliceN : shown)} of ${misNum(total)} units (10%)',
      if (working != null && working > 0) '${misNum(working)} working',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '${parts.join(', ')}, ranked by ${_mode == 'disbursement' ? 'disbursement amount' : '${bucket ?? ''} achievement'}.',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    );
  }
}
