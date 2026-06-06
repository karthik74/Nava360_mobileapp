import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'meetings_models.dart';

final meetingsRepositoryProvider =
    Provider((ref) => MeetingsRepository(ref.watch(apiClientProvider)));

class MeetingsRepository {
  MeetingsRepository(this._api);
  final ApiClient _api;

  Future<List<MeetingRecord>> getMyMeetings() {
    return _api.get<List<MeetingRecord>>(
      '/api/meetings/my',
      parse: (d) {
        if (d is List) {
          return d
              .map((e) => MeetingRecord.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (d is Map<String, dynamic>) {
          final content = d['content'] as List<dynamic>? ?? [];
          return content
              .map((e) => MeetingRecord.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        return [];
      },
    );
  }
}
