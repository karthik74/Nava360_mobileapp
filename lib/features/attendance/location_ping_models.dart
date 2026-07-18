/// A single GPS sample to send to the server.
class LocationPing {
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? speedMps;

  LocationPing({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.speedMps,
  });

  Map<String, dynamic> toJson() => {
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (speedMps != null) 'speedMps': speedMps,
      };

  /// Rebuilds a ping from its persisted [toJson] form (offline queue).
  static LocationPing fromJson(Map<String, dynamic> json) => LocationPing(
        recordedAt:
            DateTime.parse(json['recordedAt'] as String).toUtc(),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        speedMps: (json['speedMps'] as num?)?.toDouble(),
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
