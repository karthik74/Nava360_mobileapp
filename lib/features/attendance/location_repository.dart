import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'location_ping_models.dart';

/// Device diagnostics attached to the status heartbeat so the server-side GPS
/// audit can explain a tracking gap (battery restriction, missing background
/// permission, fixes still queued on the phone …). Every field is optional.
class HeartbeatDiagnostics {
  const HeartbeatDiagnostics({
    this.fixAt,
    this.accuracyMeters,
    this.pendingPings,
    this.lastCaptureAt,
    this.batteryLevel,
    this.batteryOptimisationIgnored,
    this.backgroundLocationGranted,
    this.serviceRunning,
    this.appVersion,
    this.poorFixesDiscarded,
    this.charging,
  });

  final DateTime? fixAt;
  final double? accuracyMeters;
  final int? pendingPings;
  final DateTime? lastCaptureAt;
  final int? batteryLevel;
  final bool? batteryOptimisationIgnored;
  final bool? backgroundLocationGranted;
  final bool? serviceRunning;
  final String? appVersion;
  final int? poorFixesDiscarded;
  final bool? charging;

  Map<String, dynamic> toJson() => {
        if (fixAt != null) 'fixAt': fixAt!.toUtc().toIso8601String(),
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (pendingPings != null) 'pendingPings': pendingPings,
        if (lastCaptureAt != null)
          'lastCaptureAt': lastCaptureAt!.toUtc().toIso8601String(),
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
        if (batteryOptimisationIgnored != null)
          'batteryOptimisationIgnored': batteryOptimisationIgnored,
        if (backgroundLocationGranted != null)
          'backgroundLocationGranted': backgroundLocationGranted,
        if (serviceRunning != null) 'serviceRunning': serviceRunning,
        if (appVersion != null) 'appVersion': appVersion,
        if (poorFixesDiscarded != null) 'poorFixesDiscarded': poorFixesDiscarded,
        if (charging != null) 'charging': charging,
      };
}

class LocationRepository {
  LocationRepository(this._api);
  final ApiClient _api;

  /// Whether the server answered the per-sample endpoint. Once a 404 says it
  /// does not exist (older backend) the count-only upload is used from then on.
  bool _batchV2Available = true;

  /// Uploads a batch (count-only answer; kept for older servers).
  Future<int> uploadBatch(LocationPingBatch batch) {
    return _api.post<int>(
      '/api/attendance/locations',
      body: batch.toJson(),
      parse: (d) => (d as num).toInt(),
    );
  }

  /// Uploads a batch and returns what the server did with each sample, so the
  /// offline queue can forget exactly the fixes the server now holds. Falls
  /// back to [uploadBatch] on a server without the per-sample endpoint.
  Future<LocationPingBatchResult> uploadBatchAcked(LocationPingBatch batch) async {
    if (_batchV2Available) {
      try {
        return await _api.post<LocationPingBatchResult>(
          '/api/attendance/locations/batch',
          body: batch.toJson(),
          parse: (d) => LocationPingBatchResult.fromJson(d as Map<String, dynamic>),
        );
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        _batchV2Available = false;
      }
    }
    final saved = await uploadBatch(batch);
    return LocationPingBatchResult.allAccepted(batch.pings, saved);
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

  /// Heartbeat telling the server whether this device's location/GPS is on,
  /// plus the diagnostics the GPS audit needs. Sent even when GPS is off, so HR
  /// can see "location turned off".
  Future<void> sendStatus({
    required bool locationEnabled,
    required bool permissionGranted,
    required bool tracking,
    double? latitude,
    double? longitude,
    HeartbeatDiagnostics? diagnostics,
  }) {
    return _api.post<void>(
      '/api/attendance/locations/status',
      body: {
        'locationEnabled': locationEnabled,
        'permissionGranted': permissionGranted,
        'tracking': tracking,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        ...?diagnostics?.toJson(),
      },
      parse: (_) {},
    );
  }
}

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => LocationRepository(ref.watch(apiClientProvider)),
);
