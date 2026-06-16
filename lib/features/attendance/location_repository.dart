import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'location_ping_models.dart';

class LocationRepository {
  LocationRepository(this._api);
  final ApiClient _api;

  /// Uploads a batch of pings. Server returns the saved count.
  Future<int> uploadBatch(LocationPingBatch batch) {
    return _api.post<int>(
      '/api/attendance/locations',
      body: batch.toJson(),
      parse: (d) => (d as num).toInt(),
    );
  }

  /// Answers an HR live-location request with the current fix, or the reason
  /// (permission/GPS off, timed out) it can't share one.
  Future<void> reportLive({
    required bool locationEnabled,
    required bool permissionGranted,
    required bool tracking,
    double? latitude,
    double? longitude,
    String? reason,
  }) {
    return _api.post<void>(
      '/api/attendance/locations/live-report',
      body: {
        'locationEnabled': locationEnabled,
        'permissionGranted': permissionGranted,
        'tracking': tracking,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (reason != null) 'reason': reason,
      },
      parse: (_) {},
    );
  }

  /// Heartbeat telling the server whether this device's location/GPS is on.
  /// Sent even when GPS is off, so HR can see "location turned off".
  Future<void> sendStatus({
    required bool locationEnabled,
    required bool permissionGranted,
    required bool tracking,
    double? latitude,
    double? longitude,
  }) {
    return _api.post<void>(
      '/api/attendance/locations/status',
      body: {
        'locationEnabled': locationEnabled,
        'permissionGranted': permissionGranted,
        'tracking': tracking,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
      parse: (_) {},
    );
  }
}

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => LocationRepository(ref.watch(apiClientProvider)),
);
