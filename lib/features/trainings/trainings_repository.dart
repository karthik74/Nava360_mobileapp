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
}
