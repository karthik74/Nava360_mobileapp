// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Comparison (route /mis/comparison). Month-over-month, previous vs
//  current, day by day. Collection pairs days by weekday-occurrence (1st Mon ↔
//  1st Mon), de-cumulates the cumulative MTD figures into daily contributions
//  and re-accumulates per label; Disbursement pairs by day-of-month. Ports
//  ComparisonScreen.tsx (card views; the web's sortable tables are omitted on
//  mobile — the card comparison carries the same numbers).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

// ── calendar + formatting helpers (ported 1:1) ──────────────────────────────

const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _monthNames = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _deltaFields = [
  'regular_demand', 'regular_collection',
  'demand_1_30', 'collection_1_30',
  'demand_31_60', 'collection_31_60',
  'pnpa_demand', 'pnpa_collection',
  'npa_cases', 'npa_act_acc',
];

String _pad2(int n) => n < 10 ? '0$n' : '$n';
String _ordinal(int n) {
  final v = n % 100;
  final s = ['th', 'st', 'nd', 'rd'];
  return '$n${(v >= 11 && v <= 13) ? 'th' : (s.length > n % 10 ? s[n % 10] : 'th')}';
}

String _fmtNum(num v) => misNum(v);
String _fmtCr(num v) => '${(v / 10000000).toStringAsFixed(2)} Cr';
String _pctStr(double d, double c) =>
    d > 0 ? '${(c / d * 100).toStringAsFixed(1)}%' : '-';
Color _pctColor(double d, double c) {
  if (d == 0) return AppColors.muted;
  final p = c / d * 100;
  return p >= 95
      ? AppColors.success
      : p >= 80
          ? AppColors.warning
          : AppColors.danger;
}

String _fmtDate(String? s) {
  if (s == null || s.isEmpty) return '-';
  final p = s.split('-');
  if (p.length < 3) return s;
  return '${int.parse(p[2])} ${_monthNames[int.parse(p[1])]}';
}

/// JS getDay() equivalent: Sun=0..Sat=6.
int _jsDay(int y, int m, int d) => DateTime(y, m, d).weekday % 7;
int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

int _getOccurrence(int y, int m, int d) {
  final dow = _jsDay(y, m, d);
  final firstDow = _jsDay(y, m, 1);
  final firstOfThisDow = 1 + ((dow - firstDow + 7) % 7);
  return ((d - firstOfThisDow) / 7).floor() + 1;
}

int? _getDateForLabel(int y, int m, String dayName, int occurrence) {
  final dowIndex = _dayNames.indexOf(dayName);
  final firstDow = _jsDay(y, m, 1);
  final firstOfThisDow = 1 + ((dowIndex - firstDow + 7) % 7);
  final d = firstOfThisDow + (occurrence - 1) * 7;
  return d <= _daysInMonth(y, m) ? d : null;
}

class _MonthInfo {
  final int year, month;
  final String name;
  const _MonthInfo(this.year, this.month, this.name);
}

class _Months {
  final _MonthInfo cur, prev;
  const _Months(this.cur, this.prev);
}

class _LabeledDay {
  final String date;
  final int dayNum;
  final String dayName;
  final int occurrence;
  final String label;
  const _LabeledDay(
      this.date, this.dayNum, this.dayName, this.occurrence, this.label);
}

_Months? _getMonths(List<String> allDates) {
  if (allDates.isEmpty) return null;
  final sorted = [...allDates]..sort();
  final p = sorted.last.substring(0, 10).split('-');
  final cy = int.parse(p[0]), cm = int.parse(p[1]);
  final py = cm == 1 ? cy - 1 : cy, pm = cm == 1 ? 12 : cm - 1;
  return _Months(
    _MonthInfo(cy, cm, '${_monthNames[cm]} $cy'),
    _MonthInfo(py, pm, '${_monthNames[pm]} $py'),
  );
}

double _num(Map<String, dynamic>? m, String k) =>
    m == null ? 0 : (misToDouble(m[k]) ?? 0);

bool _sideHasData(CompareSide? s) =>
    s != null && _deltaFields.any((f) => s.field(f) > 0);

Map<String, Map<String, dynamic>> _buildDateMap(List<CompareDailyRow> rows) {
  final map = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    if (_sideHasData(r.from)) map[r.from!.date] = r.from!.raw;
    if (_sideHasData(r.to)) map[r.to!.date] = r.to!.raw;
  }
  return map;
}

Map<String, Map<String, double>> _buildDailyMap(
    Map<String, Map<String, dynamic>> dateMap, _Months months) {
  final dailyMap = <String, Map<String, double>>{};
  for (final mo in [months.prev, months.cur]) {
    final dates = dateMap.keys.where((ds) {
      final p = ds.split('-');
      return int.parse(p[0]) == mo.year && int.parse(p[1]) == mo.month;
    }).toList()
      ..sort();
    for (var i = 0; i < dates.length; i++) {
      final cur = dateMap[dates[i]];
      final prev = i > 0 ? dateMap[dates[i - 1]] : null;
      final daily = <String, double>{};
      for (final f in _deltaFields) {
        daily[f] = _num(cur, f) - (prev != null ? _num(prev, f) : 0);
      }
      dailyMap[dates[i]] = daily;
    }
  }
  return dailyMap;
}

List<_LabeledDay> _buildLabeledDays(
    Map<String, Map<String, dynamic>> dateMap, int year, int month) {
  final days = <_LabeledDay>[];
  final dim = _daysInMonth(year, month);
  for (var d = 1; d <= dim; d++) {
    final ds = '$year-${_pad2(month)}-${_pad2(d)}';
    if (!dateMap.containsKey(ds)) continue;
    final dow = _jsDay(year, month, d);
    final occ = _getOccurrence(year, month, d);
    days.add(_LabeledDay(ds, d, _dayNames[dow], occ, '$occ - ${_dayNames[dow]}'));
  }
  return days;
}

Map<String, _LabeledDay> _labelMap(List<_LabeledDay> days) =>
    {for (final d in days) d.label: d};

class _CollModel {
  final _Months months;
  final List<_LabeledDay> curDays;
  final Map<String, _LabeledDay> prevLabelMap;
  final Map<String, Map<String, double>> prevCumMap, curCumMap;
  const _CollModel(this.months, this.curDays, this.prevLabelMap,
      this.prevCumMap, this.curCumMap);
}

_CollModel? _buildCollectionModel(Map<String, Map<String, dynamic>> dateMap) {
  final months = _getMonths(dateMap.keys.toList());
  if (months == null) return null;
  final dailyMap = _buildDailyMap(dateMap, months);
  final curDays = _buildLabeledDays(dateMap, months.cur.year, months.cur.month);
  final prevDays =
      _buildLabeledDays(dateMap, months.prev.year, months.prev.month);
  final prevLabelMap = _labelMap(prevDays);
  final curLabelMap = _labelMap(curDays);

  const dowOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final latestCurDayNum = curDays.isNotEmpty ? curDays.last.dayNum : 0;
  final maxOcc = [
    (_daysInMonth(months.prev.year, months.prev.month) / 7).ceil(),
    (_daysInMonth(months.cur.year, months.cur.month) / 7).ceil(),
  ].reduce((a, b) => a > b ? a : b);

  final allLabels = <String>[];
  for (var occ = 1; occ <= maxOcc; occ++) {
    for (final dow in dowOrder) {
      allLabels.add('$occ - $dow');
    }
  }

  final prevCumMap = <String, Map<String, double>>{};
  final curCumMap = <String, Map<String, double>>{};

  int labelDate(int y, int m, String label) {
    final parts = label.split(' - ');
    return _getDateForLabel(y, m, parts[1], int.parse(parts[0])) ?? 99;
  }

  final prevSorted = [...allLabels]..sort((a, b) =>
      labelDate(months.prev.year, months.prev.month, a) -
      labelDate(months.prev.year, months.prev.month, b));
  final pRun = {for (final f in _deltaFields) f: 0.0};
  for (final label in prevSorted) {
    final parts = label.split(' - ');
    final pv = prevLabelMap[label];
    final pvD = pv != null ? dailyMap[pv.date] : null;
    final curDateNum = _getDateForLabel(
        months.cur.year, months.cur.month, parts[1], int.parse(parts[0]));
    final isFuture = curDateNum == null || curDateNum > latestCurDayNum;
    if (pvD != null && !isFuture) {
      for (final f in _deltaFields) {
        pRun[f] = pRun[f]! + (pvD[f] ?? 0);
      }
      prevCumMap[label] = {for (final f in _deltaFields) f: pRun[f]!};
    }
  }

  final curSorted = [...allLabels]..sort((a, b) =>
      labelDate(months.cur.year, months.cur.month, a) -
      labelDate(months.cur.year, months.cur.month, b));
  final cRun = {for (final f in _deltaFields) f: 0.0};
  for (final label in curSorted) {
    final cu = curLabelMap[label];
    final cuD = cu != null ? dailyMap[cu.date] : null;
    if (cuD != null) {
      for (final f in _deltaFields) {
        cRun[f] = cRun[f]! + (cuD[f] ?? 0);
      }
      curCumMap[label] = {for (final f in _deltaFields) f: cRun[f]!};
    }
  }

  return _CollModel(months, curDays, prevLabelMap, prevCumMap, curCumMap);
}

// Disbursement -----------------------------------------------------------------

class _DisbDay {
  final double accounts, amount;
  const _DisbDay(this.accounts, this.amount);
}

class _DisbModel {
  final _Months months;
  final Map<int, _DisbDay> prevMap, curMap;
  final List<int> days;
  const _DisbModel(this.months, this.prevMap, this.curMap, this.days);
}

Map<int, _DisbDay> _trendToDayMap(List<DisbTrendRow> rows, int year, int month) {
  final map = <int, _DisbDay>{};
  for (final r in rows) {
    final iso = r.disbDate.length >= 10 ? r.disbDate.substring(0, 10) : r.disbDate;
    final p = iso.split('-');
    if (p.length < 3) continue;
    if (int.parse(p[0]) != year || int.parse(p[1]) != month) continue;
    map[int.parse(p[2])] = _DisbDay(r.count, r.amount);
  }
  return map;
}

// ── scope + providers ───────────────────────────────────────────────────────

/// The selected Region/Division/Area/Branch NAMES for the comparison filter.
class MisCompareScope {
  final String? region, division, area, branch;
  const MisCompareScope({this.region, this.division, this.area, this.branch});

  @override
  bool operator ==(Object other) =>
      other is MisCompareScope &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch;

  @override
  int get hashCode => Object.hash(region, division, area, branch);
}

final _collCompareProvider =
    FutureProvider.autoDispose.family<_CollModel?, MisCompareScope>(
        (ref, scope) async {
  final repo = ref.watch(misRepositoryProvider);
  final dates = await repo.collectionDates();
  if (dates.isEmpty) return null;
  final months = _getMonths(dates.map((d) => d.substring(0, 10)).toList());
  if (months == null) return null;
  final curAnchor = '${months.cur.year}-${_pad2(months.cur.month)}-01';
  final prevAnchor = '${months.prev.year}-${_pad2(months.prev.month)}-01';
  final resp = await repo.compareDaily(
    prevAnchor,
    curAnchor,
    region: scope.region,
    division: scope.division,
    area: scope.area,
    branch: scope.branch,
  );
  return _buildCollectionModel(_buildDateMap(resp.rows));
});

final _disbCompareProvider =
    FutureProvider.autoDispose.family<_DisbModel?, MisCompareScope>(
        (ref, scope) async {
  final repo = ref.watch(misRepositoryProvider);
  final dates = await repo.disbursementDailyDates();
  if (dates.isEmpty) return null;
  final months = _getMonths(dates.map((d) => d.substring(0, 10)).toList());
  if (months == null) return null;
  // Same scope passed to BOTH the prev and cur month calls.
  final prev = await repo.disbursementDailyTrend(DisbTrendQuery(
    month: '${months.prev.year}-${_pad2(months.prev.month)}',
    region: scope.region,
    division: scope.division,
    area: scope.area,
    branch: scope.branch,
  ));
  final cur = await repo.disbursementDailyTrend(DisbTrendQuery(
    month: '${months.cur.year}-${_pad2(months.cur.month)}',
    region: scope.region,
    division: scope.division,
    area: scope.area,
    branch: scope.branch,
  ));
  final prevMap = _trendToDayMap(prev, months.prev.year, months.prev.month);
  final curMap = _trendToDayMap(cur, months.cur.year, months.cur.month);
  final days = <int>[];
  for (var d = 1; d <= 31; d++) {
    if (prevMap.containsKey(d) || curMap.containsKey(d)) days.add(d);
  }
  return _DisbModel(months, prevMap, curMap, days);
});

// ── screen ──────────────────────────────────────────────────────────────────

class MisComparisonScreen extends ConsumerStatefulWidget {
  const MisComparisonScreen({super.key});

  @override
  ConsumerState<MisComparisonScreen> createState() =>
      _MisComparisonScreenState();
}

class _MisComparisonScreenState extends ConsumerState<MisComparisonScreen> {
  bool _disb = false; // Collection | Disbursement sub-tab
  int _dayIdx = -1; // -1 ⇒ default to latest

  // Cascading scope filter (Region → Division → Area → Branch). The `id` loads
  // the next level; the NAMES are sent to the comparison endpoints.
  HierOption? _region, _division, _area, _branch;

  MisCompareScope get _scope => MisCompareScope(
        region: _region?.name,
        division: _division?.name,
        area: _area?.name,
        branch: _branch?.name,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Comparison')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, MediaQuery.of(context).padding.bottom + 24),
        children: [
          const Text(
            'Month-over-month — previous vs current, day by day.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          // Scope filter (above the sub-tabs).
          _scopeFilter(),
          const SizedBox(height: 12),
          Center(
            child: MisSegmented<bool>(
              options: const [(false, 'Collection'), (true, 'Disbursement')],
              value: _disb,
              onChanged: (v) => setState(() {
                _disb = v;
                _dayIdx = -1;
              }),
            ),
          ),
          const SizedBox(height: 16),
          if (_disb) _disbursement() else _collection(),
        ],
      ),
    );
  }

  // ── Cascading scope filter ──────────────────────────────────────────────────

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
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
                  SizedBox(width: 4),
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

  Widget _navigator(String label, String sub, int idx, int lastIdx) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton.outlined(
          onPressed: idx <= 0 ? null : () => setState(() => _dayIdx = idx - 1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ),
        IconButton.outlined(
          onPressed:
              idx >= lastIdx ? null : () => setState(() => _dayIdx = idx + 1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  // Collection -----------------------------------------------------------------

  Widget _collection() {
    final async = ref.watch(_collCompareProvider(_scope));
    return async.when(
      loading: () => const AppLoadingBlock(height: 280),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(_collCompareProvider(_scope)),
      ),
      data: (model) {
        if (model == null || model.curDays.isEmpty) {
          return const MisInlineEmpty('No daily collection data available.');
        }
        final lastIdx = model.curDays.length - 1;
        final idx = _dayIdx < 0 ? lastIdx : _dayIdx.clamp(0, lastIdx);
        final curDay = model.curDays[idx];
        final prevDay = model.prevLabelMap[curDay.label];
        final cur = model.curCumMap[curDay.label];
        final prev = model.prevCumMap[curDay.label];

        final buckets = <(String, Color, double, double, double, double)>[
          ('Regular (FTOD)', AppColors.success, _num(prev, 'regular_demand'),
              _num(prev, 'regular_collection'), _num(cur, 'regular_demand'),
              _num(cur, 'regular_collection')),
          ('SMA-0 (1-30)', const Color(0xFF34D399), _num(prev, 'demand_1_30'),
              _num(prev, 'collection_1_30'), _num(cur, 'demand_1_30'),
              _num(cur, 'collection_1_30')),
          ('SMA-1 (31-60)', AppColors.warning, _num(prev, 'demand_31_60'),
              _num(prev, 'collection_31_60'), _num(cur, 'demand_31_60'),
              _num(cur, 'collection_31_60')),
          ('Pre-NPA', const Color(0xFFFB923C), _num(prev, 'pnpa_demand'),
              _num(prev, 'pnpa_collection'), _num(cur, 'pnpa_demand'),
              _num(cur, 'pnpa_collection')),
          ('NPA', AppColors.danger, _num(prev, 'npa_cases'),
              _num(prev, 'npa_act_acc'), _num(cur, 'npa_cases'),
              _num(cur, 'npa_act_acc')),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _navigator(
                curDay.label,
                '${prevDay != null ? _fmtDate(prevDay.date) : 'No data'}  vs  ${_fmtDate(curDay.date)}',
                idx,
                lastIdx),
            const SizedBox(height: 14),
            _CompareHeader(prev: model.months.prev.name, cur: model.months.cur.name),
            const SizedBox(height: 8),
            for (final b in buckets)
              _CollBucketRow(
                name: b.$1,
                color: b.$2,
                pD: b.$3,
                pC: b.$4,
                cD: b.$5,
                cC: b.$6,
              ),
          ],
        );
      },
    );
  }

  // Disbursement ---------------------------------------------------------------

  Widget _disbursement() {
    final async = ref.watch(_disbCompareProvider(_scope));
    return async.when(
      loading: () => const AppLoadingBlock(height: 240),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(_disbCompareProvider(_scope)),
      ),
      data: (model) {
        if (model == null || model.days.isEmpty) {
          return const MisInlineEmpty('No disbursement data available.');
        }
        // Default to the latest current-month day with data.
        var def = model.days.length - 1;
        for (var i = model.days.length - 1; i >= 0; i--) {
          if (model.curMap.containsKey(model.days[i])) {
            def = i;
            break;
          }
        }
        final lastIdx = model.days.length - 1;
        final idx = _dayIdx < 0 ? def : _dayIdx.clamp(0, lastIdx);
        final day = model.days[idx];
        final p = model.prevMap[day];
        final c = model.curMap[day];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _navigator(
                'Day $day',
                '${p != null ? '${_ordinal(day)} ${_monthNames[model.months.prev.month]}' : 'No data'}  vs  ${c != null ? '${_ordinal(day)} ${_monthNames[model.months.cur.month]}' : 'No data'}',
                idx,
                lastIdx),
            const SizedBox(height: 14),
            _CompareHeader(
                prev: model.months.prev.name, cur: model.months.cur.name),
            const SizedBox(height: 8),
            _DisbBucketRow(
              name: 'Accounts',
              color: AppColors.primary,
              pVal: p?.accounts,
              cVal: c?.accounts,
              fmt: _fmtNum,
            ),
            _DisbBucketRow(
              name: 'Amount',
              color: AppColors.warning,
              pVal: p?.amount,
              cVal: c?.amount,
              fmt: _fmtCr,
            ),
          ],
        );
      },
    );
  }
}

class _CompareHeader extends StatelessWidget {
  const _CompareHeader({required this.prev, required this.cur});
  final String prev, cur;

  @override
  Widget build(BuildContext context) {
    Widget h(String t, Color c) => Expanded(
          child: Text(t,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: c,
                  letterSpacing: 0.5)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const SizedBox(width: 96),
          h(prev.toUpperCase(), AppColors.pink),
          h(cur.toUpperCase(), AppColors.success),
          const SizedBox(width: 66,
              child: Text('Δ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted))),
        ],
      ),
    );
  }
}

class _CollBucketRow extends StatelessWidget {
  const _CollBucketRow({
    required this.name,
    required this.color,
    required this.pD,
    required this.pC,
    required this.cD,
    required this.cC,
  });
  final String name;
  final Color color;
  final double pD, pC, cD, cC;

  @override
  Widget build(BuildContext context) {
    final pBal = pD - pC, cBal = cD - cC;
    final diff = cBal - pBal;
    final improved = diff <= 0;
    final dColor = improved ? AppColors.success : AppColors.danger;

    Widget side(double bal, double d, double c) => Expanded(
          child: Column(
            children: [
              Text(_fmtNum(bal),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFEA8C3F))),
              Text(_pctStr(d, c),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _pctColor(d, c))),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Row(
              children: [
                Container(width: 4, height: 30, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                ),
              ],
            ),
          ),
          side(pBal, pD, pC),
          side(cBal, cD, cC),
          SizedBox(
            width: 66,
            child: Column(
              children: [
                Text(
                  '${diff < 0 ? '▼ ' : diff > 0 ? '▲ ' : ''}${_fmtNum(diff.abs())}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: dColor),
                ),
                Text(improved ? 'Improved' : 'Higher',
                    style: TextStyle(fontSize: 8.5, color: dColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisbBucketRow extends StatelessWidget {
  const _DisbBucketRow({
    required this.name,
    required this.color,
    required this.pVal,
    required this.cVal,
    required this.fmt,
  });
  final String name;
  final Color color;
  final double? pVal, cVal;
  final String Function(num) fmt;

  @override
  Widget build(BuildContext context) {
    Widget side(double? v) => Expanded(
          child: Text(v != null ? fmt(v) : '-',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFEA8C3F))),
        );

    Widget diff() {
      if (pVal != null && cVal != null) {
        final d = pVal! != 0 ? (cVal! - pVal!) / pVal! * 100 : 0.0;
        final higher = (cVal! - pVal!) >= 0;
        final color = higher ? AppColors.success : AppColors.danger;
        return Column(
          children: [
            Text('${d > 0 ? '▲ ' : d < 0 ? '▼ ' : ''}${d.abs().toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            Text(higher ? 'Higher' : 'Lower',
                style: TextStyle(fontSize: 8.5, color: color)),
          ],
        );
      }
      if (pVal == null && cVal != null) {
        return const Text('new',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary));
      }
      if (pVal != null && cVal == null) {
        return const Text('missing',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.danger));
      }
      return const Text('-', style: TextStyle(color: AppColors.muted));
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Row(
              children: [
                Container(width: 4, height: 30, color: color),
                const SizedBox(width: 8),
                Text(name,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ],
            ),
          ),
          side(pVal),
          side(cVal),
          SizedBox(width: 66, child: Center(child: diff())),
        ],
      ),
    );
  }
}
