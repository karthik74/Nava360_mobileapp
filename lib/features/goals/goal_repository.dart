// ─────────────────────────────────────────────────────────────────────────────
//  My Goals — repository + Riverpod providers.
//
//  Talks to the same endpoints the web My Goals page uses:
//    GET /api/performance/assignments/employee/{employeeId}
//    PUT /api/performance/assignments/{id}/my-target
//
//  ApiClient unwraps the ApiResponse envelope, so `parse` receives the inner
//  payload directly. Only self-service endpoints are exposed here — assignment
//  creation and approval stay admin/manager-side on the web.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'goal_models.dart';

class GoalRepository {
  GoalRepository(this._api);
  final ApiClient _api;

  /// Every goal assigned to [employeeId], across all cycles.
  Future<List<EmployeeGoal>> listForEmployee(int employeeId) {
    return _api.get<List<EmployeeGoal>>(
      '/api/performance/assignments/employee/$employeeId',
      parse: (d) => (d as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EmployeeGoal.fromJson)
          .toList(),
    );
  }

  /// Proposes a new target for one of the caller's own goals.
  ///
  /// The server stores it as a PENDING change — the approved target is
  /// untouched until the employee's supervisor approves it.
  Future<EmployeeGoal> updateMyTarget(int assignmentId, double targetValue) {
    return _api.put<EmployeeGoal>(
      '/api/performance/assignments/$assignmentId/my-target',
      body: {'targetValue': targetValue},
      parse: (d) => EmployeeGoal.fromJson(d as Map<String, dynamic>),
    );
  }

  // ── Supervisor side ───────────────────────────────────────────────────────

  /// All performance cycles, newest-relevant first as returned by the server.
  Future<List<PerformanceCycle>> listCycles() {
    return _api.get<List<PerformanceCycle>>(
      '/api/performance/cycles',
      parse: (d) => (d as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PerformanceCycle.fromJson)
          .toList(),
    );
  }

  /// Target changes awaiting [managerEmployeeId]'s approval for one cycle.
  ///
  /// The server rejects this unless the caller IS that manager, so the screen
  /// always passes the signed-in user's own employee id.
  Future<List<EmployeeGoal>> listPendingTeamTargetChanges(
    int managerEmployeeId,
    int cycleId,
  ) {
    return _api.get<List<EmployeeGoal>>(
      '/api/performance/assignments/team-target-changes/$managerEmployeeId',
      query: {'cycleId': cycleId},
      parse: (d) => (d as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EmployeeGoal.fromJson)
          .toList(),
    );
  }

  /// Approves one pending change — the requested target becomes the approved one.
  Future<EmployeeGoal> approveTargetChange(int assignmentId) {
    return _api.put<EmployeeGoal>(
      '/api/performance/assignments/$assignmentId/target-change/approve',
      parse: (d) => EmployeeGoal.fromJson(d as Map<String, dynamic>),
    );
  }
}

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(apiClientProvider)),
);

/// The signed-in employee's goals. Refreshable via `ref.invalidate`.
final myGoalsProvider =
    FutureProvider.family<List<EmployeeGoal>, int>((ref, employeeId) {
  return ref.watch(goalRepositoryProvider).listForEmployee(employeeId);
});

/// All performance cycles, for the supervisor's cycle picker.
final performanceCyclesProvider =
    FutureProvider<List<PerformanceCycle>>((ref) {
  return ref.watch(goalRepositoryProvider).listCycles();
});

/// Identifies one supervisor's pending queue for a cycle.
class TeamTargetQuery {
  final int managerEmployeeId;
  final int cycleId;
  const TeamTargetQuery({required this.managerEmployeeId, required this.cycleId});

  @override
  bool operator ==(Object other) =>
      other is TeamTargetQuery &&
      other.managerEmployeeId == managerEmployeeId &&
      other.cycleId == cycleId;

  @override
  int get hashCode => Object.hash(managerEmployeeId, cycleId);
}

/// Target changes awaiting the supervisor's approval for one cycle.
final teamTargetChangesProvider =
    FutureProvider.family<List<EmployeeGoal>, TeamTargetQuery>((ref, q) {
  return ref
      .watch(goalRepositoryProvider)
      .listPendingTeamTargetChanges(q.managerEmployeeId, q.cycleId);
});
