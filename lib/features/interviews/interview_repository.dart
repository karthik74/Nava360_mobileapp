import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'interview_models.dart';

class InterviewRepository {
  InterviewRepository(this._api);
  final ApiClient _api;

  /// Candidates the logged-in employee has been assigned to interview.
  Future<List<Interview>> myInterviews() {
    return _api.get<List<Interview>>(
      '/api/candidates/my-interviews',
      parse: (d) {
        final list = (d as List?) ?? const [];
        return list
            .map((e) => Interview.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Records the assigned interviewer's verdict.
  /// [outcome] must be 'SELECTED' or 'REJECTED'.
  Future<void> submitDecision({
    required int candidateId,
    required String outcome,
    String? note,
  }) {
    return _api.post<void>(
      '/api/candidates/$candidateId/interview-decision',
      body: {
        'outcome': outcome,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      parse: (_) {},
    );
  }
}

final interviewRepositoryProvider = Provider<InterviewRepository>(
  (ref) => InterviewRepository(ref.watch(apiClientProvider)),
);

/// "My interviews" list — auto-disposes so it refetches when revisited.
final myInterviewsProvider =
    FutureProvider.autoDispose<List<Interview>>((ref) {
  return ref.watch(interviewRepositoryProvider).myInterviews();
});
