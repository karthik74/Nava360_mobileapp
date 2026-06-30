// ─────────────────────────────────────────────────────────────────────────────
//  FO Scorecard Performance — data models.
//
//  Mirrors the backend's PerformanceSummary / PerformanceDetail / PerformanceCompare
//  DTOs. All *Percentage values are RATIOS (1.0 == 100%) — multiply by 100 for
//  display. Parsing is defensive: numbers come through as num/String/null.
// ─────────────────────────────────────────────────────────────────────────────

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _toStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

/// A single FO's scorecard for one month/year period.
class PerformanceSummary {
  final int? id;
  final int? employeeId;
  final String? employeeCode;
  final String? employeeName;
  final String? branchName;
  final String? areaName;
  final String? divisionName;
  final String? regionName;
  final int? month;
  final int? year;
  final String? monthLabel;
  final int? dbTarget;
  final int? dbAchievement;
  final double? dbPercentage;
  final double? regularCollectionPercentage;
  final double? oneToNinetyPercentage;
  final double? onDatePercentage;
  final double? npaRecoveryPercentage;
  final double? overallPercentage;
  final int? nlplRank;
  final int? branchRank;
  final String? branchGrade;
  final String? syncedAt;

  const PerformanceSummary({
    this.id,
    this.employeeId,
    this.employeeCode,
    this.employeeName,
    this.branchName,
    this.areaName,
    this.divisionName,
    this.regionName,
    this.month,
    this.year,
    this.monthLabel,
    this.dbTarget,
    this.dbAchievement,
    this.dbPercentage,
    this.regularCollectionPercentage,
    this.oneToNinetyPercentage,
    this.onDatePercentage,
    this.npaRecoveryPercentage,
    this.overallPercentage,
    this.nlplRank,
    this.branchRank,
    this.branchGrade,
    this.syncedAt,
  });

  factory PerformanceSummary.fromJson(Map<String, dynamic> j) =>
      PerformanceSummary(
        id: _toInt(j['id']),
        employeeId: _toInt(j['employeeId']),
        employeeCode: _toStr(j['employeeCode']),
        employeeName: _toStr(j['employeeName']),
        branchName: _toStr(j['branchName']),
        areaName: _toStr(j['areaName']),
        divisionName: _toStr(j['divisionName']),
        regionName: _toStr(j['regionName']),
        month: _toInt(j['month']),
        year: _toInt(j['year']),
        monthLabel: _toStr(j['monthLabel']),
        dbTarget: _toInt(j['dbTarget']),
        dbAchievement: _toInt(j['dbAchievement']),
        dbPercentage: _toDouble(j['dbPercentage']),
        regularCollectionPercentage:
            _toDouble(j['regularCollectionPercentage']),
        oneToNinetyPercentage: _toDouble(j['oneToNinetyPercentage']),
        onDatePercentage: _toDouble(j['onDatePercentage']),
        npaRecoveryPercentage: _toDouble(j['npaRecoveryPercentage']),
        overallPercentage: _toDouble(j['overallPercentage']),
        nlplRank: _toInt(j['nlplRank']),
        branchRank: _toInt(j['branchRank']),
        branchGrade: _toStr(j['branchGrade']),
        syncedAt: _toStr(j['syncedAt']),
      );

  /// Hierarchy line "Branch · Area · Division · Region" (only present parts).
  String get hierarchyLabel => [
        if ((branchName ?? '').isNotEmpty) branchName!,
        if ((areaName ?? '').isNotEmpty) areaName!,
        if ((divisionName ?? '').isNotEmpty) divisionName!,
        if ((regionName ?? '').isNotEmpty) regionName!,
      ].join(' · ');
}

/// A single selectable month/year period for the scorecard.
class PeriodOption {
  final int month;
  final int year;
  final String label;

  const PeriodOption({
    required this.month,
    required this.year,
    required this.label,
  });

  factory PeriodOption.fromJson(Map<String, dynamic> j) => PeriodOption(
        month: _toInt(j['month']) ?? 0,
        year: _toInt(j['year']) ?? 0,
        label: _toStr(j['label']) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is PeriodOption && other.month == month && other.year == year;

  @override
  int get hashCode => Object.hash(month, year);
}

/// Full scorecard detail for one FO — the summary for the selected period plus
/// the list of periods the FO has data for.
class PerformanceDetail {
  final int employeeId;
  final String? employeeCode;
  final String? employeeName;
  final PerformanceSummary? summary;
  final List<PeriodOption> availablePeriods;
  final String? lastSyncedAt;

  const PerformanceDetail({
    required this.employeeId,
    this.employeeCode,
    this.employeeName,
    this.summary,
    this.availablePeriods = const [],
    this.lastSyncedAt,
  });

  factory PerformanceDetail.fromJson(Map<String, dynamic> j) {
    final periods = (j['availablePeriods'] as List?) ?? const [];
    final rawSummary = j['summary'];
    return PerformanceDetail(
      employeeId: _toInt(j['employeeId']) ?? 0,
      employeeCode: _toStr(j['employeeCode']),
      employeeName: _toStr(j['employeeName']),
      summary: rawSummary is Map<String, dynamic>
          ? PerformanceSummary.fromJson(rawSummary)
          : null,
      availablePeriods: periods
          .whereType<Map<String, dynamic>>()
          .map(PeriodOption.fromJson)
          .toList(),
      lastSyncedAt: _toStr(j['lastSyncedAt']),
    );
  }
}

/// Period-over-period deltas between two scorecards. For rank deltas NEGATIVE
/// means improvement; for percentage deltas POSITIVE means improvement.
class Deltas {
  final double? dbPercentage;
  final double? regularCollectionPercentage;
  final double? oneToNinetyPercentage;
  final double? onDatePercentage;
  final double? npaRecoveryPercentage;
  final double? overallPercentage;
  final int? nlplRank;
  final int? branchRank;

  const Deltas({
    this.dbPercentage,
    this.regularCollectionPercentage,
    this.oneToNinetyPercentage,
    this.onDatePercentage,
    this.npaRecoveryPercentage,
    this.overallPercentage,
    this.nlplRank,
    this.branchRank,
  });

  factory Deltas.fromJson(Map<String, dynamic> j) => Deltas(
        dbPercentage: _toDouble(j['dbPercentage']),
        regularCollectionPercentage:
            _toDouble(j['regularCollectionPercentage']),
        oneToNinetyPercentage: _toDouble(j['oneToNinetyPercentage']),
        onDatePercentage: _toDouble(j['onDatePercentage']),
        npaRecoveryPercentage: _toDouble(j['npaRecoveryPercentage']),
        overallPercentage: _toDouble(j['overallPercentage']),
        nlplRank: _toInt(j['nlplRank']),
        branchRank: _toInt(j['branchRank']),
      );
}

/// Comparison of two periods (A vs B) for a single FO.
class PerformanceCompare {
  final int employeeId;
  final String? employeeName;
  final PerformanceSummary? periodA;
  final PerformanceSummary? periodB;
  final Deltas deltas;

  const PerformanceCompare({
    required this.employeeId,
    this.employeeName,
    this.periodA,
    this.periodB,
    this.deltas = const Deltas(),
  });

  factory PerformanceCompare.fromJson(Map<String, dynamic> j) {
    final a = j['periodA'];
    final b = j['periodB'];
    final d = j['deltas'];
    return PerformanceCompare(
      employeeId: _toInt(j['employeeId']) ?? 0,
      employeeName: _toStr(j['employeeName']),
      periodA: a is Map<String, dynamic>
          ? PerformanceSummary.fromJson(a)
          : null,
      periodB: b is Map<String, dynamic>
          ? PerformanceSummary.fromJson(b)
          : null,
      deltas: d is Map<String, dynamic> ? Deltas.fromJson(d) : const Deltas(),
    );
  }
}

/// One page of [PerformanceSummary] rows (team / branch listings).
class PerformancePage {
  final List<PerformanceSummary> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool first;
  final bool last;

  const PerformancePage({
    this.content = const [],
    this.page = 0,
    this.size = 0,
    this.totalElements = 0,
    this.totalPages = 0,
    this.first = true,
    this.last = true,
  });

  factory PerformancePage.fromJson(Map<String, dynamic> j) {
    final rows = (j['content'] as List?) ?? const [];
    return PerformancePage(
      content: rows
          .whereType<Map<String, dynamic>>()
          .map(PerformanceSummary.fromJson)
          .toList(),
      page: _toInt(j['page']) ?? 0,
      size: _toInt(j['size']) ?? 0,
      totalElements: _toInt(j['totalElements']) ?? 0,
      totalPages: _toInt(j['totalPages']) ?? 0,
      first: j['first'] == true,
      last: j['last'] != false,
    );
  }
}
