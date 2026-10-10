import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/attendance/tracking/capture_policy.dart';

/// Plain-number tests of the capture rule: 5-second cadence while moving, no
/// stale re-capture, no jitter capture while parked, slow cadence when still.
void main() {
  final t0 = DateTime.utc(2026, 10, 9, 4, 0, 0);
  double flat(double lat1, double lng1, double lat2, double lng2) =>
      ((lat2 - lat1).abs() + (lng2 - lng1).abs()) * 111000; // metres, good enough here

  CaptureDecision decide({
    required DateTime fixAt,
    required DateTime now,
    double lat = 15.3,
    double lng = 75.12,
    double accuracy = 10,
    double speed = 12,
    DateTime? lastCaptureAt,
    DateTime? lastFixAt,
    double? lastLat,
    double? lastLng,
    bool near = false,
  }) =>
      CapturePolicy.decide(
        fixAt: fixAt,
        lat: lat,
        lng: lng,
        accuracyMeters: accuracy,
        speedMps: speed,
        now: now,
        lastCaptureAt: lastCaptureAt,
        lastCapturedFixAt: lastFixAt,
        lastCapturedLat: lastLat,
        lastCapturedLng: lastLng,
        nearCustomer: near,
        movingSeconds: 5,
        stationarySeconds: 300,
        nearCustomerSeconds: 5,
        minDisplacementMeters: 10,
        distanceMeters: flat,
      );

  test('first fix is captured', () {
    final d = decide(fixAt: t0, now: t0);
    expect(d.capture, isTrue);
  });

  test('driving: a new fix 5 s and 55 m later is captured as MOVING', () {
    final d = decide(
      fixAt: t0.add(const Duration(seconds: 5)),
      now: t0.add(const Duration(seconds: 5)),
      lat: 15.3005,
      lastCaptureAt: t0,
      lastFixAt: t0,
      lastLat: 15.3,
      lastLng: 75.12,
    );
    expect(d.capture, isTrue);
    expect(d.state, 'MOVING');
  });

  test('the same device fix offered again is never re-captured', () {
    final d = decide(
      fixAt: t0,
      now: t0.add(const Duration(minutes: 6)),
      lastCaptureAt: t0,
      lastFixAt: t0,
      lastLat: 15.3,
      lastLng: 75.12,
    );
    expect(d.capture, isFalse);
    expect(d.state, 'STALE');
  });

  test('parked: jitter inside the error radius is not captured before the stationary interval', () {
    final d = decide(
      fixAt: t0.add(const Duration(seconds: 30)),
      now: t0.add(const Duration(seconds: 30)),
      lat: 15.30008, // ~9 m
      accuracy: 25,
      speed: 0,
      lastCaptureAt: t0,
      lastFixAt: t0,
      lastLat: 15.3,
      lastLng: 75.12,
    );
    expect(d.capture, isFalse);
    expect(d.state, 'STATIONARY');
  });

  test('parked: a fix is still captured every stationary interval', () {
    final d = decide(
      fixAt: t0.add(const Duration(seconds: 301)),
      now: t0.add(const Duration(seconds: 301)),
      speed: 0,
      lastCaptureAt: t0,
      lastFixAt: t0,
      lastLat: 15.3,
      lastLng: 75.12,
    );
    expect(d.capture, isTrue);
    expect(d.why, 'time');
  });

  test('never two captures within the 3 s minimum gap', () {
    final d = decide(
      fixAt: t0.add(const Duration(seconds: 2)),
      now: t0.add(const Duration(seconds: 2)),
      lat: 15.301,
      lastCaptureAt: t0,
      lastFixAt: t0,
      lastLat: 15.3,
      lastLng: 75.12,
    );
    expect(d.capture, isFalse);
    expect(d.state, 'WAIT');
  });

  test('a fix wider than 500 m is discarded', () {
    final d = decide(fixAt: t0, now: t0, accuracy: 900);
    expect(d.capture, isFalse);
    expect(d.state, 'POOR');
  });

  test('near a customer the state says so', () {
    final d = decide(
      fixAt: t0.add(const Duration(seconds: 6)),
      now: t0.add(const Duration(seconds: 6)),
      speed: 0,
      near: true,
      lastCaptureAt: t0,
      lastFixAt: t0,
      lastLat: 15.3,
      lastLng: 75.12,
    );
    expect(d.capture, isTrue);
    expect(d.state, 'NEAR_CUSTOMER');
  });
}
