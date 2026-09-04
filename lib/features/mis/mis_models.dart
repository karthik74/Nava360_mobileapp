// ─────────────────────────────────────────────────────────────────────────────
//  MIS (Grow With Me) data models. The GWM backend returns raw JSON with mixed
//  numeric/string/null fields, so every fromJson is defensive (mis* helpers).
// ─────────────────────────────────────────────────────────────────────────────

double? misToDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? misToInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? misToStr(dynamic v) => v?.toString();

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

/// The signed-in Grow With Me user (mirrors `GwmUser` in AuthContext.tsx).
class MisUser {
  final String empId;
  final String? name;
  final String? role;
  final String? designation;
  final String? branch;
  final String? area;
  final String? division;
  final String? region;

  const MisUser({
    required this.empId,
    this.name,
    this.role,
    this.designation,
    this.branch,
    this.area,
    this.division,
    this.region,
  });

  factory MisUser.fromJson(Map<String, dynamic> j) => MisUser(
        empId: (misToStr(j['emp_id']) ?? '').trim(),
        name: misToStr(j['name']),
        role: misToStr(j['role']),
        designation: misToStr(j['designation']),
        branch: misToStr(j['branch']),
        area: misToStr(j['area']),
        division: misToStr(j['division']),
        region: misToStr(j['region']),
      );

  Map<String, dynamic> toJson() => {
        'emp_id': empId,
        'name': name,
        'role': role,
        'designation': designation,
        'branch': branch,
        'area': area,
        'division': division,
        'region': region,
      };

  /// First name for the dashboard greeting; falls back to the emp id.
  String get firstName {
    final n = (name ?? '').trim();
    if (n.isEmpty) return empId.isNotEmpty ? empId : 'there';
    return n.split(RegExp(r'\s+')).first;
  }
}

/// The user's data scope (`GwmScope`) — `tier` drives what the server returns.
class MisScope {
  final String? tier; // all | region | division | area | branch | self
  final bool fullAccess;
  const MisScope({this.tier, this.fullAccess = false});

  factory MisScope.fromJson(Map<String, dynamic>? j) => j == null
      ? const MisScope()
      : MisScope(tier: misToStr(j['tier']), fullAccess: j['full_access'] == true);
}

/// Response of `POST /auth/login`.
class MisLoginResult {
  final String? token;
  final MisUser? user;
  final MisScope? scope;
  final bool mustChangePassword;

  const MisLoginResult({
    this.token,
    this.user,
    this.scope,
    this.mustChangePassword = false,
  });

  factory MisLoginResult.fromJson(Map<String, dynamic> j) => MisLoginResult(
        token: misToStr(j['token']),
        user: j['user'] is Map ? MisUser.fromJson(_asMap(j['user'])) : null,
        scope: j['scope'] is Map ? MisScope.fromJson(_asMap(j['scope'])) : null,
        mustChangePassword: j['must_change_password'] == true,
      );
}

/// One row definition of the server-computed "Month Highlights" table.
/// type: count | cr (crore) | pct | na.
class OverviewRow {
  final String key;
  final String label;
  final String type;
  final bool strong;

  const OverviewRow({
    required this.key,
    required this.label,
    required this.type,
    this.strong = false,
  });

  factory OverviewRow.fromJson(Map<String, dynamic> j) => OverviewRow(
        key: misToStr(j['key']) ?? '',
        label: misToStr(j['label']) ?? '',
        type: misToStr(j['type']) ?? '',
        strong: j['strong'] == true,
      );
}

/// The whole NLPL Overview table — computed entirely server-side (`/overview`):
/// metrics down the rows, months across the columns. Rendered as-is; no client
/// math. New months appear as new columns automatically.
class OverviewTable {
  final List<String> months; // ["2026-04-01", …]
  final List<OverviewRow> rows;
  final Map<String, Map<String, double?>> values; // month -> rowKey -> value
  final bool scoped;

  const OverviewTable({
    this.months = const [],
    this.rows = const [],
    this.values = const {},
    this.scoped = false,
  });

  factory OverviewTable.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final months = (j['months'] is List)
        ? (j['months'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final rows = (j['rows'] is List)
        ? (j['rows'] as List)
            .whereType<Map>()
            .map((m) => OverviewRow.fromJson(m.cast<String, dynamic>()))
            .toList()
        : <OverviewRow>[];
    final values = <String, Map<String, double?>>{};
    if (j['values'] is Map) {
      (j['values'] as Map).forEach((month, rowMap) {
        if (rowMap is Map) {
          final inner = <String, double?>{};
          rowMap.forEach((k, v) => inner[k.toString()] = misToDouble(v));
          values[month.toString()] = inner;
        }
      });
    }
    return OverviewTable(
      months: months,
      rows: rows,
      values: values,
      scoped: j['scoped'] == true,
    );
  }

  /// The value for one cell, or null if that month/row has no source.
  double? cell(String month, String rowKey) => values[month]?[rowKey];
}

// ── Collection ───────────────────────────────────────────────────────────────

/// Which figure the collection views show: account counts or rupee amounts.
enum MisMetric { count, amount }

/// One DPD bucket of the collection summary. Account counts and their rupee
/// twins ride together on the SAME payload — amount mode reads `demand_amt` /
/// `collection_amt` instead of the `_count` fields, with no extra request.
class MisBucket {
  final String bucketName; // regular | on_date | 1_30 | 31_60 | 61_90 | pnpa | npa
  final double demandCount;
  final double collectionCount;
  final double demandAmt;
  final double collectionAmt;

  const MisBucket({
    required this.bucketName,
    this.demandCount = 0,
    this.collectionCount = 0,
    this.demandAmt = 0,
    this.collectionAmt = 0,
  });

  factory MisBucket.fromJson(Map<String, dynamic> j) => MisBucket(
        bucketName: misToStr(j['bucket_name']) ?? '',
        demandCount: misToDouble(j['demand_count']) ?? 0,
        collectionCount: misToDouble(j['collection_count']) ?? 0,
        demandAmt: misToDouble(j['demand_amt']) ?? 0,
        collectionAmt: misToDouble(j['collection_amt']) ?? 0,
      );

  double demand(MisMetric m) =>
      m == MisMetric.amount ? demandAmt : demandCount;
  double collection(MisMetric m) =>
      m == MisMetric.amount ? collectionAmt : collectionCount;
}

class MisNpaAction {
  final String actionName; // activation | closure
  final double accounts;
  final double amount;
  const MisNpaAction({
    required this.actionName,
    this.accounts = 0,
    this.amount = 0,
  });

  factory MisNpaAction.fromJson(Map<String, dynamic> j) => MisNpaAction(
        actionName: misToStr(j['action_name']) ?? '',
        accounts: misToDouble(j['accounts']) ?? 0,
        amount: misToDouble(j['amount']) ?? 0,
      );
}

/// One `/collection/summary` `modes[]` row — a payment channel's slice of the
/// day's collection.
class MisModeRow {
  final String channel; // raw CollectionChannel value, uppercased
  final double accounts;
  final double amount;
  const MisModeRow({
    required this.channel,
    this.accounts = 0,
    this.amount = 0,
  });

  factory MisModeRow.fromJson(Map<String, dynamic> j) => MisModeRow(
        channel: (misToStr(j['channel']) ?? '').trim().toUpperCase(),
        accounts: misToDouble(j['accounts']) ?? 0,
        amount: misToDouble(j['amount']) ?? 0,
      );
}

/// `/collection/summary` — DPD buckets + NPA actions for the current scope.
class CollectionSummary {
  final List<MisBucket> dpd;
  final List<MisNpaAction> npa;
  final double npaCases;
  final String? date;

  /// Mode of Collection — the payment-channel split, scoped like the rest.
  final List<MisModeRow> modes;

  /// Collection from officers that couldn't be matched to a branch.
  final double modesUnmappedAccounts;
  final double modesUnmappedAmount;

  /// True when a product filter is active but the modes span all products.
  final bool modesAllProducts;

  const CollectionSummary({
    this.dpd = const [],
    this.npa = const [],
    this.npaCases = 0,
    this.date,
    this.modes = const [],
    this.modesUnmappedAccounts = 0,
    this.modesUnmappedAmount = 0,
    this.modesAllProducts = false,
  });

  factory CollectionSummary.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final unmapped = _asMap(j['modes_unmapped']);
    return CollectionSummary(
      dpd: (j['dpd'] is List)
          ? (j['dpd'] as List)
              .whereType<Map>()
              .map((m) => MisBucket.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const [],
      npa: (j['npa'] is List)
          ? (j['npa'] as List)
              .whereType<Map>()
              .map((m) => MisNpaAction.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const [],
      npaCases: misToDouble(j['npa_cases']) ?? 0,
      date: misToStr(j['date']),
      modes: (j['modes'] is List)
          ? (j['modes'] as List)
              .whereType<Map>()
              .map((m) => MisModeRow.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const [],
      modesUnmappedAccounts: misToDouble(unmapped['accounts']) ?? 0,
      modesUnmappedAmount: misToDouble(unmapped['amount']) ?? 0,
      modesAllProducts: j['modes_all_products'] == true,
    );
  }

  /// True when this date actually carries rupee figures. The Daily Collection
  /// Report's OverAll sheet stores Demand/Collection as ACCOUNT COUNTS only, so
  /// dates synced from it hold 0 in every `_amt` — offering an Amount view that
  /// can only ever render ₹0.00 Cr is worse than not offering it. A null check
  /// alone would miss this (0 is not null), so test for a non-zero.
  bool get hasAmounts =>
      dpd.any((b) => b.demandAmt != 0 || b.collectionAmt != 0);

  MisBucket? bucket(String name) {
    for (final b in dpd) {
      if (b.bucketName == name) return b;
    }
    return null;
  }

  MisNpaAction? action(String name) {
    for (final a in npa) {
      if (a.actionName == name) return a;
    }
    return null;
  }
}

/// A drill-grid row from `/collection/by-*` (account counts).
class CollectionRow {
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  final String? name;
  final String? empId;
  final double demandCount;
  final double collectionCount;

  /// Rupee twins of the count fields, returned by the same `/collection/by-*`
  /// endpoints. A level can come back counts-only even when the summary has
  /// amounts, so [hasAmount] gates the Amount view per feed.
  final double demandAmt;
  final double collectionAmt;
  final bool hasAmount;

  /// The untouched source record. The hourly feed carries per-hour collection
  /// columns whose shape isn't fixed yet (array / map / flat prefixed keys), so
  /// the raw map is kept and parsed by `misHourSeries` rather than modelled.
  final Map<String, dynamic> raw;

  const CollectionRow({
    this.region,
    this.division,
    this.area,
    this.branch,
    this.name,
    this.empId,
    this.demandCount = 0,
    this.collectionCount = 0,
    this.demandAmt = 0,
    this.collectionAmt = 0,
    this.hasAmount = false,
    this.raw = const {},
  });

  factory CollectionRow.fromJson(Map<String, dynamic> j) => CollectionRow(
        region: misToStr(j['region']),
        division: misToStr(j['division']),
        area: misToStr(j['area']),
        branch: misToStr(j['branch']),
        name: misToStr(j['name']),
        empId: misToStr(j['emp_id']),
        demandCount: misToDouble(j['demand_count']) ?? 0,
        collectionCount: misToDouble(j['collection_count']) ?? 0,
        demandAmt: misToDouble(j['demand_amt']) ?? 0,
        collectionAmt: misToDouble(j['collection_amt']) ?? 0,
        hasAmount: j['demand_amt'] != null || j['collection_amt'] != null,
        raw: j,
      );

  double demand(MisMetric m) =>
      m == MisMetric.amount ? demandAmt : demandCount;
  double collection(MisMetric m) =>
      m == MisMetric.amount ? collectionAmt : collectionCount;

  double get balance => demandCount - collectionCount;
}

/// `/hourly/snapshot` — freshness of the live intra-day snapshot. Metadata only:
/// which period is loaded (date + hour slot) and when it was captured. Carries
/// no collection data; the figures still come from the summary / by-* feeds.
class HourlySnapshot {
  final String periodDate; // "2026-07-11"
  final String periodHour; // "18" (0–23, as a string)
  final String? asOf; // "2026-07-16 04:22:58"

  const HourlySnapshot({
    this.periodDate = '',
    this.periodHour = '',
    this.asOf,
  });

  factory HourlySnapshot.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return HourlySnapshot(
      periodDate: misToStr(j['period_date']) ?? '',
      periodHour: misToStr(j['period_hour']) ?? '',
      asOf: misToStr(j['as_of']),
    );
  }

  /// The snapshot's hour slot as 0–23, or null when the feed didn't carry one.
  int? get hour {
    final h = int.tryParse(periodHour.trim());
    return (h != null && h >= 0 && h <= 23) ? h : null;
  }

  bool get isEmpty => hour == null;
}

/// One archived hour slot from `/hourly/hours`.
class HourlyHourInfo {
  final String hour; // "14" (0–23, as a string)
  final String? capturedAt;

  const HourlyHourInfo({required this.hour, this.capturedAt});

  factory HourlyHourInfo.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return HourlyHourInfo(
      hour: misToStr(j['hour']) ?? '',
      capturedAt: misToStr(j['captured_at']),
    );
  }
}

/// `/hourly/hours` — the hour slots stored for a date, driving the replay
/// switcher. `liveHour` is the slot the live grain currently holds. An older
/// API build without this endpoint errors out; the screen treats that as "no
/// switcher" and stays on the live path.
class HourlyHoursMeta {
  final String? date;
  final String? liveHour; // "18"
  final List<HourlyHourInfo> hours;

  const HourlyHoursMeta({this.date, this.liveHour, this.hours = const []});

  factory HourlyHoursMeta.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final list = j['hours'];
    return HourlyHoursMeta(
      date: misToStr(j['date']),
      liveHour: misToStr(j['live_hour']),
      hours: [
        if (list is List)
          for (final h in list) HourlyHourInfo.fromJson(h),
      ],
    );
  }
}

// ── Portfolio ────────────────────────────────────────────────────────────────

/// `/portfolio/summary` — POS amounts keyed by status_name.
class PortfolioSummary {
  final Map<String, double> pos; // status_name -> amount
  const PortfolioSummary({this.pos = const {}});

  factory PortfolioSummary.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final map = <String, double>{};
    if (j['pos'] is List) {
      for (final e in (j['pos'] as List)) {
        if (e is Map) {
          final k = misToStr(e['status_name']);
          if (k != null) map[k] = misToDouble(e['amount']) ?? 0;
        }
      }
    }
    return PortfolioSummary(pos: map);
  }

  double amt(String key) => pos[key] ?? 0;
}

/// Per-unit pivot row from `/portfolio/by-unit`.
class PortfolioUnitRow {
  final String unit;
  final String? empId; // only at the officer (FO) drill level
  final double total;
  final double npa;
  final double npaAcc;
  final double regularAcc;
  final double sma0Acc;
  final double sma1Acc;
  final double pnpaAcc;
  // Full bucket-wise pivot (status_name -> amount / account count), identical in
  // shape to a PortfolioSummary's `pos`. Lets an opened officer render the same
  // bucket-wise detail as a branch, since `/portfolio/summary` cannot scope to
  // an individual FO.
  final Map<String, double> pos;

  const PortfolioUnitRow({
    this.unit = '',
    this.empId,
    this.total = 0,
    this.npa = 0,
    this.npaAcc = 0,
    this.regularAcc = 0,
    this.sma0Acc = 0,
    this.sma1Acc = 0,
    this.pnpaAcc = 0,
    this.pos = const {},
  });

  static const _posKeys = [
    'regular', 'sma0', 'sma1', 'pnpa', 'npa', 'total',
    'total_acc', 'regular_acc', 'sma0_acc', 'sma1_acc', 'pnpa_acc', 'npa_acc',
  ];

  factory PortfolioUnitRow.fromJson(Map<String, dynamic> j) => PortfolioUnitRow(
        unit: misToStr(j['unit']) ?? '',
        empId: misToStr(j['emp_id']),
        total: misToDouble(j['total']) ?? 0,
        npa: misToDouble(j['npa']) ?? 0,
        npaAcc: misToDouble(j['npa_acc']) ?? 0,
        regularAcc: misToDouble(j['regular_acc']) ?? 0,
        sma0Acc: misToDouble(j['sma0_acc']) ?? 0,
        sma1Acc: misToDouble(j['sma1_acc']) ?? 0,
        pnpaAcc: misToDouble(j['pnpa_acc']) ?? 0,
        pos: {for (final k in _posKeys) k: misToDouble(j[k]) ?? 0},
      );

  double get activeAcc => regularAcc + sma0Acc + sma1Acc + pnpaAcc;
  double get totalAcc => activeAcc + npaAcc;
  double get npaPct => total > 0 ? (npa / total) * 100 : 0;

  /// This row's bucket breakdown as a PortfolioSummary, so an opened officer
  /// reuses the same summary UI as a branch.
  PortfolioSummary toSummary() => PortfolioSummary(pos: pos);
}

// ── Clients (the "Active clients details as on <date>" report) ───────────────

/// The as-of block every `/clients` response carries.
class ClientsAsOn {
  final String asOnDate;
  final String label;
  final String monthLabel;
  final String periodMonth;
  final String sourceKind;
  final int? rowCount;

  const ClientsAsOn({
    this.asOnDate = '',
    this.label = '',
    this.monthLabel = '',
    this.periodMonth = '',
    this.sourceKind = '',
    this.rowCount,
  });

  factory ClientsAsOn.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return ClientsAsOn(
      asOnDate: misToStr(j['as_on_date']) ?? '',
      label: misToStr(j['label']) ?? '',
      monthLabel: misToStr(j['month_label']) ?? '',
      periodMonth: misToStr(j['period_month']) ?? '',
      sourceKind: misToStr(j['source_kind']) ?? '',
      rowCount: misToInt(j['row_count']),
    );
  }
}

/// One report row. Keys are the workbook's ORIGINAL column names (spaces and
/// all), plus the derived `Bucket`, and money fields arrive as decimal strings —
/// so the raw map is kept and read through named getters.
class ClientRow {
  final Map<String, dynamic> raw;
  const ClientRow(this.raw);

  String? str(String key) {
    final v = raw[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  double? number(String key) => misToDouble(raw[key]);

  String? get clientId => str('ClientID');
  String? get clientName => str('Client Name');
  String? get mobile => str('Mobile No');
  String? get accountId => str('AccountID');
  String? get productName => str('Product Name');
  String? get branchName => str('BranchName');
  String? get officerName => str('OfficerName');
  String? get groupName => str('GroupName');
  String? get disbursementDate => str('DisbursementDate');
  String? get loanMaturityDate => str('LoanMaturityDate');
  String? get dpdDays => str('DPD Days');
  String? get bucket => str('Bucket');
  double? get loanAmount => number('LoanAmount');
  double? get installmentAmount => number('InstallmentAmount');
  double? get principalOs => number('PrincipalOS');
  double? get totalArrear => number('TotalArrear');
  double? get dueDays => number('DueDays');

  /// A stable-ish identity for list keys.
  String get id => accountId ?? clientId ?? clientName ?? '';
}

/// `/clients/list` — the report rows for one bucket + scope, server-paged.
class ClientsListResponse {
  final ClientsAsOn asOn;
  final String grain; // account | aggregate
  final bool detailAvailable;
  final List<String> headers;
  final int total;
  final int limit;
  final int offset;
  final List<ClientRow> rows;

  const ClientsListResponse({
    this.asOn = const ClientsAsOn(),
    this.grain = '',
    this.detailAvailable = false,
    this.headers = const [],
    this.total = 0,
    this.limit = 0,
    this.offset = 0,
    this.rows = const [],
  });

  factory ClientsListResponse.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return ClientsListResponse(
      asOn: ClientsAsOn.fromJson(j['as_on']),
      grain: misToStr(j['grain']) ?? '',
      detailAvailable: j['detail_available'] == true,
      headers: (j['headers'] is List)
          ? (j['headers'] as List).map((e) => e.toString()).toList()
          : const [],
      total: misToInt(j['total']) ?? 0,
      limit: misToInt(j['limit']) ?? 0,
      offset: misToInt(j['offset']) ?? 0,
      rows: (j['rows'] is List)
          ? (j['rows'] as List)
              .whereType<Map>()
              .map((m) => ClientRow(m.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

// ── Disbursement ─────────────────────────────────────────────────────────────

/// `/disbursement/summary` (and daily/summary).
class DisbSummary {
  final double totalCount;
  final double totalAmount;
  const DisbSummary({this.totalCount = 0, this.totalAmount = 0});

  factory DisbSummary.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return DisbSummary(
      totalCount: misToDouble(j['total_count']) ?? 0,
      totalAmount: misToDouble(j['total_amount']) ?? 0,
    );
  }

  double get ats => totalCount > 0 ? totalAmount / totalCount : 0;
}

/// Per-unit pivot row from `/disbursement/by-unit` (and daily/by-unit).
class DisbUnitRow {
  final String unit;
  final String? empId;
  final String? managerName;
  final String? mobile;
  final double count;
  final double amount;

  const DisbUnitRow({
    this.unit = '',
    this.empId,
    this.managerName,
    this.mobile,
    this.count = 0,
    this.amount = 0,
  });

  factory DisbUnitRow.fromJson(Map<String, dynamic> j) => DisbUnitRow(
        unit: misToStr(j['unit']) ?? '',
        empId: misToStr(j['emp_id']),
        managerName: misToStr(j['manager_name']),
        mobile: misToStr(j['mobile']),
        count: misToDouble(j['count']) ?? 0,
        amount: misToDouble(j['amount']) ?? 0,
      );
}

/// Product breakdown row from `/disbursement/by-product`.
class DisbProductRow {
  final int productId; // 1 IGL · 2 FIG · 3 IL
  final double count;
  final double amount;
  const DisbProductRow({this.productId = 0, this.count = 0, this.amount = 0});

  factory DisbProductRow.fromJson(Map<String, dynamic> j) => DisbProductRow(
        productId: misToInt(j['product_id']) ?? 0,
        count: misToDouble(j['count']) ?? 0,
        amount: misToDouble(j['amount']) ?? 0,
      );

  double get ats => count > 0 ? amount / count : 0;
}

/// Per-day totals row from `/disbursement/daily/trend`.
class DisbTrendRow {
  final String disbDate;
  final double count;
  final double amount;
  const DisbTrendRow({this.disbDate = '', this.count = 0, this.amount = 0});

  factory DisbTrendRow.fromJson(Map<String, dynamic> j) => DisbTrendRow(
        disbDate: misToStr(j['disb_date']) ?? '',
        count: misToDouble(j['count']) ?? 0,
        amount: misToDouble(j['amount']) ?? 0,
      );
}

// ── Analytical (leaderboard tool) ───────────────────────────────────────────
// Ports src/mis/gwm/api/analysisApi.ts's response shapes: /analysis/filters,
// /analysis/leaderboard, /analysis/my-rank.

/// The caller's own scope, as returned by `/analysis/filters`.
class AnalysisMe {
  final String? tier;
  final String? region;
  final String? division;
  final String? area;
  final String? branch;
  final String? empId;
  final String? name;

  const AnalysisMe({
    this.tier,
    this.region,
    this.division,
    this.area,
    this.branch,
    this.empId,
    this.name,
  });

  factory AnalysisMe.fromJson(Map<String, dynamic> j) => AnalysisMe(
        tier: misToStr(j['tier']),
        region: misToStr(j['region']),
        division: misToStr(j['division']),
        area: misToStr(j['area']),
        branch: misToStr(j['branch']),
        empId: misToStr(j['emp_id']),
        name: misToStr(j['name']),
      );
}

/// `/analysis/filters` — dates/months/levels metadata, loaded once per screen.
class AnalysisFilters {
  final List<String> dates;
  final List<String> months;
  final List<String> levels;
  final AnalysisMe me;

  const AnalysisFilters({
    this.dates = const [],
    this.months = const [],
    this.levels = const [],
    this.me = const AnalysisMe(),
  });

  factory AnalysisFilters.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return AnalysisFilters(
      dates: (j['dates'] is List)
          ? (j['dates'] as List).map((e) => e.toString()).toList()
          : const [],
      months: (j['months'] is List)
          ? (j['months'] as List).map((e) => e.toString()).toList()
          : const [],
      levels: (j['levels'] is List)
          ? (j['levels'] as List).map((e) => e.toString()).toList()
          : const [],
      me: j['me'] is Map
          ? AnalysisMe.fromJson(_asMap(j['me']))
          : const AnalysisMe(),
    );
  }
}

/// One ranked unit row from `/analysis/leaderboard`. Collection rows carry
/// demand/collection/pct/ftod (accounts only); disbursement rows carry
/// count/amount.
class AnalysisUnitRow {
  final String unit;
  final String? empId;
  final double? demand;
  final double? collection;

  /// Fixed 2-decimal string from the backend, e.g. "5.00".
  final String? pct;
  final double? ftod;
  final double? count;
  final double? amount;
  final int rank;

  const AnalysisUnitRow({
    required this.unit,
    this.empId,
    this.demand,
    this.collection,
    this.pct,
    this.ftod,
    this.count,
    this.amount,
    this.rank = 0,
  });

  factory AnalysisUnitRow.fromJson(Map<String, dynamic> j) => AnalysisUnitRow(
        unit: misToStr(j['unit']) ?? '',
        empId: misToStr(j['emp_id']),
        demand: misToDouble(j['demand']),
        collection: misToDouble(j['collection']),
        pct: misToStr(j['pct']),
        ftod: misToDouble(j['ftod']),
        count: misToDouble(j['count']),
        amount: misToDouble(j['amount']),
        rank: misToInt(j['rank']) ?? 0,
      );
}

/// One level's slice of `/analysis/leaderboard` — top 5 (+ bottom 5, empty for
/// `region`), plus the full national list (`all`) for `branch` and `employee`,
/// which backs a search across everyone nationally rather than just the ten
/// rows already shown.
class AnalysisLeaderboardLevel {
  final List<AnalysisUnitRow> top;
  final List<AnalysisUnitRow> bottom;
  final List<AnalysisUnitRow>? all;
  final int total;

  const AnalysisLeaderboardLevel({
    this.top = const [],
    this.bottom = const [],
    this.all,
    this.total = 0,
  });

  factory AnalysisLeaderboardLevel.fromJson(dynamic raw) {
    final j = _asMap(raw);
    List<AnalysisUnitRow> rows(dynamic v) => v is List
        ? v
            .whereType<Map>()
            .map((m) => AnalysisUnitRow.fromJson(m.cast<String, dynamic>()))
            .toList()
        : const [];
    return AnalysisLeaderboardLevel(
      top: rows(j['top']),
      bottom: rows(j['bottom']),
      all: j['all'] is List ? rows(j['all']) : null,
      total: misToInt(j['total']) ?? 0,
    );
  }
}

/// `/analysis/leaderboard` — all-India top 5 (+ bottom 5 except region) at
/// every level, plus the full national branch/employee lists. Always unscoped.
class AnalysisLeaderboard {
  final String mode;
  final AnalysisLeaderboardLevel region;
  final AnalysisLeaderboardLevel division;
  final AnalysisLeaderboardLevel area;
  final AnalysisLeaderboardLevel branch;
  final AnalysisLeaderboardLevel employee;

  const AnalysisLeaderboard({
    this.mode = 'collection',
    this.region = const AnalysisLeaderboardLevel(),
    this.division = const AnalysisLeaderboardLevel(),
    this.area = const AnalysisLeaderboardLevel(),
    this.branch = const AnalysisLeaderboardLevel(),
    this.employee = const AnalysisLeaderboardLevel(),
  });

  factory AnalysisLeaderboard.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return AnalysisLeaderboard(
      mode: misToStr(j['mode']) ?? 'collection',
      region: AnalysisLeaderboardLevel.fromJson(j['region']),
      division: AnalysisLeaderboardLevel.fromJson(j['division']),
      area: AnalysisLeaderboardLevel.fromJson(j['area']),
      branch: AnalysisLeaderboardLevel.fromJson(j['branch']),
      employee: AnalysisLeaderboardLevel.fromJson(j['employee']),
    );
  }

  /// The level's data by key ("region"|"division"|"area"|"branch"|"employee").
  AnalysisLeaderboardLevel level(String key) => switch (key) {
        'region' => region,
        'division' => division,
        'area' => area,
        'branch' => branch,
        'employee' => employee,
        _ => const AnalysisLeaderboardLevel(),
      };
}

/// One level's entry in `/analysis/my-rank` — the caller's own national rank.
class AnalysisRankEntry {
  final String unit;
  final int rank;
  final int total;
  final String? pct;
  final double? demand;
  final double? collection;
  final double? ftod;
  final double? count;
  final double? amount;

  const AnalysisRankEntry({
    this.unit = '',
    this.rank = 0,
    this.total = 0,
    this.pct,
    this.demand,
    this.collection,
    this.ftod,
    this.count,
    this.amount,
  });

  factory AnalysisRankEntry.fromJson(Map<String, dynamic> j) =>
      AnalysisRankEntry(
        unit: misToStr(j['unit']) ?? '',
        rank: misToInt(j['rank']) ?? 0,
        total: misToInt(j['total']) ?? 0,
        pct: misToStr(j['pct']),
        demand: misToDouble(j['demand']),
        collection: misToDouble(j['collection']),
        ftod: misToDouble(j['ftod']),
        count: misToDouble(j['count']),
        amount: misToDouble(j['amount']),
      );
}

/// `/analysis/my-rank` — the caller's own national rank at every level they
/// belong to (e.g. "#50 of 800 FOs"). Unscoped.
class AnalysisMyRank {
  final String mode;
  final String? empId;
  final String? name;
  final AnalysisRankEntry? region;
  final AnalysisRankEntry? division;
  final AnalysisRankEntry? area;
  final AnalysisRankEntry? branch;
  final AnalysisRankEntry? employee;

  const AnalysisMyRank({
    this.mode = 'collection',
    this.empId,
    this.name,
    this.region,
    this.division,
    this.area,
    this.branch,
    this.employee,
  });

  factory AnalysisMyRank.fromJson(dynamic raw) {
    final j = _asMap(raw);
    AnalysisRankEntry? entry(dynamic v) => v is Map
        ? AnalysisRankEntry.fromJson(v.cast<String, dynamic>())
        : null;
    return AnalysisMyRank(
      mode: misToStr(j['mode']) ?? 'collection',
      empId: misToStr(j['emp_id']),
      name: misToStr(j['name']),
      region: entry(j['region']),
      division: entry(j['division']),
      area: entry(j['area']),
      branch: entry(j['branch']),
      employee: entry(j['employee']),
    );
  }

  /// The level's entry by key ("region"|"division"|"area"|"branch"|"employee").
  AnalysisRankEntry? level(String key) => switch (key) {
        'region' => region,
        'division' => division,
        'area' => area,
        'branch' => branch,
        'employee' => employee,
        _ => null,
      };
}

// ── Comparison ───────────────────────────────────────────────────────────────

/// One side (prev or cur) of a paired comparison day — a `date` plus cumulative
/// per-DPD-bucket count fields. Kept as a raw map (dynamic field set).
class CompareSide {
  final Map<String, dynamic> raw;
  const CompareSide(this.raw);

  String get date => misToStr(raw['date']) ?? '';
  double field(String key) => misToDouble(raw[key]) ?? 0;
}

/// A `/comparison/daily` row: the same weekday-occurrence in each month.
class CompareDailyRow {
  final CompareSide? from; // previous month
  final CompareSide? to; // current month
  const CompareDailyRow(this.from, this.to);

  factory CompareDailyRow.fromJson(Map<String, dynamic> j) => CompareDailyRow(
        j['from'] is Map ? CompareSide((j['from'] as Map).cast<String, dynamic>()) : null,
        j['to'] is Map ? CompareSide((j['to'] as Map).cast<String, dynamic>()) : null,
      );
}

class CompareDailyResponse {
  final List<CompareDailyRow> rows;
  const CompareDailyResponse({this.rows = const []});

  factory CompareDailyResponse.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return CompareDailyResponse(
      rows: (j['rows'] is List)
          ? (j['rows'] as List)
              .whereType<Map>()
              .map((m) => CompareDailyRow.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

// ── Daily Plan ───────────────────────────────────────────────────────────────

class DailyPlanBranch {
  final String branchName;
  final String? area;
  const DailyPlanBranch({required this.branchName, this.area});

  factory DailyPlanBranch.fromJson(Map<String, dynamic> j) => DailyPlanBranch(
        branchName: misToStr(j['branch_name']) ?? '',
        area: misToStr(j['area']),
      );

  String get label => area != null && area!.isNotEmpty
      ? '$branchName · $area'
      : branchName;
}

class PlanAmount {
  final double actual, plan;
  const PlanAmount(this.actual, this.plan);
  factory PlanAmount.fromJson(dynamic j) {
    final m = _asMap(j);
    return PlanAmount(misToDouble(m['actual']) ?? 0, misToDouble(m['plan']) ?? 0);
  }
}

class PlanDisb {
  final double acc, amt;
  const PlanDisb(this.acc, this.amt);
  factory PlanDisb.fromJson(dynamic j) {
    final m = _asMap(j);
    return PlanDisb(misToDouble(m['acc']) ?? 0, misToDouble(m['amt']) ?? 0);
  }
}

/// `/daily-plan/mine` — a branch's saved plan/achievement, to pre-fill the form.
class DailyPlanMine {
  final bool exists;
  final PlanAmount ftod, dpd130, dpd3160, dpd6190, fyNonStart;
  final PlanDisb igl, fig, il;
  final double kycIgl, kycFig, kycIl, npaActivation, npaClosure;

  const DailyPlanMine({
    this.exists = false,
    this.ftod = const PlanAmount(0, 0),
    this.dpd130 = const PlanAmount(0, 0),
    this.dpd3160 = const PlanAmount(0, 0),
    this.dpd6190 = const PlanAmount(0, 0),
    this.fyNonStart = const PlanAmount(0, 0),
    this.igl = const PlanDisb(0, 0),
    this.fig = const PlanDisb(0, 0),
    this.il = const PlanDisb(0, 0),
    this.kycIgl = 0,
    this.kycFig = 0,
    this.kycIl = 0,
    this.npaActivation = 0,
    this.npaClosure = 0,
  });

  factory DailyPlanMine.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final dpd = _asMap(j['dpd']);
    final disb = _asMap(j['disb']);
    final kyc = _asMap(j['kyc']);
    final npa = _asMap(j['npa']);
    return DailyPlanMine(
      exists: j['exists'] == true,
      ftod: PlanAmount.fromJson(j['ftod']),
      dpd130: PlanAmount.fromJson(dpd['1_30']),
      dpd3160: PlanAmount.fromJson(dpd['31_60']),
      dpd6190: PlanAmount.fromJson(dpd['61_90']),
      fyNonStart: PlanAmount.fromJson(j['fy_non_start']),
      igl: PlanDisb.fromJson(disb['igl']),
      fig: PlanDisb.fromJson(disb['fig']),
      il: PlanDisb.fromJson(disb['il']),
      kycIgl: misToDouble(kyc['igl']) ?? 0,
      kycFig: misToDouble(kyc['fig']) ?? 0,
      kycIl: misToDouble(kyc['il']) ?? 0,
      npaActivation: misToDouble(npa['activation']) ?? 0,
      npaClosure: misToDouble(npa['closure']) ?? 0,
    );
  }
}

/// One record of the flat `/daily-plan/rows` report feed (one row per branch,
/// all columns). The column set is wide and level-dependent, so the raw map is
/// kept and aggregated by the report table.
class DailyPlanReportRow {
  final Map<String, dynamic> raw;
  const DailyPlanReportRow(this.raw);

  double n(String key) => misToDouble(raw[key]) ?? 0;

  String? get region => misToStr(raw['region']);
  String? get division => misToStr(raw['division']);
  String? get area => misToStr(raw['area']);
  String? get branchName => misToStr(raw['branch_name']);

  /// The grouping value for a report level, blank-safe.
  String group(String field) {
    final v = misToStr(raw[field])?.trim();
    return (v == null || v.isEmpty) ? '—' : v;
  }
}

/// A branch that has not yet submitted for a date/type, with the BM's contact
/// so the caller can follow up (`/daily-plan/pending-branches`).
class PendingBranch {
  final String branchName;
  final String? area, region, bmName, bmPhone;
  const PendingBranch({
    this.branchName = '—',
    this.area,
    this.region,
    this.bmName,
    this.bmPhone,
  });

  factory PendingBranch.fromJson(Map<String, dynamic> j) => PendingBranch(
        branchName: misToStr(j['branch_name']) ?? '—',
        area: misToStr(j['area']),
        region: misToStr(j['region']),
        bmName: misToStr(j['bm_name']),
        bmPhone: misToStr(j['bm_phone']),
      );

  String get crumb =>
      [area, region].where((s) => s != null && s.isNotEmpty).join(' · ');
}

// ── Feedback ─────────────────────────────────────────────────────────────────

class FeedbackItem {
  final String id;
  final String? name;
  final String? branch;
  final String? category;
  final String? status;
  final String? title;
  final String? body;
  final String? createdAt;

  const FeedbackItem({
    required this.id,
    this.name,
    this.branch,
    this.category,
    this.status,
    this.title,
    this.body,
    this.createdAt,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> j) => FeedbackItem(
        id: misToStr(j['feedback_id']) ?? '',
        name: misToStr(j['name']),
        branch: misToStr(j['branch']),
        category: misToStr(j['category']),
        status: misToStr(j['status']),
        title: misToStr(j['title']),
        body: misToStr(j['body']),
        createdAt: misToStr(j['created_at']),
      );

  bool get isOpen => (status ?? 'open') == 'open';
}

// ── Employees ────────────────────────────────────────────────────────────────

class EmployeeRow {
  final String empId;
  final String? name, designation, role, mobile, branch, area, region;
  const EmployeeRow({
    required this.empId,
    this.name,
    this.designation,
    this.role,
    this.mobile,
    this.branch,
    this.area,
    this.region,
  });

  factory EmployeeRow.fromJson(Map<String, dynamic> j) => EmployeeRow(
        empId: misToStr(j['emp_id']) ?? '',
        name: misToStr(j['name']),
        designation: misToStr(j['designation']),
        role: misToStr(j['role']),
        mobile: misToStr(j['mobile']),
        branch: misToStr(j['branch']),
        area: misToStr(j['area']),
        region: misToStr(j['region']),
      );

  String get displayDesignation =>
      (designation != null && designation!.isNotEmpty)
          ? designation!
          : (role ?? '—');

  String get location =>
      [branch, area, region].where((s) => s != null && s.isNotEmpty).join(' • ');
}

class EmployeeCounts {
  final double total, working;
  const EmployeeCounts({this.total = 0, this.working = 0});
  factory EmployeeCounts.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return EmployeeCounts(
      total: misToDouble(j['total']) ?? 0,
      working: misToDouble(j['working']) ?? 0,
    );
  }
}

/// Full employee record from `/employees/:id`.
class Employee {
  final String empId;
  final String? name, designation, role, status;
  final bool isWorking;
  final String? reportsToName, reportsToEmpId;
  final String? branch, area, division, region, postedSince;
  final String? mobile, email, emergencyPhone, gender;

  const Employee({
    required this.empId,
    this.name,
    this.designation,
    this.role,
    this.status,
    this.isWorking = false,
    this.reportsToName,
    this.reportsToEmpId,
    this.branch,
    this.area,
    this.division,
    this.region,
    this.postedSince,
    this.mobile,
    this.email,
    this.emergencyPhone,
    this.gender,
  });

  factory Employee.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final w = j['is_working'];
    return Employee(
      empId: misToStr(j['emp_id']) ?? '',
      name: misToStr(j['name']),
      designation: misToStr(j['designation']),
      role: misToStr(j['role']),
      status: misToStr(j['status']),
      isWorking: w == 1 || w == true || w == '1',
      reportsToName: misToStr(j['reports_to_name']),
      reportsToEmpId: misToStr(j['reports_to_emp_id']),
      branch: misToStr(j['branch']),
      area: misToStr(j['area']),
      division: misToStr(j['division']),
      region: misToStr(j['region']),
      postedSince: misToStr(j['posted_since']),
      mobile: misToStr(j['mobile']),
      email: misToStr(j['email']),
      emergencyPhone: misToStr(j['emergency_phone']),
      gender: misToStr(j['gender']),
    );
  }

  String get displayName {
    final n = (name ?? '').trim();
    return n.isNotEmpty ? n : empId;
  }
}

class EmployeePersonal {
  final String? dateOfBirth, hireDate, pan, aadhaarLast4;
  const EmployeePersonal({
    this.dateOfBirth,
    this.hireDate,
    this.pan,
    this.aadhaarLast4,
  });

  /// The endpoint wraps the object as `{ personal: {...} }`.
  factory EmployeePersonal.fromJson(dynamic raw) {
    final outer = _asMap(raw);
    final j = outer['personal'] is Map
        ? (outer['personal'] as Map).cast<String, dynamic>()
        : outer;
    return EmployeePersonal(
      dateOfBirth: misToStr(j['date_of_birth']),
      hireDate: misToStr(j['hire_date']),
      pan: misToStr(j['pan']),
      aadhaarLast4: misToStr(j['aadhaar_last4']),
    );
  }
}

// ── Hierarchy (cascading scope filter options) ───────────────────────────────

/// One option in a Region/Division/Area/Branch cascading dropdown. The `id` is
/// used ONLY to load the next level; data endpoints filter by `name`.
class HierOption {
  final String id;
  final String name;
  const HierOption(this.id, this.name);

  static HierOption from(Map<String, dynamic> j, String idKey, String nameKey) =>
      HierOption(misToStr(j[idKey]) ?? '', misToStr(j[nameKey]) ?? '');
}

// ── Branch Matrix ────────────────────────────────────────────────────────────
// Mirrors src/mis/gwm/api/branchMatrixApi.ts — GET /branch-matrix?fy=. One call
// returns every branch, every month in the selected financial year, every
// metric; the caller picks which metric column to render.

/// count | cr (crore) | pct.
typedef BranchMatrixType = String;

/// sum | avg — how the rightmost Total column is derived for this metric.
typedef BranchMatrixAgg = String;

class BranchMatrixMetric {
  final String key;
  final String label;
  final BranchMatrixType type;
  final BranchMatrixAgg agg;

  const BranchMatrixMetric({
    required this.key,
    required this.label,
    required this.type,
    required this.agg,
  });

  factory BranchMatrixMetric.fromJson(Map<String, dynamic> j) =>
      BranchMatrixMetric(
        key: misToStr(j['key']) ?? '',
        label: misToStr(j['label']) ?? '',
        type: misToStr(j['type']) ?? 'count',
        agg: misToStr(j['agg']) ?? 'sum',
      );
}

class BranchMatrixRow {
  final String branch;
  final String? area;
  final String? division;
  final String? region;

  /// 'YYYY-MM-01' -> metric key -> value (null = not available).
  final Map<String, Map<String, double?>> values;

  /// One Total per metric across this branch's months.
  final Map<String, double?> totals;

  /// True only for the network-wide "Total" row appended last.
  final bool isTotal;

  const BranchMatrixRow({
    required this.branch,
    this.area,
    this.division,
    this.region,
    this.values = const {},
    this.totals = const {},
    this.isTotal = false,
  });

  factory BranchMatrixRow.fromJson(Map<String, dynamic> j) {
    final values = <String, Map<String, double?>>{};
    if (j['values'] is Map) {
      (j['values'] as Map).forEach((month, metricMap) {
        if (metricMap is Map) {
          final inner = <String, double?>{};
          metricMap.forEach((k, v) => inner[k.toString()] = misToDouble(v));
          values[month.toString()] = inner;
        }
      });
    }
    final totals = <String, double?>{};
    if (j['totals'] is Map) {
      (j['totals'] as Map)
          .forEach((k, v) => totals[k.toString()] = misToDouble(v));
    }
    return BranchMatrixRow(
      branch: misToStr(j['branch']) ?? '—',
      area: misToStr(j['area']),
      division: misToStr(j['division']),
      region: misToStr(j['region']),
      values: values,
      totals: totals,
      isTotal: j['is_total'] == true,
    );
  }

  /// One cell's value for a metric in a given month.
  double? cell(String month, String metricKey) => values[month]?[metricKey];
}

class BranchMatrixResponse {
  final List<BranchMatrixMetric> metrics;
  final String? note;

  /// The FY's start year actually applied, e.g. 2026 for "FY 2026-27".
  final int? fy;

  /// "FY 2026-27".
  final String? fyLabel;

  /// Every FY that has data, newest first.
  final List<int> availableFys;

  /// This FY's months, ascending (union across every branch).
  final List<String> months;
  final int branchCount;
  final List<BranchMatrixRow> branches;

  /// Loan product filter echoed back: `igl` | `fig` | `il`; null ⇒ all products.
  final String? product;

  const BranchMatrixResponse({
    this.metrics = const [],
    this.note,
    this.fy,
    this.fyLabel,
    this.availableFys = const [],
    this.months = const [],
    this.branchCount = 0,
    this.branches = const [],
    this.product,
  });

  factory BranchMatrixResponse.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return BranchMatrixResponse(
      metrics: (j['metrics'] is List)
          ? (j['metrics'] as List)
              .whereType<Map>()
              .map((m) => BranchMatrixMetric.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const [],
      note: misToStr(j['note']),
      fy: (j['fy'] as num?)?.toInt(),
      fyLabel: misToStr(j['fy_label']),
      product: misToStr(j['product']),
      availableFys: (j['available_fys'] is List)
          ? (j['available_fys'] as List)
              .map((e) => (e as num).toInt())
              .toList()
          : const [],
      months: (j['months'] is List)
          ? (j['months'] as List).map((e) => e.toString()).toList()
          : const [],
      branchCount: (j['branch_count'] as num?)?.toInt() ?? 0,
      branches: (j['branches'] is List)
          ? (j['branches'] as List)
              .whereType<Map>()
              .map((m) => BranchMatrixRow.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

// ── Locations ────────────────────────────────────────────────────────────────

class BranchLocationRow {
  final String branchId;
  final String branch;
  final String? area, region;
  final double lat, lng;
  const BranchLocationRow({
    required this.branchId,
    required this.branch,
    this.area,
    this.region,
    required this.lat,
    required this.lng,
  });

  factory BranchLocationRow.fromJson(Map<String, dynamic> j) =>
      BranchLocationRow(
        branchId: misToStr(j['branch_id']) ?? '',
        branch: misToStr(j['branch']) ?? '—',
        area: misToStr(j['area']),
        region: misToStr(j['region']),
        lat: misToDouble(j['latitude']) ?? 0,
        lng: misToDouble(j['longitude']) ?? 0,
      );

  bool get hasCoords => lat != 0 && lng != 0;
}

// ── Branch Report ────────────────────────────────────────────────────────────

/// One branch the caller may open (already scope-limited by the server).
class BranchOption {
  final String branch;
  final String? area;
  final String? division;
  final String? region;

  const BranchOption({
    required this.branch,
    this.area,
    this.division,
    this.region,
  });

  factory BranchOption.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return BranchOption(
      branch: misToStr(j['branch']) ?? '',
      area: misToStr(j['area']),
      division: misToStr(j['division']),
      region: misToStr(j['region']),
    );
  }
}

/// An accounts + amount pair on the portfolio row. `accounts` is null when the
/// month's PAR carries no bucket split — rendered as "—", never a zero.
class BrPortfolioCell {
  final double? accounts;
  final double amount;
  const BrPortfolioCell({this.accounts, this.amount = 0});

  factory BrPortfolioCell.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return BrPortfolioCell(
      accounts: misToDouble(j['accounts']),
      amount: misToDouble(j['amount']) ?? 0,
    );
  }
}

/// The month-end POS snapshot block of `/branch-report`.
class BranchPortfolio {
  final String month; // "2026-07-01"
  final String label; // "Jul"
  final bool hasBucketAccounts;
  final BrPortfolioCell total;
  final BrPortfolioCell regular;
  final BrPortfolioCell od1To90;
  final BrPortfolioCell npa;
  final double? regCustPerFo;
  final double? odCustPerFo;

  const BranchPortfolio({
    this.month = '',
    this.label = '',
    this.hasBucketAccounts = false,
    this.total = const BrPortfolioCell(),
    this.regular = const BrPortfolioCell(),
    this.od1To90 = const BrPortfolioCell(),
    this.npa = const BrPortfolioCell(),
    this.regCustPerFo,
    this.odCustPerFo,
  });

  factory BranchPortfolio.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return BranchPortfolio(
      month: misToStr(j['month']) ?? '',
      label: misToStr(j['label']) ?? '',
      hasBucketAccounts: j['has_bucket_accounts'] == true,
      total: BrPortfolioCell.fromJson(j['total']),
      regular: BrPortfolioCell.fromJson(j['regular']),
      od1To90: BrPortfolioCell.fromJson(j['od_1_90']),
      npa: BrPortfolioCell.fromJson(j['npa']),
      regCustPerFo: misToDouble(j['reg_cust_per_fo']),
      odCustPerFo: misToDouble(j['od_cust_per_fo']),
    );
  }
}

/// One month's column of the Collection Performance table.
class BranchPerformance {
  final String month;
  final String label;
  final double? ftod;
  final double? regularCollectionPct;
  final double? npaPct;
  final double? npaCollectionAmount;
  final double? npaCollectionPct;
  final String? lastDate; // "2026-08-11" — set with monthComplete=false on a part month
  final bool monthComplete;

  const BranchPerformance({
    this.month = '',
    this.label = '',
    this.ftod,
    this.regularCollectionPct,
    this.npaPct,
    this.npaCollectionAmount,
    this.npaCollectionPct,
    this.lastDate,
    this.monthComplete = true,
  });

  factory BranchPerformance.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return BranchPerformance(
      month: misToStr(j['month']) ?? '',
      label: misToStr(j['label']) ?? '',
      ftod: misToDouble(j['ftod']),
      regularCollectionPct: misToDouble(j['regular_collection_pct']),
      npaPct: misToDouble(j['npa_pct']),
      npaCollectionAmount: misToDouble(j['npa_collection_amount']),
      npaCollectionPct: misToDouble(j['npa_collection_pct']),
      lastDate: misToStr(j['last_date']),
      monthComplete: j['month_complete'] != false,
    );
  }
}

/// One month of the BUSINESS Projection table — a PURE READ from the server,
/// exactly as uploaded (see routes/branchReport.js on the API). There is no
/// roll-forward arithmetic, no assumption rates, on any client: the server
/// sends every forward month's Opening/Closure/DB/Closing figures straight
/// from the "Branch Report Cards Consolidated" upload, same as the web port
/// (BranchProjectionMonth in branchReportApi.ts). A null cell means the
/// upload didn't carry that figure for that month — never a zero.
class BranchProjectionMonth {
  final String month; // "2026-09-01"
  final String label; // "Sep-26"
  final double? openingAcc;
  final double? openingPos;
  final double? closureAcc;
  final double? closurePos;
  final double? dbAcc;
  final double? dbAmt;
  final double? closingAcc;
  final double? closingPos;

  const BranchProjectionMonth({
    this.month = '',
    this.label = '',
    this.openingAcc,
    this.openingPos,
    this.closureAcc,
    this.closurePos,
    this.dbAcc,
    this.dbAmt,
    this.closingAcc,
    this.closingPos,
  });

  factory BranchProjectionMonth.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return BranchProjectionMonth(
      month: misToStr(j['month']) ?? '',
      label: misToStr(j['label']) ?? misToStr(j['short']) ?? '',
      openingAcc: misToDouble(j['opening_acc']),
      openingPos: misToDouble(j['opening_pos']),
      closureAcc: misToDouble(j['closure_acc']),
      closurePos: misToDouble(j['closure_pos']),
      dbAcc: misToDouble(j['db_acc']),
      dbAmt: misToDouble(j['db_amt']),
      closingAcc: misToDouble(j['closing_acc']),
      closingPos: misToDouble(j['closing_pos']),
    );
  }
}

/// `/branch-report` — the whole per-branch Report Card in one call, already
/// scoped: `branches` only lists what the caller may open, and the server
/// resolves the caller's own branch when none is requested.
class BranchReportResponse {
  final String tier;
  final List<BranchOption> branches;
  final String? branch;
  final String? bmName;
  final int foCount;
  final String? month;
  final List<String> months; // newest first
  final BranchPortfolio? portfolio;
  final List<BranchPerformance> performance;
  final List<BranchProjectionMonth> projection;

  const BranchReportResponse({
    this.tier = 'all',
    this.branches = const [],
    this.branch,
    this.bmName,
    this.foCount = 0,
    this.month,
    this.months = const [],
    this.portfolio,
    this.performance = const [],
    this.projection = const [],
  });

  factory BranchReportResponse.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final bm = _asMap(j['bm']);
    return BranchReportResponse(
      tier: misToStr(j['tier']) ?? 'all',
      branches: [
        if (j['branches'] is List)
          for (final b in j['branches'] as List) BranchOption.fromJson(b),
      ],
      branch: misToStr(j['branch']),
      bmName: misToStr(bm['name']),
      foCount: misToDouble(j['fo_count'])?.round() ?? 0,
      month: misToStr(j['month']),
      months: [
        if (j['months'] is List)
          for (final m in j['months'] as List)
            if (misToStr(m) != null) misToStr(m)!,
      ],
      portfolio:
          j['portfolio'] == null ? null : BranchPortfolio.fromJson(j['portfolio']),
      performance: [
        if (j['performance'] is List)
          for (final p in j['performance'] as List)
            BranchPerformance.fromJson(p),
      ],
      projection: [
        if (j['projection'] is List)
          for (final p in j['projection'] as List)
            BranchProjectionMonth.fromJson(p),
      ],
    );
  }
}
