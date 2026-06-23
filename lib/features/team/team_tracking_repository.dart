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

/// A single location on/off transition event (mirrors LocationStatusEventResponse).
class LocationStatusEvent {
  final int id;
  final DateTime occurredAt;
  final String state; // ON | LOCATION_OFF | PERMISSION_OFF | NOT_TRACKING | UNKNOWN
  final double? latitude;
  final double? longitude;

  LocationStatusEvent({
    required this.id,
    required this.occurredAt,
    required this.state,
    this.latitude,
    this.longitude,
  });

  /// Whether location is currently considered "on" (tracking) at this event.
  bool get isOn => state == 'ON';

  factory LocationStatusEvent.fromJson(Map<String, dynamic> j) =>
      LocationStatusEvent(
        id: (j['id'] as num).toInt(),
        occurredAt: DateTime.parse(j['occurredAt'] as String).toLocal(),
        state: (j['state'] as String?) ?? 'UNKNOWN',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
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

  /// HR-style live-location request, matching the web "Live location" button.
  /// POST /api/attendance/locations/{id}/live-request (needs LOCATION_PING_VIEW).
  Future<LiveLocation> requestLiveDirect(int employeeId) {
    return _api.post<LiveLocation>(
      '/api/attendance/locations/$employeeId/live-request',
      parse: (d) => LiveLocation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Latest live snapshot via the HR endpoint the web polls.
  /// GET /api/attendance/locations/{id}/live (needs LOCATION_PING_VIEW).
  Future<LiveLocation> getLiveDirect(int employeeId) {
    return _api.get<LiveLocation>(
      '/api/attendance/locations/$employeeId/live',
      parse: (d) => LiveLocation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// On/off transition timeline for [employeeId] in [from, to] (newest first).
  /// Backend: GET /api/attendance/locations/status/{id}/history (LOCATION_PING_VIEW).
  /// The first event is the employee's current on/off status.
  Future<List<LocationStatusEvent>> statusHistory(
    int employeeId, {
    required DateTime from,
    required DateTime to,
  }) {
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return _api.get<List<LocationStatusEvent>>(
      '/api/attendance/locations/status/$employeeId/history',
      query: {'from': d(from), 'to': d(to)},
      parse: (data) {
        final list = (data as List?) ?? const [];
        return list
            .map((e) => LocationStatusEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }
}

final teamTrackingRepositoryProvider = Provider<TeamTrackingRepository>(
  (ref) => TeamTrackingRepository(ref.watch(apiClientProvider)),
);
