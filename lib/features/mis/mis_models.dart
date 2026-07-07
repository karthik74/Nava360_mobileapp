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

/// One DPD bucket of the collection summary (account counts, not rupees).
class MisBucket {
  final String bucketName; // regular | on_date | 1_30 | 31_60 | 61_90 | pnpa | npa
  final double demandCount;
  final double collectionCount;
  const MisBucket({
    required this.bucketName,
    this.demandCount = 0,
    this.collectionCount = 0,
  });

  factory MisBucket.fromJson(Map<String, dynamic> j) => MisBucket(
        bucketName: misToStr(j['bucket_name']) ?? '',
        demandCount: misToDouble(j['demand_count']) ?? 0,
        collectionCount: misToDouble(j['collection_count']) ?? 0,
      );
}

class MisNpaAction {
  final String actionName; // activation | closure
  final double accounts;
  const MisNpaAction({required this.actionName, this.accounts = 0});

  factory MisNpaAction.fromJson(Map<String, dynamic> j) => MisNpaAction(
        actionName: misToStr(j['action_name']) ?? '',
        accounts: misToDouble(j['accounts']) ?? 0,
      );
}

/// `/collection/summary` — DPD buckets + NPA actions for the current scope.
class CollectionSummary {
  final List<MisBucket> dpd;
  final List<MisNpaAction> npa;
  final double npaCases;
  final String? date;

  const CollectionSummary({
    this.dpd = const [],
    this.npa = const [],
    this.npaCases = 0,
    this.date,
  });

  factory CollectionSummary.fromJson(dynamic raw) {
    final j = _asMap(raw);
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
    );
  }

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

  const CollectionRow({
    this.region,
    this.division,
    this.area,
    this.branch,
    this.name,
    this.empId,
    this.demandCount = 0,
    this.collectionCount = 0,
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
      );

  double get balance => demandCount - collectionCount;
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
  final double total;
  final double npa;
  final double npaAcc;
  final double regularAcc;
  final double sma0Acc;
  final double sma1Acc;
  final double pnpaAcc;

  const PortfolioUnitRow({
    this.unit = '',
    this.total = 0,
    this.npa = 0,
    this.npaAcc = 0,
    this.regularAcc = 0,
    this.sma0Acc = 0,
    this.sma1Acc = 0,
    this.pnpaAcc = 0,
  });

  factory PortfolioUnitRow.fromJson(Map<String, dynamic> j) => PortfolioUnitRow(
        unit: misToStr(j['unit']) ?? '',
        total: misToDouble(j['total']) ?? 0,
        npa: misToDouble(j['npa']) ?? 0,
        npaAcc: misToDouble(j['npa_acc']) ?? 0,
        regularAcc: misToDouble(j['regular_acc']) ?? 0,
        sma0Acc: misToDouble(j['sma0_acc']) ?? 0,
        sma1Acc: misToDouble(j['sma1_acc']) ?? 0,
        pnpaAcc: misToDouble(j['pnpa_acc']) ?? 0,
      );

  double get activeAcc => regularAcc + sma0Acc + sma1Acc + pnpaAcc;
  double get totalAcc => activeAcc + npaAcc;
  double get npaPct => total > 0 ? (npa / total) * 100 : 0;
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

// ── Analytical ───────────────────────────────────────────────────────────────

/// A per-unit analytical row. Fields are dynamic (per-bucket demand/collection
/// columns for collection mode; count/amount for disbursement mode), so the raw
/// map is kept and read through typed getters.
class AnalyticalRow {
  final Map<String, dynamic> raw;
  const AnalyticalRow(this.raw);

  String? get unit => misToStr(raw['unit']);
  String? get empId => misToStr(raw['emp_id']);
  double get count => misToDouble(raw['count']) ?? 0;
  double get amount => misToDouble(raw['amount']) ?? 0;

  /// Any numeric bucket field by name (e.g. "regular_demand").
  double field(String key) => misToDouble(raw[key]) ?? 0;
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
