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
