import 'dart:math' as math;

/// The pure decision "does this fix become a route ping, and in which tracking
/// state?" — kept free of plugins so it can be unit-tested with plain numbers.
///
/// Inputs are the fix's own timestamp, position, accuracy and speed; the last
/// captured fix; and the server-tunable cadence. The rules:
///
///  * a fix with the SAME device timestamp as the last captured one is not new
///    (the OS stream went quiet; re-storing the stale position every interval
///    used to produce dt=0 duplicates that hid real outages);
///  * never two captures closer than [minCaptureGap] (3 s) — the floor for the
///    5-second moving cadence;
///  * MOVING = speed above [movingSpeedMps] or displacement since the last
///    capture at least twice the configured minimum; NEAR_CUSTOMER overrides;
///  * capture when the state's interval has elapsed, OR when the displacement
///    since the last capture clears max(minDisplacement, this fix's own error
///    radius) — so a vehicle produces a fix every stream tick while a parked
///    phone's jitter does not.
class CapturePolicy {
  CapturePolicy._();

  static const double movingSpeedMps = 1.5;
  static const Duration minCaptureGap = Duration(seconds: 3);
  /// Fixes worse than this are not worth a row — the server would reject them.
  static const double maxCaptureAccuracyMeters = 500;

  static CaptureDecision decide({
    required DateTime fixAt,
    required double lat,
    required double lng,
    required double accuracyMeters,
    required double speedMps,
    required DateTime now,
    required DateTime? lastCaptureAt,
    required DateTime? lastCapturedFixAt,
    required double? lastCapturedLat,
    required double? lastCapturedLng,
    required bool nearCustomer,
    required int movingSeconds,
    required int stationarySeconds,
    required int nearCustomerSeconds,
    required int minDisplacementMeters,
    required double Function(double, double, double, double) distanceMeters,
  }) {
    if (accuracyMeters > maxCaptureAccuracyMeters) {
      return const CaptureDecision(false, 'POOR', 'accuracy');
    }
    if (lastCapturedFixAt != null && !fixAt.isAfter(lastCapturedFixAt)) {
      return const CaptureDecision(false, 'STALE', 'same fix');
    }
    if (lastCaptureAt != null && now.difference(lastCaptureAt) < minCaptureGap) {
      return const CaptureDecision(false, 'WAIT', 'min gap');
    }

    double? displacement;
    if (lastCapturedLat != null && lastCapturedLng != null) {
      displacement = distanceMeters(lastCapturedLat, lastCapturedLng, lat, lng);
    }
    final moving = speedMps > movingSpeedMps ||
        (displacement != null && displacement >= minDisplacementMeters * 2);
    final state = nearCustomer
        ? 'NEAR_CUSTOMER'
        : moving
            ? 'MOVING'
            : 'STATIONARY';
    final interval = Duration(
        seconds: nearCustomer
            ? nearCustomerSeconds
            : moving
                ? movingSeconds
                : stationarySeconds);

    final dueByTime = lastCaptureAt == null || now.difference(lastCaptureAt) >= interval;
    var movedFar = displacement == null;
    if (!movedFar) {
      // The jump has to clear the configured displacement AND the fix's own
      // error radius, so a noisy fix while parked isn't travel.
      final threshold = math.max(minDisplacementMeters.toDouble(),
          math.min(accuracyMeters, maxCaptureAccuracyMeters));
      movedFar = displacement >= threshold;
    }
    if (!dueByTime && !movedFar) {
      return CaptureDecision(false, state, 'not due');
    }
    return CaptureDecision(true, state, dueByTime ? 'time' : 'distance');
  }
}

class CaptureDecision {
  const CaptureDecision(this.capture, this.state, this.why);
  final bool capture;
  /// MOVING / STATIONARY / NEAR_CUSTOMER — or POOR / STALE / WAIT when skipped.
  final String state;
  final String why;
}
