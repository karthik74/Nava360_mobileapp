import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/approvals.dart';
import 'leave_models.dart';

class LeaveRepository {
  LeaveRepository(this._api);
  final ApiClient _api;

  Future<List<LeaveRequest>> listForEmployee(int employeeId,
      {int page = 0, int size = 50}) async {
    return _api.get<List<LeaveRequest>>(
      '/api/leaves/employee/$employeeId',
      query: {'page': page, 'size': size},
      parse: (d) {
        final list = (d as Map<String, dynamic>)['content'] as List<dynamic>;
        return list
            .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Dates in [from..to] (yyyy-MM-dd) covered by a PENDING leave request for the
  /// employee, expanded across each request's from→to span. Used to flag
  /// "Leave request submitted" days on the attendance screen.
  Future<Set<String>> myPendingLeaveDates(
    int employeeId, {
    String? from,
    String? to,
  }) async {
    final leaves = await listForEmployee(employeeId, size: 100);
    final out = <String>{};
    for (final lv in leaves) {
      if (lv.status != 'PENDING') continue;
      final start = DateTime.tryParse(lv.fromDate);
      final end = DateTime.tryParse(lv.toDate);
      if (start == null || end == null) continue;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        final iso = '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        if (from != null && iso.compareTo(from) < 0) continue;
        if (to != null && iso.compareTo(to) > 0) continue;
        out.add(iso);
      }
    }
    return out;
  }

  Future<List<LeaveRequest>> listForTeam({int page = 0, int size = 50}) async {
    return _api.get<List<LeaveRequest>>(
      '/api/leaves/team',
      query: {'page': page, 'size': size},
      parse: (d) {
        final list = (d as Map<String, dynamic>)['content'] as List<dynamic>;
        return list
            .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Configured leave-type policies. Same source the web uses to build the
  /// apply-leave type list (`GET /api/leave-types?activeOnly=`).
  Future<List<LeaveTypePolicy>> listLeaveTypes({bool activeOnly = true}) {
    return _api.get<List<LeaveTypePolicy>>(
      '/api/leave-types',
      query: {'activeOnly': activeOnly},
      parse: (d) {
        final list = d is List
            ? d
            : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ??
                const []);
        return list
            .map((e) => LeaveTypePolicy.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<EmployeeLeaveBalances> getBalance(int employeeId) {
    return _api.get<EmployeeLeaveBalances>(
      '/api/leaves/balance/$employeeId',
      parse: (d) => EmployeeLeaveBalances.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<LeaveRequest> create(LeaveCreateRequest req) {
    return _api.post<LeaveRequest>(
      '/api/leaves',
      body: req.toJson(),
      parse: (d) => LeaveRequest.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Leaves waiting on the CALLER as a configured chain approver (Wave 4b
  /// approval engine). Empty when no chain step is pending on them — chain
  /// approvers aren't necessarily direct managers, so this is surfaced on the
  /// employee-facing Leaves screen too.
  Future<List<LeaveRequest>> pendingMyApproval() {
    return _api.get<List<LeaveRequest>>(
      '/api/leaves/pending-my-approval',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The configured approval chain of one leave (empty = default
  /// direct-manager flow; hide the chain UI).
  Future<List<ApprovalStep>> approvalSteps(int id) {
    return _api.get<List<ApprovalStep>>(
      '/api/leaves/$id/approval-steps',
      parse: ApprovalStep.listFromJson,
    );
  }

  Future<LeaveRequest> review(int id,
      {required String status, int? reviewerEmployeeId, String? reviewComment}) {
    return _api.patch<LeaveRequest>(
      '/api/leaves/$id/review',
      body: {
        'status': status,
        if (reviewerEmployeeId != null) 'reviewerEmployeeId': reviewerEmployeeId,
        if (reviewComment != null && reviewComment.isNotEmpty)
          'reviewComment': reviewComment,
      },
      parse: (d) => LeaveRequest.fromJson(d as Map<String, dynamic>),
    );
  }
}

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => LeaveRepository(ref.watch(apiClientProvider)),
);

/// Leaves pending the signed-in user's chain approval. Errors degrade to an
/// empty list so the section simply hides.
final leavesPendingMyApprovalProvider =
    FutureProvider.autoDispose<List<LeaveRequest>>((ref) async {
  try {
    return await ref.watch(leaveRepositoryProvider).pendingMyApproval();
  } catch (_) {
    return const [];
  }
});

/// Approval chain of one leave request (empty = no custom chain).
final leaveApprovalStepsProvider = FutureProvider.autoDispose
    .family<List<ApprovalStep>, int>((ref, id) async {
  try {
    return await ref.watch(leaveRepositoryProvider).approvalSteps(id);
  } catch (_) {
    return const [];
  }
});
