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
  /// Loan product filter: `igl` | `fig` | `il`; null ⇒ all products.
  final String? product;
  const MisDrill(
      {this.region, this.division, this.area, this.branch, this.product});

  Map<String, dynamic> toMap() => {
        if (region != null) 'region': region,
        if (division != null) 'division': division,
        if (area != null) 'area': area,
        if (branch != null) 'branch': branch,
        if (product != null) 'product': product,
      };

  @override
  bool operator ==(Object other) =>
      other is MisDrill &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch &&
      other.product == product;

  @override
  int get hashCode => Object.hash(region, division, area, branch, product);
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

  /// Hourly only: replay a stored hour slot ("14"). Null reads the live grain
  /// (latest push) — an older backend that ignores the param still works.
  final String? hour;
  const CollectionQuery({
    this.date,
    this.product = '',
    this.region,
    this.division,
    this.area,
    this.branch,
    this.emp,
    this.hour,
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
      other.emp == emp &&
      other.hour == hour;

  @override
  int get hashCode =>
      Object.hash(date, product, region, division, area, branch, emp, hour);
}

// ── Branch Report ────────────────────────────────────────────────────────────

class BranchReportQuery {
  final String? branch; // null → the server resolves the caller's own branch
  final String? month; // "YYYY-MM-01"; null → the branch's latest month
  const BranchReportQuery({this.branch, this.month});

  @override
  bool operator ==(Object other) =>
      other is BranchReportQuery &&
      other.branch == branch &&
      other.month == month;

  @override
  int get hashCode => Object.hash(branch, month);
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

// ── Clients (customer detail behind a portfolio bucket) ──────────────────────

/// A `/clients/list` request: month + product + the open drill levels, one DPD
/// bucket, plus server-side search, sort and paging.
class ClientsQuery {
  /// Screen bucket key → the key the API expects. `pnpa` is the screen's name
  /// for SMA-2; the API also accepts `pnpa`, but `sma2` is the documented key.
  static const Map<String, String> _apiBucket = {'pnpa': 'sma2'};

  final String? month; // YYYY-MM
  final String product; // "" = All
  final String? region, division, area, branch;
  final String? officer; // source-system OfficerID
  /// Screen bucket key; "total" means every bucket in scope.
  final String bucket;
  final String query; // free-text search, "" = none
  final String? sort; // an exact source-workbook column name
  final bool ascending;
  final int limit;
  final int offset;

  const ClientsQuery({
    this.month,
    this.product = '',
    this.region,
    this.division,
    this.area,
    this.branch,
    this.officer,
    this.bucket = 'total',
    this.query = '',
    this.sort,
    this.ascending = false,
    this.limit = 25,
    this.offset = 0,
  });

  ClientsQuery copyWith({
    String? bucket,
    String? query,
    String? sort,
    bool? ascending,
    int? limit,
    int? offset,
    bool clearSort = false,
  }) =>
      ClientsQuery(
        month: month,
        product: product,
        region: region,
        division: division,
        area: area,
        branch: branch,
        officer: officer,
        bucket: bucket ?? this.bucket,
        query: query ?? this.query,
        sort: clearSort ? null : (sort ?? this.sort),
        ascending: ascending ?? this.ascending,
        limit: limit ?? this.limit,
        offset: offset ?? this.offset,
      );

  Map<String, dynamic> toQuery() => {
        'month': month,
        'product': product.isEmpty ? null : product,
        'region': region,
        'division': division,
        'area': area,
        'branch': branch,
        'officer': officer,
        // "total" = no bucket filter, i.e. every bucket in scope.
        'bucket': bucket == 'total' ? null : (_apiBucket[bucket] ?? bucket),
        'q': query.isEmpty ? null : query,
        'sort': sort,
        'dir': sort == null ? null : (ascending ? 'asc' : 'desc'),
        'limit': limit,
        'offset': offset,
      };

  @override
  bool operator ==(Object other) =>
      other is ClientsQuery &&
      other.month == month &&
      other.product == product &&
      other.region == region &&
      other.division == division &&
      other.area == area &&
      other.branch == branch &&
      other.officer == officer &&
      other.bucket == bucket &&
      other.query == query &&
      other.sort == sort &&
      other.ascending == ascending &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(
        month,
        product,
        region,
        division,
        area,
        branch,
        officer,
        bucket,
        query,
        sort,
        ascending,
        limit,
        offset,
      );
}

// ── Daily Plan (manager report surfaces) ─────────────────────────────────────

/// A `/daily-plan/rows` or `/daily-plan/pending-branches` request.
class DailyPlanReportQuery {
  final String date; // YYYY-MM-DD
  final String type; // plan | achievement
  const DailyPlanReportQuery(this.date, this.type);

  @override
  bool operator ==(Object other) =>
      other is DailyPlanReportQuery &&
      other.date == date &&
      other.type == type;

  @override
  int get hashCode => Object.hash(date, type);
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

// ── Analysis (leaderboard tool) ──────────────────────────────────────────────

class AnalysisQuery {
  final String mode; // collection | disbursement
  final String? date; // collection: the MTD-as-of date
  final String? month; // disbursement
  final String bucket; // collection only, but always sent (mirrors the web)
  final String product;
  const AnalysisQuery({
    required this.mode,
    this.date,
    this.month,
    this.bucket = 'regular',
    this.product = '',
  });

  @override
  bool operator ==(Object other) =>
      other is AnalysisQuery &&
      other.mode == mode &&
      other.date == date &&
      other.month == month &&
      other.bucket == bucket &&
      other.product == product;

  @override
  int get hashCode => Object.hash(mode, date, month, bucket, product);
}

// ── Branch Matrix ────────────────────────────────────────────────────────────

/// A `/branch-matrix` request: financial year + loan product filter.
class BranchMatrixQuery {
  final int? fy;
  /// Loan product filter: `igl` | `fig` | `il`; null ⇒ all products.
  final String? product;
  const BranchMatrixQuery({this.fy, this.product});

  @override
  bool operator ==(Object other) =>
      other is BranchMatrixQuery && other.fy == fy && other.product == product;

  @override
  int get hashCode => Object.hash(fy, product);
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
          'hour': q.hour,
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
    final hour = q.hour;
    switch (q.level) {
      case 'division':
        return _api.get('/hourly/by-division',
            query: {
              'date': q.date,
              'region': q.region,
              'product': product,
              'hour': hour,
            },
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'area':
        return _api.get('/hourly/by-area',
            query: {
              'date': q.date,
              'division': q.division,
              'product': product,
              'hour': hour,
            },
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'branch':
        return _api.get('/hourly/by-branch',
            query: {
              'date': q.date,
              'area': q.area,
              'product': product,
              'hour': hour,
            },
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'employee':
        return _api.get('/hourly/by-employee',
            query: {
              'date': q.date,
              'branch': q.branch,
              'product': product,
              'hour': hour,
            },
            parse: (d) => _list(d, CollectionRow.fromJson));
      case 'region':
      default:
        return _api.get('/hourly/by-region',
            query: {'date': q.date, 'product': product, 'hour': hour},
            parse: (d) => _list(d, CollectionRow.fromJson));
    }
  }

  /// Freshness of the live hourly snapshot (period date + hour slot, capture
  /// time). Metadata only — the figures come from the summary / by-* feeds.
  Future<HourlySnapshot> hourlySnapshot(String? date) => _api.get(
        '/hourly/snapshot',
        query: {'date': date},
        parse: HourlySnapshot.fromJson,
      );

  /// The hour slots stored for a date — drives the ?hour= replay switcher.
  /// Older API builds don't have /hourly/hours; the screen treats the error as
  /// "no switcher" and stays on the live path.
  Future<HourlyHoursMeta> hourlyHours(String? date) => _api.get(
        '/hourly/hours',
        query: {'date': date},
        parse: HourlyHoursMeta.fromJson,
      );

  // Branch Report (per-branch Report Card) --------------------------------------
  /// One call returns the whole card: scoped branch list, month-end portfolio,
  /// monthly performance and the projection seed. Branch/month omitted → the
  /// server resolves the caller's own branch and its latest month.
  Future<BranchReportResponse> branchReport(BranchReportQuery q) => _api.get(
        '/branch-report',
        query: {'branch': q.branch, 'month': q.month, 'months': '4'},
        parse: BranchReportResponse.fromJson,
      );

  // Clients (customer detail behind a portfolio bucket) -------------------------
  Future<ClientsListResponse> clientsList(ClientsQuery q) => _api.get(
        '/clients/list',
        query: q.toQuery(),
        parse: ClientsListResponse.fromJson,
      );

  // Analysis (leaderboard tool) --------------------------------------------------
  Future<AnalysisFilters> analysisFilters() =>
      _api.get('/analysis/filters', parse: AnalysisFilters.fromJson);

  Future<AnalysisLeaderboard> analysisLeaderboard(AnalysisQuery q) => _api.get(
        '/analysis/leaderboard',
        query: {
          'mode': q.mode,
          'date': q.date,
          'month': q.month,
          'bucket': q.bucket,
          'product': _p(q.product),
        },
        parse: AnalysisLeaderboard.fromJson,
      );

  /// The caller's own national rank at every level they belong to. Unscoped.
  Future<AnalysisMyRank> analysisMyRank(AnalysisQuery q) => _api.get(
        '/analysis/my-rank',
        query: {
          'mode': q.mode,
          'date': q.date,
          'month': q.month,
          'bucket': q.bucket,
          'product': _p(q.product),
        },
        parse: AnalysisMyRank.fromJson,
      );

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

  // Branch Matrix (full-access CEO/Director only; server 403s anyone else) -----
  /// One call returns every branch, every month in the selected financial
  /// year, every metric. Omit `fy` for the latest FY with data; omit
  /// `product` for all products.
  Future<BranchMatrixResponse> branchMatrix(BranchMatrixQuery q) => _api.get(
        '/branch-matrix',
        query: {'fy': q.fy, 'product': q.product},
        parse: BranchMatrixResponse.fromJson,
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

  // Daily Plan (read — manager report surfaces) --------------------------------

  /// Flat one-row-per-branch report feed, scoped. `{ rows: [...] }`.
  Future<List<DailyPlanReportRow>> dailyPlanRows(String date, String type) =>
      _api.get(
        '/daily-plan/rows',
        query: {'date': date, 'type': type},
        parse: (d) {
          final list = d is Map ? d['rows'] : d;
          return list is List
              ? list
                  .whereType<Map>()
                  .map((m) => DailyPlanReportRow(m.cast<String, dynamic>()))
                  .toList()
              : <DailyPlanReportRow>[];
        },
      );

  /// Branches in scope that have NOT submitted for a date/type, with the BM's
  /// name + phone for follow-up. `{ branches: [...] }`.
  Future<List<PendingBranch>> dailyPlanPending(String date, String type) =>
      _api.get(
        '/daily-plan/pending-branches',
        query: {'date': date, 'type': type},
        parse: (d) {
          final list = d is Map ? d['branches'] : d;
          return list is List
              ? list
                  .whereType<Map>()
                  .map((m) => PendingBranch.fromJson(m.cast<String, dynamic>()))
                  .toList()
              : <PendingBranch>[];
        },
      );

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

/// Live-snapshot freshness for the Hourly header. Keyed by date; the family
/// argument is nullable so "latest" (no date) is its own cache entry.
final misHourlySnapshotProvider =
    FutureProvider.autoDispose.family<HourlySnapshot, String?>(
  (ref, date) => ref.watch(misRepositoryProvider).hourlySnapshot(date),
);

/// Stored hour slots for the Hourly replay switcher, keyed by date.
final misHourlyHoursProvider =
    FutureProvider.autoDispose.family<HourlyHoursMeta, String?>(
  (ref, date) => ref.watch(misRepositoryProvider).hourlyHours(date),
);

final misBranchReportProvider =
    FutureProvider.autoDispose.family<BranchReportResponse, BranchReportQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).branchReport(q),
);

final misClientsProvider =
    FutureProvider.autoDispose.family<ClientsListResponse, ClientsQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).clientsList(q),
);

final misDailyPlanRowsProvider = FutureProvider.autoDispose
    .family<List<DailyPlanReportRow>, DailyPlanReportQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).dailyPlanRows(q.date, q.type),
);

final misDailyPlanPendingProvider = FutureProvider.autoDispose
    .family<List<PendingBranch>, DailyPlanReportQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).dailyPlanPending(q.date, q.type),
);

final misAnalysisFiltersProvider = FutureProvider.autoDispose<AnalysisFilters>(
  (ref) => ref.watch(misRepositoryProvider).analysisFilters(),
);
final misAnalysisLeaderboardProvider =
    FutureProvider.autoDispose.family<AnalysisLeaderboard, AnalysisQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).analysisLeaderboard(q),
);
final misAnalysisMyRankProvider =
    FutureProvider.autoDispose.family<AnalysisMyRank, AnalysisQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).analysisMyRank(q),
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

final misBranchMatrixProvider =
    FutureProvider.autoDispose.family<BranchMatrixResponse, BranchMatrixQuery>(
  (ref, q) => ref.watch(misRepositoryProvider).branchMatrix(q),
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
