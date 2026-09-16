/// A single GPS sample to send to the server.
///
/// [clientPingId] is generated once when the sample is captured and travels
/// with it through the offline queue, so a batch re-sent after a failed upload
/// is stored once — which also stops a replayed fix from inflating a detected
/// customer visit. The device context (id, mock flag, battery) is what lets the
/// backend judge how much to trust the fix.
class LocationPing {
  final String? clientPingId;
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? speedMps;
  final double? headingDegrees;
  final String? deviceId;
  final bool? mockLocation;
  final int? batteryLevel;

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
