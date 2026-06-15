import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'team_models.dart';

class TeamRepository {
  TeamRepository(this._api);
  final ApiClient _api;

  /// Direct reports of the signed-in manager.
  Future<List<TeamMember>> myTeam() {
    return _api.get<List<TeamMember>>(
      '/api/employees/my-team',
      parse: (d) {
        final list = (d as List?) ?? const [];
        return list
            .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Attendance regularization requests raised by the manager's direct reports.
  Future<List<RegularizationRequest>> teamRegularizations() {
    return _api.get<List<RegularizationRequest>>(
      '/api/regularizations/team',
      query: {'size': 50, 'sort': 'createdAt,desc'},
      parse: (d) {
        final map = (d as Map<String, dynamic>?) ?? const {};
        final content = (map['content'] as List?) ?? const [];
        return content
            .map((e) =>
                RegularizationRequest.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Approve or reject a regularization request.
  /// [status] must be 'APPROVED' or 'REJECTED'.
  Future<void> reviewRegularization(
    int id, {
    required String status,
    int? reviewerEmployeeId,
    String? comment,
  }) {
    return _api.patch<void>(
      '/api/regularizations/$id/review',
      body: {
        'status': status,
        if (reviewerEmployeeId != null) 'reviewerEmployeeId': reviewerEmployeeId,
        if (comment != null && comment.trim().isNotEmpty)
          'reviewComment': comment.trim(),
      },
      parse: (_) {},
    );
  }
}

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(apiClientProvider)),
);

final teamMembersProvider =
    FutureProvider.autoDispose<List<TeamMember>>((ref) {
  return ref.watch(teamRepositoryProvider).myTeam();
});

final teamRegularizationsProvider =
    FutureProvider.autoDispose<List<RegularizationRequest>>((ref) {
  return ref.watch(teamRepositoryProvider).teamRegularizations();
});
