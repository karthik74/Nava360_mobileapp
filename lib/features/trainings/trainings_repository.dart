import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'trainings_models.dart';

final trainingsRepositoryProvider =
    Provider((ref) => TrainingsRepository(ref.watch(apiClientProvider)));

class TrainingsRepository {
  TrainingsRepository(this._api);
  final ApiClient _api;

  Future<List<TrainingEnrollment>> getMyTrainings() {
    return _api.get<List<TrainingEnrollment>>(
      '/api/trainings/my',
      parse: (d) {
        if (d is List) {
          return d
              .map((e) => TrainingEnrollment.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (d is Map<String, dynamic>) {
          final content = d['content'] as List<dynamic>? ?? [];
          return content
              .map((e) => TrainingEnrollment.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        return [];
      },
    );
  }

  /// Marks the signed-in participant's attendance with a selfie (+ GPS / device).
  Future<void> markAttendance({
    required int trainingId,
    required String selfiePath,
    double? latitude,
    double? longitude,
    String? deviceInfo,
  }) async {
    final form = FormData.fromMap({
      'selfie': await MultipartFile.fromFile(selfiePath, filename: 'selfie.jpg'),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (deviceInfo != null) 'deviceInfo': deviceInfo,
    });
    await _api.raw.post<dynamic>(
      '/api/trainings/$trainingId/attendance/selfie',
      data: form,
    );
  }

  /// Participant test/feedback status (counts, best %, improvement, retake).
  Future<TrainingTestStatus> getTestStatus(int trainingId) {
    return _api.get<TrainingTestStatus>(
      '/api/trainings/$trainingId/tests/status',
      parse: (d) => TrainingTestStatus.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Questions for a section's form (no answer keys). section = PRE_TEST/POST_TEST/FEEDBACK.
  Future<List<TQuestion>> getQuestionForm(int trainingId, String section) {
    return _api.get<List<TQuestion>>(
      '/api/trainings/$trainingId/questions/$section/form',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => TQuestion.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Submit a Pre/Post test; returns the scored attempt JSON.
  Future<Map<String, dynamic>> submitTest(
    int trainingId,
    String section,
    List<Map<String, dynamic>> answers,
  ) async {
    final res = await _api.raw.post<Map<String, dynamic>>(
      '/api/trainings/$trainingId/tests/$section/submit',
      data: {'answers': answers},
    );
    return (res.data?['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Submit feedback.
  Future<void> submitFeedback(int trainingId, List<Map<String, dynamic>> answers) async {
    await _api.raw.post<dynamic>(
      '/api/trainings/$trainingId/feedback/submit',
      data: {'answers': answers},
    );
  }

  /// Materials for a training the employee is assigned to (files + links).
  Future<List<TrainingMaterial>> getMaterials(int trainingId) {
    return _api.get<List<TrainingMaterial>>(
      '/api/trainings/$trainingId/materials',
      parse: (d) {
        final list = (d as List?) ?? const [];
        return list
            .map((e) => TrainingMaterial.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }
}
