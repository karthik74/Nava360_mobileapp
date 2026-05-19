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
