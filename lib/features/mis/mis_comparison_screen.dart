// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Comparison (route /mis/comparison). Month-over-month, previous vs
//  current, day by day. Collection pairs days by weekday-occurrence (1st Mon ↔
//  1st Mon), de-cumulates the cumulative MTD figures into daily contributions
//  and re-accumulates per label; Disbursement pairs by day-of-month. Ports
//  ComparisonScreen.tsx — the card view walks one paired day at a time, the
//  table view (toggle, top right) shows the whole month like the web's tables,
//  with the same sortable Day / date columns.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart' show MisPalette;
import 'mis_comparison_tables.dart';
import 'mis_format.dart';
import 'mis_matrix_table.dart' show MisFootNote;
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

  /// Every weekday-occurrence label in the two months ("1 - Mon" … "5 - Sun"),
  /// in occurrence order — the table's row set (the cards walk `curDays`).
  final List<String> allLabels;

  /// Day-of-month of the newest current-month day that has data. Labels past it
  /// are "future": the previous month's figures show dimmed, not as a comparison.
  final int latestCurDayNum;

  const _CollModel(this.months, this.curDays, this.prevLabelMap,
      this.prevCumMap, this.curCumMap, this.allLabels, this.latestCurDayNum);
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

  return _CollModel(months, curDays, prevLabelMap, prevCumMap, curCumMap,
      allLabels, latestCurDayNum);
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

/// The collection card view's paired day, derived from the model + the
/// selected index (exactly the walk the card view always did).
class _CollDayView {
  final _CollModel model;
  final int idx, lastIdx;
  final _LabeledDay curDay;
  final _LabeledDay? prevDay;

  /// (name, colour, prev demand, prev collection, cur demand, cur collection).
  final List<(String, Color, double, double, double, double)> buckets;

  const _CollDayView(this.model, this.idx, this.lastIdx, this.curDay,
      this.prevDay, this.buckets);
}

/// The disbursement card view's paired day.
class _DisbDayView {
  final _DisbModel model;
  final int idx, lastIdx, day;
  final _DisbDay? p, c;
  const _DisbDayView(
      this.model, this.idx, this.lastIdx, this.day, this.p, this.c);
}

class MisComparisonScreen extends ConsumerStatefulWidget {
  const MisComparisonScreen({super.key});

  @override
  ConsumerState<MisComparisonScreen> createState() =>
      _MisComparisonScreenState();
}

class _MisComparisonScreenState extends ConsumerState<MisComparisonScreen> {
  bool _disb = false; // Collection | Disbursement sub-tab
  int _dayIdx = -1; // -1 ⇒ default to latest
  // Cards walk one paired day at a time; the table shows the whole month.
  bool _table = false;

  // Cascading scope filter (Region → Division → Area → Branch). The `id` loads
  // the next level; the NAMES are sent to the comparison endpoints.
  HierOption? _region, _division, _area, _branch;

  MisCompareScope get _scope => MisCompareScope(
        region: _region?.name,
        division: _division?.name,
        area: _area?.name,
        branch: _branch?.name,
      );

  _CollDayView? _collView(_CollModel? model) {
    if (model == null || model.curDays.isEmpty) return null;
    final lastIdx = model.curDays.length - 1;
    final idx = _dayIdx < 0 ? lastIdx : _dayIdx.clamp(0, lastIdx);
    final curDay = model.curDays[idx];
    final prevDay = model.prevLabelMap[curDay.label];
    final cur = model.curCumMap[curDay.label];
    final prev = model.prevCumMap[curDay.label];

    final buckets = <(String, Color, double, double, double, double)>[
      ('Regular (FTOD)', MisPalette.risk('regular'),
          _num(prev, 'regular_demand'), _num(prev, 'regular_collection'),
          _num(cur, 'regular_demand'), _num(cur, 'regular_collection')),
      ('SMA-0 (1-30)', MisPalette.risk('1_30'), _num(prev, 'demand_1_30'),
          _num(prev, 'collection_1_30'), _num(cur, 'demand_1_30'),
          _num(cur, 'collection_1_30')),
      ('SMA-1 (31-60)', MisPalette.risk('31_60'), _num(prev, 'demand_31_60'),
          _num(prev, 'collection_31_60'), _num(cur, 'demand_31_60'),
          _num(cur, 'collection_31_60')),
      ('Pre-NPA', MisPalette.risk('61_90'), _num(prev, 'pnpa_demand'),
          _num(prev, 'pnpa_collection'), _num(cur, 'pnpa_demand'),
          _num(cur, 'pnpa_collection')),
      ('NPA', MisPalette.risk('npa'), _num(prev, 'npa_cases'),
          _num(prev, 'npa_act_acc'), _num(cur, 'npa_cases'),
          _num(cur, 'npa_act_acc')),
    ];
    return _CollDayView(model, idx, lastIdx, curDay, prevDay, buckets);
  }

  _DisbDayView? _disbView(_DisbModel? model) {
    if (model == null || model.days.isEmpty) return null;
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
    return _DisbDayView(
        model, idx, lastIdx, day, model.prevMap[day], model.curMap[day]);
  }

  @override
  Widget build(BuildContext context) {
    final collAsync = _disb ? null : ref.watch(_collCompareProvider(_scope));
    final disbAsync = _disb ? ref.watch(_disbCompareProvider(_scope)) : null;
    final collView = _collView(collAsync?.valueOrNull);
    final disbView = _disbView(disbAsync?.valueOrNull);

    // Day navigator + headline figures for the paired day (cards and table
    // alike; the navigator only walks in the card view).
    String? navLabel, navSub, navPos, heroKey;
    int idx = 0, lastIdx = 0;
    List<ProStat>? stats;
    if (collView != null) {
      final m = collView.model;
      idx = collView.idx;
      lastIdx = collView.lastIdx;
      navLabel = collView.curDay.label;
      navSub =
          '${collView.prevDay != null ? _fmtDate(collView.prevDay!.date) : 'No data'}  vs  ${_fmtDate(collView.curDay.date)}';
      navPos = 'Day ${idx + 1} of ${m.curDays.length} with data this month';
      heroKey = 'Regular (FTOD) balance';
      final r = collView.buckets.first;
      final pBal = r.$3 - r.$4, cBal = r.$5 - r.$6;
      final diff = cBal - pBal;
      final improved = diff <= 0;
      stats = [
        ProStat(
          label: m.months.prev.name,
          value: _fmtNum(pBal),
          sub: '${_pctStr(r.$3, r.$4)} collected',
          dot: _prevDot,
        ),
        ProStat(
          label: m.months.cur.name,
          value: _fmtNum(cBal),
          sub: '${_pctStr(r.$5, r.$6)} collected',
          dot: Color.lerp(AppColors.primary, Colors.white, 0.45),
        ),
        ProStat(
          label: 'Change',
          value:
              '${diff < 0 ? '▼ ' : diff > 0 ? '▲ ' : ''}${_fmtNum(diff.abs())}',
          sub: improved ? 'Improved' : 'Higher',
          dot: improved ? AppColors.live : _badDot,
        ),
      ];
    } else if (disbView != null) {
      final m = disbView.model;
      final day = disbView.day;
      final p = disbView.p, c = disbView.c;
      idx = disbView.idx;
      lastIdx = disbView.lastIdx;
      navLabel = 'Day $day';
      navSub =
          '${p != null ? '${_ordinal(day)} ${_monthNames[m.months.prev.month]}' : 'No data'}  vs  ${c != null ? '${_ordinal(day)} ${_monthNames[m.months.cur.month]}' : 'No data'}';
      navPos = '${idx + 1} of ${m.days.length} days';
      heroKey = 'Disbursement amount';
      final change = _disbChange(p?.amount, c?.amount);
      stats = [
        ProStat(
          label: m.months.prev.name,
          value: p != null ? _fmtCr(p.amount) : '-',
          sub: p != null ? '${_fmtNum(p.accounts)} accounts' : 'No data',
          dot: _prevDot,
        ),
        ProStat(
          label: m.months.cur.name,
          value: c != null ? _fmtCr(c.amount) : '-',
          sub: c != null ? '${_fmtNum(c.accounts)} accounts' : 'No data',
          dot: Color.lerp(AppColors.primary, Colors.white, 0.45),
        ),
        ProStat(
          label: 'Change',
          value: change.$1,
          sub: change.$2,
          dot: change.$3,
        ),
      ];
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Comparison')),
      body: ProPage(
        onRefresh: () async {
          if (_disb) {
            ref.invalidate(_disbCompareProvider(_scope));
          } else {
            ref.invalidate(_collCompareProvider(_scope));
          }
        },
        hero: ProHero(
          title: 'Comparison',
          subtitle: 'Month-over-month — previous vs current, day by day.',
          children: [
            // Scope filter (above the sub-tabs).
            _scopeFilter(),
            Row(
              children: [
                Expanded(
                  child: ProHeroSegmented(
                    labels: const ['Collection', 'Disbursement'],
                    selected: _disb ? 1 : 0,
                    onChanged: (i) => setState(() {
                      _disb = i == 1;
                      _dayIdx = -1;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                _HeroViewToggle(
                  table: _table,
                  onChanged: (t) => setState(() => _table = t),
                ),
              ],
            ),
            if (!_table && navLabel != null)
              _navigator(navLabel, navSub ?? '', navPos ?? '', idx, lastIdx),
            if (stats != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroKicker(left: heroKey ?? '', right: navSub ?? ''),
                  const SizedBox(height: 8),
                  ProHeroStats(stats: stats),
                ],
              ),
          ],
        ),
        children: [
          if (_disb)
            ..._disbursement(disbAsync!, disbView)
          else
            ..._collection(collAsync!, collView),
        ],
      ),
    );
  }

  /// The disbursement "Change" figure — the card row's own rule: % change in
  /// amount, "new" / "missing" when only one month has the day.
  (String, String, Color) _disbChange(double? pVal, double? cVal) {
    if (pVal != null && cVal != null) {
      final d = pVal != 0 ? (cVal - pVal) / pVal * 100 : 0.0;
      final higher = (cVal - pVal) >= 0;
      return (
        '${d > 0 ? '▲ ' : d < 0 ? '▼ ' : ''}${d.abs().toStringAsFixed(1)}%',
        higher ? 'Higher' : 'Lower',
        higher ? AppColors.live : _badDot,
      );
    }
    if (pVal == null && cVal != null) return ('new', 'Amount', _prevDot);
    if (pVal != null && cVal == null) return ('missing', 'Amount', _badDot);
    return ('-', 'Amount', _prevDot);
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
      const gap = 8.0;
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
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => setState(() {
                _region = _division = _area = _branch = null;
              }),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xD1FFFFFF),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.close_rounded, size: 15),
              label: const Text('Reset filter'),
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
    return _HeroDropdown<String>(
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

  Widget _navigator(
      String label, String sub, String pos, int idx, int lastIdx) {
    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: ProHeroIconButton(icon: icon, tooltip: tip, onTap: onTap),
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, 'Previous day',
              idx <= 0 ? null : () => setState(() => _dayIdx = idx - 1)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xD6FFFFFF),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (pos.isNotEmpty)
                  Text(
                    pos,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0x99FFFFFF),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          arrow(Icons.chevron_right_rounded, 'Next day',
              idx >= lastIdx ? null : () => setState(() => _dayIdx = idx + 1)),
        ],
      ),
    );
  }

  // Collection -----------------------------------------------------------------

  List<Widget> _collection(
      AsyncValue<_CollModel?> async, _CollDayView? view) {
    return async.when(
      loading: () => const [AppLoadingBlock(height: 280)],
      error: (e, _) => [
        AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_collCompareProvider(_scope)),
        ),
      ],
      data: (model) {
        if (model == null || model.curDays.isEmpty || view == null) {
          return const [MisInlineEmpty('No daily collection data available.')];
        }
        if (_table) return _collectionTable(model);
        return [
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CompareHeader(
                    head: 'Bucket',
                    prev: model.months.prev.name,
                    cur: model.months.cur.name),
                for (final b in view.buckets)
                  _CollBucketRow(
                    name: b.$1,
                    color: b.$2,
                    pD: b.$3,
                    pC: b.$4,
                    cD: b.$5,
                    cC: b.$6,
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 12, 0, 10),
                  child: Text(
                    'Figures are the month-to-date balance (demand minus '
                    'collection) up to the paired day, with collection % '
                    'below. Days are paired by weekday: the 1st Monday '
                    'against the 1st Monday.',
                    style: TextStyle(
                        fontSize: 12, height: 1.42, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }

  /// The whole month at once: every weekday-occurrence label, each month's date
  /// and cumulative regular demand / collection. Sortable by Day or either date.
  List<Widget> _collectionTable(_CollModel model) {
    const dowOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final m = model.months;
    final rows = <MisCompareCollRow>[];

    for (final label in model.allLabels) {
      final parts = label.split(' - ');
      final occ = int.tryParse(parts[0]) ?? 0;
      final dayName = parts.length > 1 ? parts[1] : '';
      final prevNum =
          _getDateForLabel(m.prev.year, m.prev.month, dayName, occ);
      final curNum = _getDateForLabel(m.cur.year, m.cur.month, dayName, occ);
      final future = curNum == null || curNum > model.latestCurDayNum;

      final prevCum = model.prevCumMap[label];
      final curCum = model.curCumMap[label];
      // A label neither month reached is noise — the web skips it too, since
      // both sides render as dashes.
      if (prevCum == null && curCum == null && prevNum == null && curNum == null) {
        continue;
      }

      rows.add(MisCompareCollRow(
        label: label,
        occurrence: occ,
        dayIndex: dowOrder.indexOf(dayName),
        prevDateLabel: prevNum != null
            ? '${_ordinal(prevNum)} ${_monthNames[m.prev.month]}'
            : '-',
        curDateLabel: curNum != null
            ? '${_ordinal(curNum)} ${_monthNames[m.cur.month]}'
            : '-',
        prevDateNum: prevNum ?? 99,
        curDateNum: curNum ?? 99,
        prev: prevCum == null
            ? null
            : (
                demand: prevCum['regular_demand'] ?? 0,
                collection: prevCum['regular_collection'] ?? 0
              ),
        cur: curCum == null
            ? null
            : (
                demand: curCum['regular_demand'] ?? 0,
                collection: curCum['regular_collection'] ?? 0
              ),
        future: future,
      ));
    }

    if (rows.isEmpty) {
      return const [MisInlineEmpty('No daily collection data available.')];
    }
    return [
      ProSectionHeader(
        title: 'Collection · ${m.prev.name} vs ${m.cur.name}',
        trailing: const _SwipeHint(),
      ),
      MisCompareCollectionTable(
        rows: rows,
        prevMonth: m.prev.name,
        curMonth: m.cur.name,
        numberFormat: _fmtNum,
      ),
      const MisFootNote(
        'RD regular demand · RC regular collection · FTOD the gap, all '
        'month-to-date. Faded figures: the current month has not reached that '
        'day yet, so last month shows for reference only. Tap Day or Date to '
        'sort.',
      ),
    ];
  }

  /// Day-of-month rows with each month's accounts and CUMULATIVE amount, so the
  /// last row doubles as the month-to-date total, plus a month-over-month diff.
  List<Widget> _disbursementTable(_DisbModel model) {
    final m = model.months;
    var prevLastDay = 0, curLastDay = 0;
    for (final d in model.prevMap.keys) {
      if (d > prevLastDay) prevLastDay = d;
    }
    for (final d in model.curMap.keys) {
      if (d > curLastDay) curLastDay = d;
    }

    var prevCum = 0.0, curCum = 0.0;
    var totPAcc = 0.0, totCAcc = 0.0, totPAmt = 0.0, totCAmt = 0.0;
    final rows = <MisCompareDisbRow>[];

    for (final day in model.days) {
      final p = model.prevMap[day];
      final c = model.curMap[day];
      if (p != null) {
        totPAcc += p.accounts;
        totPAmt += p.amount;
        prevCum += p.amount;
      }
      if (c != null) {
        totCAcc += c.accounts;
        totCAmt += c.amount;
        curCum += c.amount;
      }
      rows.add(MisCompareDisbRow(
        day: day,
        prevDateLabel: '${_ordinal(day)} ${_monthNames[m.prev.month]}',
        curDateLabel: '${_ordinal(day)} ${_monthNames[m.cur.month]}',
        prevAccounts: p?.accounts,
        curAccounts: c?.accounts,
        prevAmount: day <= prevLastDay ? prevCum : null,
        curAmount: day <= curLastDay ? curCum : null,
        beyondCurrent: day > curLastDay,
      ));
    }

    return [
      ProSectionHeader(
        title: 'Disbursement · ${m.prev.name} vs ${m.cur.name}',
        trailing: const _SwipeHint(),
      ),
      MisCompareDisbursementTable(
        rows: rows,
        prevMonth: m.prev.name,
        curMonth: m.cur.name,
        totalPrevAccounts: totPAcc,
        totalCurAccounts: totCAcc,
        totalPrevAmount: totPAmt,
        totalCurAmount: totCAmt,
        numberFormat: _fmtNum,
        croreFormat: _fmtCr,
      ),
      const MisFootNote(
        'Amounts are cumulative through the month, so the last row is the '
        'month total.',
      ),
    ];
  }

  // Disbursement ---------------------------------------------------------------

  List<Widget> _disbursement(
      AsyncValue<_DisbModel?> async, _DisbDayView? view) {
    return async.when(
      loading: () => const [AppLoadingBlock(height: 240)],
      error: (e, _) => [
        AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_disbCompareProvider(_scope)),
        ),
      ],
      data: (model) {
        if (model == null || model.days.isEmpty || view == null) {
          return const [MisInlineEmpty('No disbursement data available.')];
        }
        if (_table) return _disbursementTable(model);
        final p = view.p;
        final c = view.c;

        return [
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CompareHeader(
                    head: 'Measure',
                    prev: model.months.prev.name,
                    cur: model.months.cur.name),
                _DisbBucketRow(
                  name: 'Accounts',
                  color: AppColors.primary,
                  pVal: p?.accounts,
                  cVal: c?.accounts,
                  fmt: _fmtNum,
                ),
                _DisbBucketRow(
                  name: 'Amount',
                  color: const Color(0xFFF2B347),
                  pVal: p?.amount,
                  cVal: c?.amount,
                  fmt: _fmtCr,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 12, 0, 10),
                  child: Text(
                    'Disbursement pairs days by date: the 5th against the 5th.',
                    style: TextStyle(
                        fontSize: 12, height: 1.42, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }
}

/// Stat dots: the previous month in a quiet grey, a worse change in red.
const Color _prevDot = Color(0xFFB9C7CA);
const Color _badDot = Color(0xFFE5484D);

/// "Regular (FTOD) balance · 3 Sep vs 1 Oct" line above the hero stats.
class _HeroKicker extends StatelessWidget {
  const _HeroKicker({required this.left, required this.right});
  final String left, right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xBDFFFFFF),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0x94FFFFFF),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Cards ↔ table toggle on the deep hero.
class _HeroViewToggle extends StatelessWidget {
  const _HeroViewToggle({required this.table, required this.onChanged});
  final bool table;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool active, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon,
                  size: 18,
                  color: active ? AppColors.deep : Colors.white70),
            ),
          ),
        );
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.view_agenda_outlined, !table, 'One day at a time',
              () => onChanged(false)),
          const SizedBox(width: 2),
          btn(Icons.table_rows_rounded, table, 'Whole month table',
              () => onChanged(true)),
        ],
      ),
    );
  }
}

/// A labelled dropdown styled for the deep hero: translucent box, small label
/// above the white value; the open menu stays a plain white list.
class _HeroDropdown<T> extends StatelessWidget {
  const _HeroDropdown({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          itemHeight: null,
          focusColor: Colors.transparent,
          dropdownColor: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: Color(0x99FFFFFF)),
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
          selectedItemBuilder: (context) => [
            for (final item in items)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: Color(0x9EFFFFFF),
                    ),
                  ),
                  DefaultTextStyle.merge(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.36,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    child: item.child,
                  ),
                ],
              ),
          ],
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// "Swipe for more" hint beside a wide table's title.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swipe_rounded, size: 14, color: AppColors.faint),
          SizedBox(width: 4),
          Text('Swipe for more',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.faint)),
        ],
      );
}

class _CompareHeader extends StatelessWidget {
  const _CompareHeader({
    required this.head,
    required this.prev,
    required this.cur,
  });
  final String head, prev, cur;

  @override
  Widget build(BuildContext context) {
    Widget h(String t, Color c) => Expanded(
          child: Text(t,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: c)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(head,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted)),
          ),
          h(prev, const Color(0xFF43585D)),
          h(cur, AppColors.primary),
          const SizedBox(
            width: 72,
            child: Text('Change',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

/// Name cell of a compare row: a short colour bar + the bucket name.
class _CompareName extends StatelessWidget {
  const _CompareName({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 96,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
            ),
          ],
        ),
      );
}

const TextStyle _bigFigure = TextStyle(
  fontSize: 17,
  height: 1.3,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.3,
  color: AppColors.ink,
  fontFeatures: [FontFeature.tabularFigures()],
);

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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_fmtNum(bal), style: _bigFigure),
              ),
              Text(_pctStr(d, c),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _pctColor(d, c),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          _CompareName(name: name, color: color),
          side(pBal, pD, pC),
          side(cBal, cD, cC),
          SizedBox(
            width: 72,
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${diff < 0 ? '▼ ' : diff > 0 ? '▲ ' : ''}${_fmtNum(diff.abs())}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: dColor,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                Text(improved ? 'Improved' : 'Higher',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: dColor)),
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
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v != null ? fmt(v) : '-',
                textAlign: TextAlign.center, style: _bigFigure),
          ),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text(higher ? 'Higher' : 'Lower',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w500, color: color)),
          ],
        );
      }
      if (pVal == null && cVal != null) {
        return Text('new',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary));
      }
      if (pVal != null && cVal == null) {
        return const Text('missing',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.danger));
      }
      return const Text('-', style: TextStyle(color: AppColors.faint));
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          _CompareName(name: name, color: color),
          side(pVal),
          side(cVal),
          SizedBox(width: 72, child: Center(child: diff())),
        ],
      ),
    );
  }
}
