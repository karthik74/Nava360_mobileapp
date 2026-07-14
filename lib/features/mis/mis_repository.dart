// ─────────────────────────────────────────────────────────────────────────────
//  MIS (Grow With Me) repository + Riverpod providers.
//
//  All calls go through MisApiClient (its own Dio, `Token` auth, raw JSON). Data
//  is computed and scoped server-side to the logged-in user's tier, so the app
//  renders responses as-is. Drill hierarchy: region → division → area → branch →
//  employee; the active level is derived from which parent fields are set.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mis_api_client.dart';
import 'mis_models.dart';

// ── parse helpers ────────────────────────────────────────────────────────────

List<T> _list<T>(dynamic d, T Function(Map<String, dynamic>) f) => d is List
    ? d.whereType<Map>().map((m) => f(m.cast<String, dynamic>())).toList()
    : <T>[];

List<String> _strList(dynamic d) =>
    d is List ? d.map((e) => e.toString()).toList() : <String>[];

// ── Overview (dashboard) ─────────────────────────────────────────────────────

/// Hierarchy drill scope for the overview feed (names, not ids). Empty ⇒ own tier.
class MisDrill {
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  const MisDrill({this.region, this.division, this.area, this.branch});

  Map<String, dynamic> toMap() => {
        if (region != null) 'region': region,
        if (division != null) 'division': division,
        if (area != null) 'area': area,
        if (branch != null) 'branch': branch,
      };

  @override
  bool operator ==(Object other) =>
      other is MisDrill &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch;

  @override
  int get hashCode => Object.hash(region, division, area, branch);
}

// ── Collection ───────────────────────────────────────────────────────────────

class CollectionQuery {
  final String? date;
  final String product; // "" = All
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  final String? emp; // emp_id of an opened officer
  const CollectionQuery({
    this.date,
    this.product = '',
    this.region,
    this.division,
    this.area,
    this.branch,
    this.emp,
  });

  /// The drill grid level (one below the deepest set parent).
  String get level => branch != null
      ? 'employee'
      : area != null
          ? 'branch'
          : division != null
              ? 'area'
              : region != null
                  ? 'division'
                  : 'region';

  @override
  bool operator ==(Object other) =>
      other is CollectionQuery &&
      other.date == date &&
      other.product == product &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch &&
      other.emp == emp;

  @override
  int get hashCode =>
      Object.hash(date, product, region, division, area, branch, emp);
}

// ── Portfolio ────────────────────────────────────────────────────────────────

class PortfolioQuery {
  final String? month;
  final String product;
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  const PortfolioQuery({
    this.month,
    this.product = '',
    this.region,
    this.division,
    this.area,
    this.branch,
  });

  // Portfolio drills to the FO/officer level; the backend names it `officer`
  // (NOT `employee` — cf. the collection/disbursement endpoints).
  String get level => branch != null
      ? 'officer'
      : area != null
          ? 'branch'
          : division != null
              ? 'area'
              : region != null
                  ? 'division'
                  : 'region';

  Map<String, dynamic> get parent => {
        if (region != null) 'region': region,
        if (division != null) 'division': division,
        if (area != null) 'area': area,
        if (branch != null) 'branch': branch,
      };

  @override
  bool operator ==(Object other) =>
      other is PortfolioQuery &&
      other.month == month &&
      other.product == product &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch;

  @override
  int get hashCode =>
      Object.hash(month, product, region, division, area, branch);
}

// ── Disbursement ─────────────────────────────────────────────────────────────

class DisbQuery {
  final String? month;
  final String product;
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  const DisbQuery({
    this.month,
    this.product = '',
    this.region,
    this.division,
    this.area,
    this.branch,
  });

  String get level => branch != null
      ? 'employee'
      : area != null
          ? 'branch'
          : division != null
              ? 'area'
              : region != null
                  ? 'division'
                  : 'region';

  Map<String, dynamic> get parent => {
        if (region != null) 'region': region,
        if (division != null) 'division': division,
        if (area != null) 'area': area,
        if (branch != null) 'branch': branch,
      };

  @override
  bool operator ==(Object other) =>
      other is DisbQuery &&
      other.month == month &&
      other.product == product &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch;

  @override
  int get hashCode =>
      Object.hash(month, product, region, division, area, branch);
}

class DisbTrendQuery {
  final String? month; // "YYYY-MM"
  final String product;
  // Optional scope (names) — used by the Comparison screen's filter.
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  const DisbTrendQuery({
    this.month,
    this.product = '',
    this.region,
    this.division,
    this.area,
    this.branch,
  });

  Map<String, dynamic> get scope => {
        if (region != null) 'region': region,
        if (division != null) 'division': division,
        if (area != null) 'area': area,
        if (branch != null) 'branch': branch,
      };

  @override
  bool operator ==(Object other) =>
      other is DisbTrendQuery &&
      other.month == month &&
      other.product == product &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch;

  @override
  int get hashCode =>
      Object.hash(month, product, region, division, area, branch);
}

class DisbDailyQuery {
  final String? date;
  final String range; // ftd | mtd
  final String product;
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  const DisbDailyQuery({
    this.date,
    this.range = 'ftd',
    this.product = '',
    this.region,
    this.division,
    this.area,
    this.branch,
  });

  String get level => branch != null
      ? 'employee'
      : area != null
          ? 'branch'
          : division != null
              ? 'area'
              : region != null
                  ? 'division'
                  : 'region';

  Map<String, dynamic> get parent => {
        if (region != null) 'region': region,
        if (division != null) 'division': division,
        if (area != null) 'area': area,
        if (branch != null) 'branch': branch,
      };

  @override
  bool operator ==(Object other) =>
      other is DisbDailyQuery &&
      other.date == date &&
      other.range == range &&
      other.product == product &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch;

  @override
  int get hashCode =>
      Object.hash(date, range, product, region, division, area, branch);
}

// ── Analytical ("Lowest 10%") ────────────────────────────────────────────────

/// Collection analytical bucket field pairs (demand, collection) summed for MTD.
const List<(String, String)> _analyticalFields = [
  ('regular_demand', 'regular_collection'),
  ('demand_1_30', 'collection_1_30'),
  ('demand_31_60', 'collection_31_60'),
  ('pnpa_demand', 'pnpa_collection'),
  ('npa_cases', 'npa_clo_acc'),
];

class AnalyticalQuery {
  final String mode; // collection | disbursement
  final String range; // ftd | mtd (collection only)
  final String level; // region | division | area | branch | employee
  final String? date;
  final String? month;
  final Map<String, dynamic> parent; // drilled ancestors (level -> name)
  final String parentKey; // canonical string of `parent` for equality
  const AnalyticalQuery({
    required this.mode,
    required this.range,
    required this.level,
    this.date,
    this.month,
    this.parent = const {},
    this.parentKey = '',
  });

  @override
  bool operator ==(Object other) =>
      other is AnalyticalQuery &&
      other.mode == mode &&
      other.range == range &&
      other.level == level &&
      other.date == date &&
      other.month == month &&
      other.parentKey == parentKey;

  @override
  int get hashCode => Object.hash(mode, range, level, date, month, parentKey);
}

// ── Repository ───────────────────────────────────────────────────────────────

class MisRepository {
  MisRepository(this._api);
  final MisApiClient _api;

  String? _p(String v) => v.isEmpty ? null : v;

  // Overview -------------------------------------------------------------------
  Future<OverviewTable> overview(MisDrill drill) => _api.get<OverviewTable>(
        '/overview',
        query: drill.toMap(),
        parse: OverviewTable.fromJson,
      );

  // Collection -----------------------------------------------------------------
  Future<List<String>> collectionDates() => _api.get(
        '/collection/dates',
        query: {'grain': 2},
        parse: _strList,
      );

  Future<CollectionSummary> collectionSummary(CollectionQuery q) => _api.get(
        '/collection/summary',
        query: {
          'date': q.date,
          'product': _p(q.product),
          'region': q.region,
          'division': q.division,
          'area': q.area,
          'branch': q.branch,
          'emp_id': q.emp,
        },
        parse: CollectionSummary.fromJson,
      );

  Future<List<CollectionRow>> collectionList(CollectionQuery q) {
    final product = _p(q.product);
    switch (q.level) {
      case 'division':
        return _api.get('/collection/by-division',
            query: {'date': q.date, 'region': q.region, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'area':
        return _api.get('/collection/by-area',
            query: {'date': q.date, 'division': q.division, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'branch':
        return _api.get('/collection/by-branch',
            query: {'date': q.date, 'area': q.area, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'employee':
        return _api.get('/collection/by-employee',
            query: {'date': q.date, 'branch': q.branch, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'region':
      default:
        return _api.get('/collection/by-region',
            query: {'date': q.date, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
    }
  }

  // Portfolio ------------------------------------------------------------------
  Future<List<String>> portfolioMonths() =>
      _api.get('/portfolio/months', parse: _strList);

  Future<PortfolioSummary> portfolioSummary(PortfolioQuery q) => _api.get(
        '/portfolio/summary',
        query: {
          'month': q.month,
          'product': _p(q.product),
          ...q.parent,
        },
        parse: PortfolioSummary.fromJson,
      );

  Future<List<PortfolioUnitRow>> portfolioUnits(PortfolioQuery q) => _api.get(
        '/portfolio/by-unit',
        query: {
          'month': q.month,
          'level': q.level,
          'product': _p(q.product),
          ...q.parent,
        },
        parse: (d) => _list(d, PortfolioUnitRow.fromJson),
      );

  // Disbursement ---------------------------------------------------------------
  Future<List<String>> disbursementMonths() =>
      _api.get('/disbursement/months', parse: _strList);

  Future<DisbSummary> disbursementSummary(DisbQuery q) => _api.get(
        '/disbursement/summary',
        query: {'month': q.month, 'product': _p(q.product), ...q.parent},
        parse: DisbSummary.fromJson,
      );

  Future<List<DisbProductRow>> disbursementByProduct(DisbQuery q) => _api.get(
        '/disbursement/by-product',
        query: {'month': q.month, ...q.parent},
        parse: (d) => _list(d, DisbProductRow.fromJson),
      );

  Future<List<DisbUnitRow>> disbursementUnits(DisbQuery q) => _api.get(
        '/disbursement/by-unit',
        query: {
          'month': q.month,
          'level': q.level,
          'product': _p(q.product),
          ...q.parent,
        },
        parse: (d) => _list(d, DisbUnitRow.fromJson),
      );

  Future<List<DisbTrendRow>> disbursementDailyTrend(DisbTrendQuery q) =>
      _api.get(
        '/disbursement/daily/trend',
        query: {'month': q.month, 'product': _p(q.product), ...q.scope},
        parse: (d) => _list(d, DisbTrendRow.fromJson),
      );

  Future<List<String>> disbursementDailyDates() =>
      _api.get('/disbursement/daily/dates', parse: _strList);

  Future<DisbSummary> disbursementDailySummary(DisbDailyQuery q) => _api.get(
        '/disbursement/daily/summary',
        query: {
          'date': q.date,
          'range': q.range,
          'product': _p(q.product),
          ...q.parent,
        },
        parse: DisbSummary.fromJson,
      );

  Future<List<DisbUnitRow>> disbursementDailyUnits(DisbDailyQuery q) => _api.get(
        '/disbursement/daily/by-unit',
        query: {
          'date': q.date,
          'level': q.level,
          'range': q.range,
          'product': _p(q.product),
          ...q.parent,
        },
        parse: (d) => _list(d, DisbUnitRow.fromJson),
      );

  // Hourly (intra-day collection) ----------------------------------------------
  Future<List<String>> hourlyDates() =>
      _api.get('/hourly/dates', parse: _strList);

  Future<CollectionSummary> hourlySummary(CollectionQuery q) => _api.get(
        '/hourly/summary',
        query: {
          'date': q.date,
          'product': _p(q.product),
          'region': q.region,
          'division': q.division,
          'area': q.area,
          'branch': q.branch,
        },
        parse: CollectionSummary.fromJson,
      );

  Future<List<CollectionRow>> hourlyList(CollectionQuery q) {
    final product = _p(q.product);
    switch (q.level) {
      case 'division':
        return _api.get('/hourly/by-division',
            query: {'date': q.date, 'region': q.region, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'area':
        return _api.get('/hourly/by-area',
            query: {'date': q.date, 'division': q.division, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'branch':
        return _api.get('/hourly/by-branch',
            query: {'date': q.date, 'area': q.area, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'employee':
        return _api.get('/hourly/by-employee',
            query: {'date': q.date, 'branch': q.branch, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'region':
      default:
        return _api.get('/hourly/by-region',
            query: {'date': q.date, 'product': product},
            parse: (d) => _list(d, CollectionRow.fromJson));
    }
  }

  // Analytical -----------------------------------------------------------------
  Future<List<AnalyticalRow>> _collectionAnalytical(String date, String level) =>
      _api.get('/collection/analytical',
          query: {'date': date, 'level': level},
          parse: (d) => d is List
              ? d
                  .whereType<Map>()
                  .map((m) => AnalyticalRow(m.cast<String, dynamic>()))
                  .toList()
              : <AnalyticalRow>[]);

  /// MTD = sum the month's analytical rows up to (and including) the date,
  /// merged per unit client-side (the endpoint only accepts a single date).
  Future<List<AnalyticalRow>> _collectionAnalyticalMtd(
      String date, String level) async {
    final dates = await collectionDates();
    final prefix = date.length >= 7 ? date.substring(0, 7) : date;
    final monthDates = dates
        .where((d) =>
            d.length >= 7 &&
            d.substring(0, 7) == prefix &&
            d.compareTo(date) <= 0)
        .toList();
    final merged = <String, Map<String, dynamic>>{};
    for (final d in monthDates) {
      final rows = await _collectionAnalytical(d, level);
      for (final r in rows) {
        final key = r.empId ?? r.unit;
        if (key == null) continue;
        final cur =
            merged.putIfAbsent(key, () => {'unit': r.unit, 'emp_id': r.empId});
        for (final f in _analyticalFields) {
          cur[f.$1] = (misToDouble(cur[f.$1]) ?? 0) + r.field(f.$1);
          cur[f.$2] = (misToDouble(cur[f.$2]) ?? 0) + r.field(f.$2);
        }
      }
    }
    return merged.values.map(AnalyticalRow.new).toList();
  }

  Future<List<AnalyticalRow>> analyticalRows(AnalyticalQuery q) async {
    if (q.mode == 'disbursement') {
      if (q.month == null) return [];
      return _api.get('/disbursement/by-unit',
          query: {'month': q.month, 'level': q.level, ...q.parent},
          parse: (d) => d is List
              ? d
                  .whereType<Map>()
                  .map((m) => AnalyticalRow(m.cast<String, dynamic>()))
                  .toList()
              : <AnalyticalRow>[]);
    }
    if (q.date == null) return [];
    return q.range == 'mtd'
        ? _collectionAnalyticalMtd(q.date!, q.level)
        : _collectionAnalytical(q.date!, q.level);
  }

  Future<int> analyticalWorking(AnalyticalQuery q) {
    if (q.date == null) return Future.value(0);
    return _api.get('/employees/working-counts',
        query: {'date': q.date, 'level': q.level, ...q.parent},
        parse: (d) => misToInt((d is Map ? d['working'] : null)) ?? 0);
  }

  // Comparison -----------------------------------------------------------------
  Future<CompareDailyResponse> compareDaily(
    String from,
    String to, {
    String? region,
    String? division,
    String? area,
    String? branch,
  }) =>
      _api.get(
        '/comparison/daily',
        query: {
          'from': from,
          'to': to,
          if (region != null) 'region': region,
          if (division != null) 'division': division,
          if (area != null) 'area': area,
          if (branch != null) 'branch': branch,
        },
        parse: CompareDailyResponse.fromJson,
      );

  // Hierarchy (cascading scope filter options) ---------------------------------
  Future<List<HierOption>> regions() => _api.get(
        '/regions',
        parse: (d) => d is List
            ? d
                .whereType<Map>()
                .map((m) => HierOption.from(
                    m.cast<String, dynamic>(), 'region_id', 'region_name'))
                .toList()
            : <HierOption>[],
      );

  Future<List<HierOption>> divisions(String regionId) => _api.get(
        '/divisions',
        query: {'region_id': regionId},
        parse: (d) => d is List
            ? d
                .whereType<Map>()
                .map((m) => HierOption.from(
                    m.cast<String, dynamic>(), 'division_id', 'division_name'))
                .toList()
            : <HierOption>[],
      );

  Future<List<HierOption>> areas(String divisionId) => _api.get(
        '/areas',
        query: {'division_id': divisionId},
        parse: (d) => d is List
            ? d
                .whereType<Map>()
                .map((m) => HierOption.from(
                    m.cast<String, dynamic>(), 'area_id', 'area_name'))
                .toList()
            : <HierOption>[],
      );

  Future<List<HierOption>> branches(String areaId) => _api.get(
        '/branches',
        query: {'area_id': areaId},
        parse: (d) => d is List
            ? d
                .whereType<Map>()
                .map((m) => HierOption.from(
                    m.cast<String, dynamic>(), 'branch_id', 'branch_name'))
                .toList()
            : <HierOption>[],
      );

  // Daily Plan (write) ---------------------------------------------------------
  Future<List<DailyPlanBranch>> dailyPlanBranches() => _api.get(
        '/daily-plan/branches',
        parse: (d) => _list(d, DailyPlanBranch.fromJson),
      );

  Future<DailyPlanMine> dailyPlanMine(String date, String type,
          [String? branch]) =>
      _api.get('/daily-plan/mine',
          query: {'date': date, 'type': type, 'branch': branch},
          parse: DailyPlanMine.fromJson);

  Future<void> dailyPlanSave(Map<String, dynamic> payload) =>
      _api.post('/daily-plan/save', body: payload, parse: (_) {});

  // Feedback (write) -----------------------------------------------------------
  Future<List<FeedbackItem>> listFeedback() =>
      _api.get('/feedback', parse: (d) => _list(d, FeedbackItem.fromJson));

  Future<void> submitFeedback(String category, String title, String body) =>
      _api.post('/feedback',
          body: {'category': category, 'title': title, 'body': body},
          parse: (_) {});

  // Employees ------------------------------------------------------------------
  Future<EmployeeCounts> employeeCount() =>
      _api.get('/employees/count', parse: EmployeeCounts.fromJson);

  Future<List<EmployeeRow>> listEmployees(String q) => _api.get(
        '/employees',
        query: {'q': q, 'limit': 500, 'offset': 0},
        parse: (d) => _list(d, EmployeeRow.fromJson),
      );

  Future<Employee> getEmployee(String empId) => _api.get(
        '/employees/${Uri.encodeComponent(empId)}',
        parse: Employee.fromJson,
      );

  Future<EmployeePersonal> getEmployeePersonal(String empId) => _api.get(
        '/employees/${Uri.encodeComponent(empId)}/personal',
        parse: EmployeePersonal.fromJson,
      );

  // Locations ------------------------------------------------------------------
  Future<List<BranchLocationRow>> branchLocations() => _api.get(
        '/locations/branches',
        parse: (d) => _list(d, BranchLocationRow.fromJson),
      );
}

final misRepositoryProvider = Provider<MisRepository>(
  (ref) => MisRepository(ref.watch(misApiClientProvider)),
);

// ── Providers ────────────────────────────────────────────────────────────────

final misOverviewProvider =
    FutureProvider.autoDispose.family<OverviewTable, MisDrill>(
  (ref, drill) => ref.watch(misRepositoryProvider).overview(drill),
);

final misCollectionDatesProvider =
    FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(misRepositoryProvider).collectionDates(),
);
final misCollectionSummaryProvider =
    FutureProvider.autoDispose.family<CollectionSummary, CollectionQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).collectionSummary(q),
);
final misCollectionListProvider =
    FutureProvider.autoDispose.family<List<CollectionRow>, CollectionQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).collectionList(q),
);

final misPortfolioMonthsProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(misRepositoryProvider).portfolioMonths(),
);
final misPortfolioSummaryProvider =
    FutureProvider.autoDispose.family<PortfolioSummary, PortfolioQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).portfolioSummary(q),
);
final misPortfolioUnitsProvider =
    FutureProvider.autoDispose.family<List<PortfolioUnitRow>, PortfolioQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).portfolioUnits(q),
);

final misDisbMonthsProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(misRepositoryProvider).disbursementMonths(),
);
final misDisbSummaryProvider =
    FutureProvider.autoDispose.family<DisbSummary, DisbQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).disbursementSummary(q),
);
final misDisbByProductProvider =
    FutureProvider.autoDispose.family<List<DisbProductRow>, DisbQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).disbursementByProduct(q),
);
final misDisbUnitsProvider =
    FutureProvider.autoDispose.family<List<DisbUnitRow>, DisbQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).disbursementUnits(q),
);
final misDisbDailyTrendProvider =
    FutureProvider.autoDispose.family<List<DisbTrendRow>, DisbTrendQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).disbursementDailyTrend(q),
);
final misDisbDailyDatesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(misRepositoryProvider).disbursementDailyDates(),
);
final misDisbDailySummaryProvider =
    FutureProvider.autoDispose.family<DisbSummary, DisbDailyQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).disbursementDailySummary(q),
);
final misDisbDailyUnitsProvider =
    FutureProvider.autoDispose.family<List<DisbUnitRow>, DisbDailyQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).disbursementDailyUnits(q),
);

final misHourlyDatesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(misRepositoryProvider).hourlyDates(),
);
final misHourlySummaryProvider =
    FutureProvider.autoDispose.family<CollectionSummary, CollectionQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).hourlySummary(q),
);
final misHourlyListProvider =
    FutureProvider.autoDispose.family<List<CollectionRow>, CollectionQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).hourlyList(q),
);

final misAnalyticalRowsProvider =
    FutureProvider.autoDispose.family<List<AnalyticalRow>, AnalyticalQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).analyticalRows(q),
);
final misAnalyticalWorkingProvider =
    FutureProvider.autoDispose.family<int, AnalyticalQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).analyticalWorking(q),
);

final misDailyPlanBranchesProvider =
    FutureProvider.autoDispose<List<DailyPlanBranch>>(
  (ref) => ref.watch(misRepositoryProvider).dailyPlanBranches(),
);

final misFeedbackProvider = FutureProvider.autoDispose<List<FeedbackItem>>(
  (ref) => ref.watch(misRepositoryProvider).listFeedback(),
);

final misEmployeeCountProvider = FutureProvider.autoDispose<EmployeeCounts>(
  (ref) => ref.watch(misRepositoryProvider).employeeCount(),
);
final misEmployeeListProvider =
    FutureProvider.autoDispose.family<List<EmployeeRow>, String>(
  (ref, q) => ref.watch(misRepositoryProvider).listEmployees(q),
);
final misEmployeeProvider =
    FutureProvider.autoDispose.family<Employee, String>(
  (ref, id) => ref.watch(misRepositoryProvider).getEmployee(id),
);
final misEmployeePersonalProvider =
    FutureProvider.autoDispose.family<EmployeePersonal, String>(
  (ref, id) => ref.watch(misRepositoryProvider).getEmployeePersonal(id),
);
final misBranchLocationsProvider =
    FutureProvider.autoDispose<List<BranchLocationRow>>(
  (ref) => ref.watch(misRepositoryProvider).branchLocations(),
);

// Cascading scope-filter options (child level loaded by parent id).
final misRegionsProvider = FutureProvider.autoDispose<List<HierOption>>(
  (ref) => ref.watch(misRepositoryProvider).regions(),
);
final misDivisionsProvider =
    FutureProvider.autoDispose.family<List<HierOption>, String>(
  (ref, regionId) => ref.watch(misRepositoryProvider).divisions(regionId),
);
final misAreasProvider =
    FutureProvider.autoDispose.family<List<HierOption>, String>(
  (ref, divisionId) => ref.watch(misRepositoryProvider).areas(divisionId),
);
final misBranchesProvider =
    FutureProvider.autoDispose.family<List<HierOption>, String>(
  (ref, areaId) => ref.watch(misRepositoryProvider).branches(areaId),
);
