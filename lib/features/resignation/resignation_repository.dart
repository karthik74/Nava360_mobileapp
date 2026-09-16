import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'resignation_models.dart';

class ResignationRepository {
  ResignationRepository(this._api);
  final ApiClient _api;

  /// The logged-in employee's own resignations (newest first by the backend).
  Future<List<Resignation>> myResignations() {
    return _api.get<List<Resignation>>(
      '/api/resignations/my',
      parse: (d) {
        final list = d is List
            ? d
            : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const []);
        return list
            .map((e) => Resignation.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Notice period derived from the employee's tenure/designation.
  Future<NoticePeriodInfo> myNoticePeriod() {
    return _api.get<NoticePeriodInfo>(
      '/api/resignations/my-notice-period',
      parse: (d) => NoticePeriodInfo.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Self-service: submit a resignation. [resignationDate] / [lastWorkingDay]
  /// are ISO `yyyy-MM-dd` strings.
  Future<Resignation> apply({
    required String resignationDate,
    String? lastWorkingDay,
    String? reason,
  }) {
    return _api.post<Resignation>(
      '/api/resignations/apply',
      body: {
        'resignationDate': resignationDate,
        if (lastWorkingDay != null && lastWorkingDay.isNotEmpty)
          'lastWorkingDay': lastWorkingDay,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      parse: (d) => Resignation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// The approver's inbox: every resignation approval step assigned to the
  /// logged-in employee. Reporting managers are approvers by workflow
  /// configuration, so this needs no HR permission.
  Future<List<ResignationApproval>> myApprovals({bool pendingOnly = false}) {
    return _api.get<List<ResignationApproval>>(
      '/api/resignations/my-approvals',
      query: {'pendingOnly': '$pendingOnly'},
      parse: (d) => (d as List<dynamic>)
          .map((e) => ResignationApproval.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Approve the caller's pending step on a resignation.
  Future<Resignation> approve(int id, {String? remarks}) {
    return _api.post<Resignation>(
      '/api/resignations/$id/approve',
      body: {if (remarks != null && remarks.isNotEmpty) 'remarks': remarks},
      parse: (d) => Resignation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Reject the caller's pending step on a resignation.
  Future<Resignation> reject(int id, {String? remarks}) {
    return _api.post<Resignation>(
      '/api/resignations/$id/reject',
      body: {if (remarks != null && remarks.isNotEmpty) 'remarks': remarks},
      parse: (d) => Resignation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Withdraw one of the employee's own resignations.
  Future<Resignation> withdraw(int id, {String? comment}) {
    return _api.post<Resignation>(
      '/api/resignations/$id/withdraw',
      body: {if (comment != null && comment.isNotEmpty) 'comment': comment},
      parse: (d) => Resignation.fromJson(d as Map<String, dynamic>),
    );
  }
}

final resignationRepositoryProvider = Provider<ResignationRepository>(
  (ref) => ResignationRepository(ref.watch(apiClientProvider)),
);

/// Resignation approvals assigned to the logged-in employee (pending + history).
final myResignationApprovalsProvider =
    FutureProvider.autoDispose<List<ResignationApproval>>((ref) {
  return ref.watch(resignationRepositoryProvider).myApprovals();
});
