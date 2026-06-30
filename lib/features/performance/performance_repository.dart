// ─────────────────────────────────────────────────────────────────────────────
//  FO Scorecard Performance — repository + Riverpod providers.
//
//  All calls go through the shared ApiClient (relative paths only; the base URL
//  comes from Env.apiBaseUrl). ApiClient.get already unwraps the ApiResponse
//  envelope and returns `.data`, so `parse` receives the inner payload directly.
//  The admin-only POST /sync and /sync-logs endpoints are intentionally NOT
//  exposed on mobile.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'performance_models.dart';

/// Optional month/year selector for a scorecard request. Null month/year ⇒ let
/// the backend pick the latest available period.
class PerfQuery {
  final int? month;
  final int? year;
  const PerfQuery({this.month, this.year});

  Map<String, dynamic> get query => {
        if (month != null) 'month': month,
        if (year != null) 'year': year,
      };

  @override
  bool operator ==(Object other) =>
      other is PerfQuery && other.month == month && other.year == year;

  @override
  int get hashCode => Object.hash(month, year);
}

/// Identifies a specific employee's scorecard for a period.
class EmployeePerfQuery {
  final int employeeId;
  final int? month;
  final int? year;
  const EmployeePerfQuery(this.employeeId, {this.month, this.year});

  @override
  bool operator ==(Object other) =>
      other is EmployeePerfQuery &&
      other.employeeId == employeeId &&
      other.month == month &&
      other.year == year;

  @override
  int get hashCode => Object.hash(employeeId, month, year);
}

/// A page request against the team/branch listing endpoints.
class TeamPerfQuery {
  final int? month;
  final int? year;
  final String? q;
  final int page;
  final int size;
  final String? sort;
  final int? branchId;

  const TeamPerfQuery({
    this.month,
    this.year,
    this.q,
    this.page = 0,
    this.size = 20,
    this.sort,
    this.branchId,
  });

  Map<String, dynamic> get query => {
        if (month != null) 'month': month,
        if (year != null) 'year': year,
        if (q != null && q!.trim().isNotEmpty) 'q': q!.trim(),
        'page': page,
        'size': size,
        if (sort != null && sort!.isNotEmpty) 'sort': sort,
      };

  @override
  bool operator ==(Object other) =>
      other is TeamPerfQuery &&
      other.month == month &&
      other.year == year &&
      other.q == q &&
      other.page == page &&
      other.size == size &&
      other.sort == sort &&
      other.branchId == branchId;

  @override
  int get hashCode =>
      Object.hash(month, year, q, page, size, sort, branchId);
}

/// Identifies a two-period comparison request.
class ComparePerfQuery {
  final int? employeeId;
  final int monthA;
  final int yearA;
  final int monthB;
  final int yearB;
  const ComparePerfQuery({
    this.employeeId,
    required this.monthA,
    required this.yearA,
    required this.monthB,
    required this.yearB,
  });

  @override
  bool operator ==(Object other) =>
      other is ComparePerfQuery &&
      other.employeeId == employeeId &&
      other.monthA == monthA &&
      other.yearA == yearA &&
      other.monthB == monthB &&
      other.yearB == yearB;

  @override
  int get hashCode =>
      Object.hash(employeeId, monthA, yearA, monthB, yearB);
}

class PerformanceRepository {
  PerformanceRepository(this._api);
  final ApiClient _api;

  /// The signed-in employee's own scorecard.
  Future<PerformanceDetail> my(PerfQuery q) {
    return _api.get<PerformanceDetail>(
      '/api/performance/my',
      query: q.query,
      parse: (d) => PerformanceDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  /// A specific employee's scorecard (manager / HR view).
  Future<PerformanceDetail> employee(EmployeePerfQuery q) {
    return _api.get<PerformanceDetail>(
      '/api/performance/employee/${q.employeeId}',
      query: {
        if (q.month != null) 'month': q.month,
        if (q.year != null) 'year': q.year,
      },
      parse: (d) => PerformanceDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  /// The manager's team scorecard listing (paginated).
  Future<PerformancePage> team(TeamPerfQuery q) {
    return _api.get<PerformancePage>(
      '/api/performance/team',
      query: q.query,
      parse: (d) => PerformancePage.fromJson(d as Map<String, dynamic>),
    );
  }

  /// A branch's scorecard listing (paginated).
  Future<PerformancePage> branch(int branchId, TeamPerfQuery q) {
    return _api.get<PerformancePage>(
      '/api/performance/branch/$branchId',
      query: q.query,
      parse: (d) => PerformancePage.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Compare two periods for one FO.
  Future<PerformanceCompare> compare(ComparePerfQuery q) {
    return _api.get<PerformanceCompare>(
      '/api/performance/compare',
      query: {
        if (q.employeeId != null) 'employeeId': q.employeeId,
        'monthA': q.monthA,
        'yearA': q.yearA,
        'monthB': q.monthB,
        'yearB': q.yearB,
      },
      parse: (d) => PerformanceCompare.fromJson(d as Map<String, dynamic>),
    );
  }
}

final performanceRepositoryProvider = Provider<PerformanceRepository>(
  (ref) => PerformanceRepository(ref.watch(apiClientProvider)),
);

/// The signed-in employee's own scorecard for the given (optional) period.
final myPerformanceProvider =
    FutureProvider.autoDispose.family<PerformanceDetail, PerfQuery>(
  (ref, q) => ref.watch(performanceRepositoryProvider).my(q),
);

/// A specific employee's scorecard (used by the employee-detail Performance tab).
final employeePerformanceProvider =
    FutureProvider.autoDispose.family<PerformanceDetail, EmployeePerfQuery>(
  (ref, q) => ref.watch(performanceRepositoryProvider).employee(q),
);

/// A page of the manager's team scorecard listing.
final teamPerformanceProvider =
    FutureProvider.autoDispose.family<PerformancePage, TeamPerfQuery>(
  (ref, q) => ref.watch(performanceRepositoryProvider).team(q),
);

/// A two-period comparison for one FO.
final comparePerformanceProvider =
    FutureProvider.autoDispose.family<PerformanceCompare, ComparePerfQuery>(
  (ref, q) => ref.watch(performanceRepositoryProvider).compare(q),
);
