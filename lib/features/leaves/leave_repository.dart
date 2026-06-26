import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
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
