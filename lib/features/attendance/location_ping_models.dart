/// A single GPS sample to send to the server.
///
/// [clientPingId] is generated once when the sample is captured and travels
/// with it through the offline queue, so a batch re-sent after a failed upload
/// is stored once — which also stops a replayed fix from inflating a detected
/// customer visit. The device context (id, mock flag, battery, provider,
/// tracking state, app version, monotonic clock) is what lets the backend judge
/// how much to trust the fix and explain any gap around it.
class LocationPing {
  final String? clientPingId;
  /// The DEVICE's capture time. Never replaced by the upload time.
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? speedMps;
  final double? headingDegrees;
  final String? deviceId;
  final bool? mockLocation;
  final int? batteryLevel;
  /// FUSED (Android fused provider) / IOS.
  final String? provider;
  /// MOVING / STATIONARY / NEAR_CUSTOMER / START (first fix after a (re)start).
  final String? trackingState;
  final String? appVersion;
  /// Process-monotonic milliseconds at capture (a Stopwatch started with the
  /// tracking session) — unaffected by wall-clock changes.
  final int? elapsedRealtimeMs;

  LocationPing({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.clientPingId,
    this.accuracyMeters,
    this.speedMps,
    this.headingDegrees,
    this.deviceId,
    this.mockLocation,
    this.batteryLevel,
    this.provider,
    this.trackingState,
    this.appVersion,
    this.elapsedRealtimeMs,
  });

  Map<String, dynamic> toJson() => {
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        if (clientPingId != null) 'clientPingId': clientPingId,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (speedMps != null) 'speedMps': speedMps,
        if (headingDegrees != null) 'headingDegrees': headingDegrees,
        if (deviceId != null) 'deviceId': deviceId,
        if (mockLocation != null) 'mockLocation': mockLocation,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
        if (provider != null) 'provider': provider,
        if (trackingState != null) 'trackingState': trackingState,
        if (appVersion != null) 'appVersion': appVersion,
        if (elapsedRealtimeMs != null) 'elapsedRealtimeMs': elapsedRealtimeMs,
      };

  /// Rebuilds a ping from its persisted [toJson] form (offline queue).
  static LocationPing fromJson(Map<String, dynamic> json) => LocationPing(
        recordedAt:
            DateTime.parse(json['recordedAt'] as String).toUtc(),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        clientPingId: json['clientPingId'] as String?,
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        speedMps: (json['speedMps'] as num?)?.toDouble(),
        headingDegrees: (json['headingDegrees'] as num?)?.toDouble(),
        deviceId: json['deviceId'] as String?,
        mockLocation: json['mockLocation'] as bool?,
        batteryLevel: (json['batteryLevel'] as num?)?.toInt(),
        provider: json['provider'] as String?,
        trackingState: json['trackingState'] as String?,
        appVersion: json['appVersion'] as String?,
        elapsedRealtimeMs: (json['elapsedRealtimeMs'] as num?)?.toInt(),
      );
}

class LocationPingBatch {
  final int employeeId;
  final List<LocationPing> pings;
  LocationPingBatch({required this.employeeId, required this.pings});

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'pings': pings.map((p) => p.toJson()).toList(),
      };
}

/// What the server did with an uploaded batch, sample by sample.
///
/// The queue forgets exactly [acceptedClientIds] ∪ [duplicateClientIds]; a
/// sample in [rejectedRefs] can never be stored (no coordinates, out of range,
/// clock far in the future) and is dropped — counted, never silently.
class LocationPingBatchResult {
  final int saved;
  final int duplicates;
  final int rejected;
  final List<String> acceptedClientIds;
  final List<String> duplicateClientIds;
  /// Client id, or `#<index in the batch>` for a sample without one.
  final List<String> rejectedRefs;
  final DateTime? serverTime;

  const LocationPingBatchResult({
    required this.saved,
    required this.duplicates,
    required this.rejected,
    required this.acceptedClientIds,
    required this.duplicateClientIds,
    required this.rejectedRefs,
    this.serverTime,
  });

  static LocationPingBatchResult fromJson(Map<String, dynamic> j) {
    List<String> ids(String k) =>
        ((j[k] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();
    final rejected = ((j['rejectedSamples'] as List<dynamic>?) ?? const [])
        .whereType<Map>()
        .map((m) => m['ref']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return LocationPingBatchResult(
      saved: (j['saved'] as num?)?.toInt() ?? 0,
      duplicates: (j['duplicates'] as num?)?.toInt() ?? 0,
      rejected: (j['rejected'] as num?)?.toInt() ?? 0,
      acceptedClientIds: ids('acceptedClientIds'),
      duplicateClientIds: ids('duplicateClientIds'),
      rejectedRefs: rejected,
      serverTime: j['serverTime'] == null
          ? null
          : DateTime.tryParse(j['serverTime'] as String),
    );
  }

  /// A result for an old server that only returns a count: everything sent is
  /// treated as accepted (the old behaviour).
  static LocationPingBatchResult allAccepted(List<LocationPing> slice, int saved) =>
      LocationPingBatchResult(
        saved: saved,
        duplicates: 0,
        rejected: 0,
        acceptedClientIds: slice
            .map((p) => p.clientPingId)
            .whereType<String>()
            .toList(),
        duplicateClientIds: const [],
        rejectedRefs: const [],
      );
}
