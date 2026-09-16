import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/approvals.dart';
import 'team_models.dart';

class TeamRepository {
  TeamRepository(this._api);
  final ApiClient _api;

  /// Full reporting downline of the signed-in manager — direct AND indirect
  /// reportees (all levels) — each with today's attendance state
  /// (Punched In / Punched Out / Absent / Leave / Not In). HR/Admin see everyone.
  Future<List<TeamMember>> myTeam() {
    return _api.get<List<TeamMember>>(
      '/api/employees/my-team/full/today-status',
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

  /// Regularizations waiting on the CALLER as a configured chain approver
  /// (Wave 4b approval engine) — chain approvers aren't necessarily direct
  /// managers.
  Future<List<RegularizationRequest>> regularizationsPendingMyApproval() {
    return _api.get<List<RegularizationRequest>>(
      '/api/regularizations/pending-my-approval',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => RegularizationRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The configured approval chain of one regularization (empty = default
  /// direct-manager flow; hide the chain UI).
  Future<List<ApprovalStep>> regularizationApprovalSteps(int id) {
    return _api.get<List<ApprovalStep>>(
      '/api/regularizations/$id/approval-steps',
      parse: ApprovalStep.listFromJson,
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

/// Regularizations pending the signed-in user's chain approval. Errors
/// degrade to an empty list so the section simply hides.
final regularizationsPendingMyApprovalProvider =
    FutureProvider.autoDispose<List<RegularizationRequest>>((ref) async {
  try {
    return await ref
        .watch(teamRepositoryProvider)
        .regularizationsPendingMyApproval();
  } catch (_) {
    return const [];
  }
});

/// Approval chain of one regularization (empty = no custom chain).
final regularizationApprovalStepsProvider = FutureProvider.autoDispose
    .family<List<ApprovalStep>, int>((ref, id) async {
  try {
    return await ref
        .watch(teamRepositoryProvider)
        .regularizationApprovalSteps(id);
  } catch (_) {
    return const [];
  }
});
