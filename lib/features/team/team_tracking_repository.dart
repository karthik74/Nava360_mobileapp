import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// One GPS sample reported by a team member's device.
class TrackPing {
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? speedMps;
  final String? type;
  final String? referenceTitle;

  TrackPing({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.speedMps,
    this.type,
    this.referenceTitle,
  });

  factory TrackPing.fromJson(Map<String, dynamic> j) => TrackPing(
        recordedAt: DateTime.parse(j['recordedAt'] as String).toLocal(),
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        accuracyMeters: (j['accuracyMeters'] as num?)?.toDouble(),
        speedMps: (j['speedMps'] as num?)?.toDouble(),
        type: j['type'] as String?,
        referenceTitle: j['referenceTitle'] as String?,
      );
}

/// Live-location snapshot for a team member (mirrors the backend DTO).
class LiveLocation {
  final String state;
  final double? latitude;
  final double? longitude;
  final String? reason;
  final bool responded;
  final bool pending;
  final String message;
  final DateTime? respondedAt;

  LiveLocation({
    required this.state,
    this.latitude,
    this.longitude,
    this.reason,
    required this.responded,
    required this.pending,
    required this.message,
    this.respondedAt,
  });

  factory LiveLocation.fromJson(Map<String, dynamic> j) => LiveLocation(
        state: (j['state'] as String?) ?? 'UNKNOWN',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        reason: j['reason'] as String?,
        responded: (j['responded'] as bool?) ?? false,
        pending: (j['pending'] as bool?) ?? false,
        message: (j['message'] as String?) ?? '',
        respondedAt: j['respondedAt'] != null
            ? DateTime.tryParse(j['respondedAt'] as String)?.toLocal()
            : null,
      );
}

class TeamTrackingRepository {
  TeamTrackingRepository(this._api);
  final ApiClient _api;

  /// A direct report's pings for [date] (defaults to today on the server).
  Future<List<TrackPing>> memberDay(int employeeId, DateTime date) {
    final d =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _api.get<List<TrackPing>>(
      '/api/attendance/locations/team/$employeeId',
      query: {'date': d},
      parse: (data) {
        final list = (data as List?) ?? const [];
        return list
            .map((e) => TrackPing.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Ask the member's app for its current location (silent push).
  Future<LiveLocation> requestLive(int employeeId) {
    return _api.post<LiveLocation>(
      '/api/attendance/locations/team/$employeeId/live-request',
      parse: (d) => LiveLocation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Latest live-location snapshot the member's app reported.
  Future<LiveLocation> getLive(int employeeId) {
    return _api.get<LiveLocation>(
      '/api/attendance/locations/team/$employeeId/live',
      parse: (d) => LiveLocation.fromJson(d as Map<String, dynamic>),
    );
  }
}

final teamTrackingRepositoryProvider = Provider<TeamTrackingRepository>(
  (ref) => TeamTrackingRepository(ref.watch(apiClientProvider)),
);
