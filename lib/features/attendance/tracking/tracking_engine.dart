import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/api_client.dart';
import '../../customers/nearby_customer_models.dart';
import '../location_ping_models.dart';
import '../location_ping_store.dart';
import '../location_repository.dart';
import 'capture_policy.dart';

/// Server-tunable capture cadence. Mirrors the tracking fields of
/// `/api/customers/nearby/config`; every value has a compiled-in fallback so
/// tracking never depends on a reachable server.
class TrackingConfig {
  const TrackingConfig({
    this.movingSeconds = 5,
    this.stationarySeconds = 300,
    this.nearCustomerSeconds = 5,
    this.nearCustomerRadiusMeters = 200,
    this.minDisplacementMeters = 10,
  });

  final int movingSeconds;
  final int stationarySeconds;
  final int nearCustomerSeconds;
  final int nearCustomerRadiusMeters;
  final int minDisplacementMeters;

  static const fallback = TrackingConfig();

  factory TrackingConfig.fromFieldVisit(FieldVisitConfig c) => TrackingConfig(
        movingSeconds: c.trackIntervalMovingSeconds,
        stationarySeconds: c.trackIntervalStationarySeconds,
        nearCustomerSeconds: c.trackIntervalNearCustomerSeconds,
        nearCustomerRadiusMeters: c.trackNearCustomerRadiusMeters,
        minDisplacementMeters: c.trackMinDisplacementMeters,
      );

  Map<String, dynamic> toJson() => {
        'movingSeconds': movingSeconds,
        'stationarySeconds': stationarySeconds,
        'nearCustomerSeconds': nearCustomerSeconds,
        'nearCustomerRadiusMeters': nearCustomerRadiusMeters,
        'minDisplacementMeters': minDisplacementMeters,
      };

  static TrackingConfig fromJson(Map<String, dynamic> j) {
    int pick(String k, int fallback) {
      final v = (j[k] as num?)?.toInt();
      return v == null || v <= 0 ? fallback : v;
    }

    return TrackingConfig(
      movingSeconds: pick('movingSeconds', 5),
      stationarySeconds: pick('stationarySeconds', 300),
      nearCustomerSeconds: pick('nearCustomerSeconds', 5),
      nearCustomerRadiusMeters: pick('nearCustomerRadiusMeters', 200),
      minDisplacementMeters: pick('minDisplacementMeters', 10),
    );
  }

  TrackingConfig merge({
    int? movingSeconds,
    int? stationarySeconds,
    int? nearCustomerSeconds,
    int? nearCustomerRadiusMeters,
    int? minDisplacementMeters,
  }) {
    int keep(int? v, int cur) => v == null || v <= 0 ? cur : v;
    return TrackingConfig(
      movingSeconds: keep(movingSeconds, this.movingSeconds),
      stationarySeconds: keep(stationarySeconds, this.stationarySeconds),
      nearCustomerSeconds: keep(nearCustomerSeconds, this.nearCustomerSeconds),
      nearCustomerRadiusMeters:
          keep(nearCustomerRadiusMeters, this.nearCustomerRadiusMeters),
      minDisplacementMeters:
          keep(minDisplacementMeters, this.minDisplacementMeters),
    );
  }
}

/// Point-in-time view of the engine, serialisable so the background service
/// isolate can hand it to the UI.
class TrackingSnapshot {
  const TrackingSnapshot({
    required this.active,
    required this.employeeId,
    this.lastCapturedAt,
    this.lastFlushedAt,
    this.lastFixAt,
    this.bufferedCount = 0,
    this.sentCount = 0,
    this.lastError,
    this.locationEnabled = true,
    this.authExpired = false,
    this.poorFixes = 0,
    this.droppedCount = 0,
    this.trackingState,
    this.gpsWeak = false,
  });

  final bool active;
  final int? employeeId;
  final DateTime? lastCapturedAt;
  final DateTime? lastFlushedAt;
  /// When the OS last delivered any fix at all (captured or not).
  final DateTime? lastFixAt;
  final int bufferedCount;
  final int sentCount;
  final String? lastError;
  final bool locationEnabled;
  /// Uploads are failing with 401: the stored token is no longer valid. Pings
  /// keep queueing; they upload after the next login.
  final bool authExpired;
  /// Fixes discarded this session because the OS reported them wider than 500 m.
  final int poorFixes;
  /// Samples the server refused outright (can never be stored) and were dropped.
  final int droppedCount;
  /// MOVING / STATIONARY / NEAR_CUSTOMER of the last capture.
  final String? trackingState;
  /// The OS is delivering only unusable fixes right now (indoors, no sky view).
  final bool gpsWeak;

  Map<String, dynamic> toJson() => {
        'active': active,
        'employeeId': employeeId,
        'lastCapturedAt': lastCapturedAt?.toUtc().toIso8601String(),
        'lastFlushedAt': lastFlushedAt?.toUtc().toIso8601String(),
        'lastFixAt': lastFixAt?.toUtc().toIso8601String(),
        'bufferedCount': bufferedCount,
        'sentCount': sentCount,
        'lastError': lastError,
        'locationEnabled': locationEnabled,
        'authExpired': authExpired,
        'poorFixes': poorFixes,
        'droppedCount': droppedCount,
        'trackingState': trackingState,
        'gpsWeak': gpsWeak,
      };

  static TrackingSnapshot fromJson(Map<String, dynamic> j) {
    DateTime? t(String k) {
      final v = j[k] as String?;
      return v == null ? null : DateTime.tryParse(v)?.toLocal();
    }

    return TrackingSnapshot(
      active: j['active'] == true,
      employeeId: (j['employeeId'] as num?)?.toInt(),
      lastCapturedAt: t('lastCapturedAt'),
      lastFlushedAt: t('lastFlushedAt'),
      lastFixAt: t('lastFixAt'),
      bufferedCount: (j['bufferedCount'] as num?)?.toInt() ?? 0,
      sentCount: (j['sentCount'] as num?)?.toInt() ?? 0,
      lastError: j['lastError'] as String?,
      locationEnabled: j['locationEnabled'] != false,
      authExpired: j['authExpired'] == true,
      poorFixes: (j['poorFixes'] as num?)?.toInt() ?? 0,
      droppedCount: (j['droppedCount'] as num?)?.toInt() ?? 0,
      trackingState: j['trackingState'] as String?,
      gpsWeak: j['gpsWeak'] == true,
    );
  }
}

/// The GPS capture + upload machine for one tracking session.
///
/// Host-agnostic: on Android it runs inside the foreground-service isolate
/// (see `tracking_task.dart`), on iOS inside the app's main isolate. The host
/// owns the clock — it calls [tick] every ~15 s — and the engine does
/// everything else:
///
///  * subscribes to the OS position stream at 5 s while moving and 30 s once
///    the phone has been still for a while (adaptive sampling),
///  * decides which fixes become route pings ([CapturePolicy]: time- and
///    distance-based, faster while moving or near a customer),
///  * persists each ping to the durable queue BEFORE it is counted as captured,
///  * uploads in chunks with exponential back-off and per-sample server
///    acknowledgements, forgetting exactly what the server holds,
///  * sends the location on/off heartbeat with device diagnostics (pending
///    count, battery, background permission, battery-optimisation exemption),
///  * self-heals: a silent stream is re-subscribed, a location toggle is
///    reacted to immediately, and the server cadence is re-fetched periodically.
///
/// What it cannot do, and does not pretend to: keep recording after the user
/// force-stops the app, revokes the location permission, or turns location
/// off. Those are reported to the server as status, so the gap is explained.
class TrackingEngine {
  TrackingEngine({
    required this.employeeId,
    required this.repo,
    required this.store,
    this.deviceId,
    this.appVersion,
    this.serviceHosted = false,
    TrackingConfig? config,
    this.onSnapshot,
    this.onSessionExpired,
  }) : _cfg = config ?? TrackingConfig.fallback;

  final int employeeId;
  final LocationRepository repo;
  final LocationPingStore store;
  final String? deviceId;
  final String? appVersion;
  /// True when the engine runs inside the Android foreground service.
  final bool serviceHosted;
  final void Function(TrackingSnapshot snapshot)? onSnapshot;
  /// Fired once when a session has outlived [maxSessionLength] — the employee
  /// forgot to check out. The host should stop the engine and the service.
  final void Function()? onSessionExpired;

  // ── Tunables (compiled-in; cadence itself comes from [TrackingConfig]) ──
  /// Upload when the buffer reaches this many pings …
  static const int _flushAtCount = 20;
  /// … or this long after the last successful upload, whichever comes first.
  static const Duration _flushInterval = Duration(seconds: 60);
  /// Largest batch per request — a long offline stretch is drained in slices.
  static const int _flushChunkMax = 200;
  static const Duration _backoffMin = Duration(seconds: 30);
  static const Duration _backoffMax = Duration(minutes: 10);
  /// A 401 is not a transient network error; wait longer before retrying.
  static const Duration _authBackoff = Duration(minutes: 10);
  static const Duration _heartbeatInterval = Duration(minutes: 3);
  static const Duration _heartbeatMinGap = Duration(seconds: 90);
  /// No RAW fix (usable or not) for this long while location is on = the
  /// stream has died; rebuild it.
  static const Duration _streamSilenceLimit = Duration(minutes: 2);
  static const Duration _configRefreshInterval = Duration(minutes: 30);
  /// OS stream cadence while moving. Fine-grained on purpose: 5 s at 40 km/h is
  /// a fix every 55 m, which keeps the recorded line on the road instead of
  /// cutting corners (a 60 s cadence lost 20–35 % of a winding road's length).
  static const Duration _streamIntervalMoving = Duration(seconds: 5);
  /// OS stream cadence once the phone has been still for [_stationaryAfter].
  static const Duration _streamIntervalStationary = Duration(seconds: 30);
  static const Duration _stationaryAfter = Duration(minutes: 2);
  /// A session this old without a check-out is a forgotten one.
  static const Duration maxSessionLength = Duration(hours: 20);
  /// Only unusable fixes for this long = "GPS weak" on the notification.
  static const Duration _weakAfter = Duration(seconds: 90);

  // ── Runtime ──
  TrackingConfig _cfg;
  List<({double lat, double lng})> _nearbyCustomerPoints = const [];
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  Position? _lastPosition;
  Position? _lastCapturedPosition;
  DateTime? _lastRawFixAt;
  DateTime? _lastUsableFixAt;
  DateTime? _lastCaptureAt;
  DateTime? _lastMovementAt;
  DateTime? _lastFlushedAt;
  DateTime? _lastFlushAttemptAt;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastConfigRefreshAt;
  DateTime? _lastBatteryReadAt;
  DateTime? _startedAt;
  Duration _backoff = _backoffMin;
  bool _authExpired = false;
  bool _locationEnabled = true;
  bool _active = false;
  bool _expiredFired = false;
  bool _streamFast = true;
  bool _firstCapture = true;
  bool _statusDirty = false;
  String? _lastError;
  String? _trackingState;
  int _sentCount = 0;
  int _pingSeq = 0;
  int _poorFixes = 0;
  int _droppedCount = 0;
  int _flushChunk = _flushChunkMax;
  int? _battery;
  final Stopwatch _clock = Stopwatch();
  final Battery _batteryPlugin = Battery();
  final List<LocationPing> _buffer = [];
  Future<void>? _flushInFlight;
  Future<void>? _resubscribeInFlight;

  bool get active => _active;
  bool get _gpsWeak {
    final raw = _lastRawFixAt;
    final usable = _lastUsableFixAt;
    if (raw == null) return false;
    if (usable == null) {
      return DateTime.now().difference(raw) < _streamSilenceLimit && _poorFixes > 0;
    }
    return raw.difference(usable) > _weakAfter;
  }

  TrackingSnapshot get snapshot => TrackingSnapshot(
        active: _active,
        employeeId: employeeId,
        lastCapturedAt: _lastCaptureAt,
        lastFlushedAt: _lastFlushedAt,
        lastFixAt: _lastRawFixAt,
        bufferedCount: _buffer.length,
        sentCount: _sentCount,
        lastError: _lastError,
        locationEnabled: _locationEnabled,
        authExpired: _authExpired,
        poorFixes: _poorFixes,
        droppedCount: _droppedCount,
        trackingState: _trackingState,
        gpsWeak: _gpsWeak,
      );

  /// Starts capturing. [sessionStartedAt] is the check-in time persisted by the
  /// host so a service restarted after a reboot still knows how old the
  /// session is. [androidForegroundNotification] is only passed when the engine
  /// runs in the app process (iOS, or the Android fallback) and geolocator has
  /// to hold its own foreground service; inside our own service it is null.
  Future<void> start({
    DateTime? sessionStartedAt,
    ForegroundNotificationConfig? androidForegroundNotification,
  }) async {
    if (_active) return;
    _active = true;
    _clock.start();
    _startedAt = sessionStartedAt ?? DateTime.now();
    _androidForegroundNotification = androidForegroundNotification;
    _firstCapture = true;

    // Whatever an earlier process left in the durable queue goes first.
    try {
      final persisted = await store.load(employeeId);
      if (persisted.isNotEmpty) {
        _buffer.insertAll(0, persisted);
      }
    } catch (_) {
      // A read failure must not block tracking.
    }

    _streamFast = true;
    await _subscribe();
    _serviceSub = Geolocator.getServiceStatusStream().listen(
      _onServiceStatus,
      onError: (_) {},
    );

    unawaited(_readBattery());
    _lastHeartbeatAt = DateTime.now();
    unawaited(_sendHeartbeat(tracking: true));
    _emit();

    // Immediate baseline fix so the first point lands at check-in, not a
    // minute later.
    unawaited(_primeWithCurrentPosition());
    unawaited(_maybeRefreshConfig(force: true));
    _maybeAutoFlush();
  }

  ForegroundNotificationConfig? _androidForegroundNotification;

  /// Stops capturing. With [flush] the remaining buffer is uploaded (bounded by
  /// [flushTimeout]). With [announce] the server is told tracking is off —
  /// false when the OS is tearing the service down and auto-restart will bring
  /// the session back, so the server does not record a false "not tracking".
  Future<void> stop({
    bool flush = true,
    bool announce = true,
    Duration flushTimeout = const Duration(seconds: 10),
  }) async {
    if (!_active) return;
    _active = false;
    await _positionSub?.cancel();
    await _serviceSub?.cancel();
    _positionSub = null;
    _serviceSub = null;

    if (flush && _buffer.isNotEmpty) {
      try {
        await _flush(force: true).timeout(flushTimeout);
      } catch (_) {
        // Still queued on disk; the next session or app start drains it.
      }
    }
    if (announce) {
      try {
        await _sendHeartbeat(tracking: false).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _buffer.clear();
    _lastPosition = null;
    _lastCapturedPosition = null;
    _clock.stop();
    _emit();
  }

  /// Host clock. Safe to call often; everything inside is throttled.
  void tick() {
    if (!_active) return;
    final now = DateTime.now();

    if (!_expiredFired &&
        _startedAt != null &&
        now.difference(_startedAt!) > maxSessionLength) {
      _expiredFired = true;
      onSessionExpired?.call();
      return;
    }

    _maybeCapture();
    _maybeAutoFlush();
    _maybeSwitchStreamRate(now);

    if (_statusDirty ||
        _lastHeartbeatAt == null ||
        now.difference(_lastHeartbeatAt!) >= _heartbeatInterval) {
      _lastHeartbeatAt = now;
      unawaited(_sendHeartbeat(tracking: true));
    }

    // Watchdog: location is on but the stream has gone quiet — rebuild it.
    // Measured on RAW fixes, so a stream that only delivers unusable fixes is
    // left alone (it is alive; the sky is the problem) and reported as weak.
    final lastRaw = _lastRawFixAt ?? _startedAt ?? now;
    if (_locationEnabled && now.difference(lastRaw) > _streamSilenceLimit) {
      _lastRawFixAt = now; // don't re-trigger every tick while recovering
      unawaited(_resubscribe());
      unawaited(_primeWithCurrentPosition());
    }

    if (_lastBatteryReadAt == null ||
        now.difference(_lastBatteryReadAt!) > const Duration(minutes: 1)) {
      unawaited(_readBattery());
    }
    unawaited(_maybeRefreshConfig());
  }

  void applyConfig(TrackingConfig cfg) {
    _cfg = cfg;
  }

  void setNearbyCustomerPoints(List<({double lat, double lng})> points) {
    _nearbyCustomerPoints = points;
  }

  /// Upload now, ignoring the count/age thresholds (app came to the foreground,
  /// network came back …). Back-off still applies to avoid hammering.
  Future<void> flushNow() => _flush(force: true);

  // ── Position stream ──────────────────────────────────────────────────────

  LocationSettings _settings() {
    final interval = _streamFast ? _streamIntervalMoving : _streamIntervalStationary;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: interval,
        foregroundNotificationConfig: _androidForegroundNotification,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        // Foreground-only on iOS: the App Store build has no location
        // background mode (guideline 2.5.4), and enabling background updates
        // without it crashes CoreLocation.
        allowBackgroundLocationUpdates: false,
        activityType: ActivityType.automotiveNavigation,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  Future<void> _subscribe() async {
    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(_onPosition, onError: _onStreamError, cancelOnError: false);
  }

  Future<void> _resubscribe() {
    return _resubscribeInFlight ??= () async {
      try {
        await _subscribe();
      } catch (e) {
        _lastError = 'Location stream restart failed: $e';
      } finally {
        _resubscribeInFlight = null;
      }
    }();
  }

  /// Adaptive sampling: 5 s while there has been movement in the last two
  /// minutes, 30 s once parked. The first fix after the slow stream shows a
  /// displacement switches straight back to the fast one.
  void _maybeSwitchStreamRate(DateTime now) {
    final movedRecently = _lastMovementAt != null &&
        now.difference(_lastMovementAt!) < _stationaryAfter;
    final wantFast = movedRecently || _lastCapturedPosition == null;
    if (wantFast == _streamFast) return;
    _streamFast = wantFast;
    unawaited(_resubscribe());
  }

  Future<void> _primeWithCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      _onPosition(pos);
    } catch (_) {
      // Cold start / indoors — the stream catches up.
    }
  }

  void _onPosition(Position p) {
    if (!_active) return;
    _lastRawFixAt = DateTime.now();
    _locationEnabled = true;
    // Wild fixes (a cell-tower guess 2 km wide) tell us nothing about the
    // route; they are counted so the heartbeat can say "GPS weak" rather than
    // letting the server see a silent phone.
    if (p.accuracy > CapturePolicy.maxCaptureAccuracyMeters) {
      _poorFixes++;
      _emit();
      return;
    }
    _lastUsableFixAt = _lastRawFixAt;
    _lastPosition = p;
    _maybeCapture();
  }

  void _onStreamError(Object e) {
    _lastError = e.toString();
    if (e is LocationServiceDisabledException) {
      _locationEnabled = false;
      _statusDirty = true;
      _lastHeartbeatAt = DateTime.now();
      unawaited(_sendHeartbeat(tracking: true));
    }
    _emit();
  }

  void _onServiceStatus(ServiceStatus status) {
    final enabled = status == ServiceStatus.enabled;
    if (enabled == _locationEnabled) return;
    _locationEnabled = enabled;
    // Tell HR right away — this is the "location turned off" signal. If the
    // phone is offline the heartbeat fails and stays dirty until it gets out.
    _statusDirty = true;
    _lastHeartbeatAt = DateTime.now();
    unawaited(_sendHeartbeat(tracking: true));
    if (enabled) {
      unawaited(_resubscribe());
      unawaited(_primeWithCurrentPosition());
    }
    _emit();
  }

  // ── Capture policy ───────────────────────────────────────────────────────

  bool _nearCustomer(Position p) {
    if (_nearbyCustomerPoints.isEmpty) return false;
    for (final c in _nearbyCustomerPoints) {
      if (Geolocator.distanceBetween(p.latitude, p.longitude, c.lat, c.lng) <=
          _cfg.nearCustomerRadiusMeters) {
        return true;
      }
    }
    return false;
  }

  void _maybeCapture() {
    final p = _lastPosition;
    if (!_active || p == null) return;
    final now = DateTime.now();
    final last = _lastCapturedPosition;
    final d = CapturePolicy.decide(
      fixAt: p.timestamp,
      lat: p.latitude,
      lng: p.longitude,
      accuracyMeters: p.accuracy,
      speedMps: p.speed,
      now: now,
      lastCaptureAt: _lastCaptureAt,
      lastCapturedFixAt: last?.timestamp,
      lastCapturedLat: last?.latitude,
      lastCapturedLng: last?.longitude,
      nearCustomer: _nearCustomer(p),
      movingSeconds: _cfg.movingSeconds,
      stationarySeconds: _cfg.stationarySeconds,
      nearCustomerSeconds: _cfg.nearCustomerSeconds,
      minDisplacementMeters: _cfg.minDisplacementMeters,
      distanceMeters: Geolocator.distanceBetween,
    );
    if (d.state == 'MOVING' || d.state == 'NEAR_CUSTOMER') _lastMovementAt = now;
    if (!d.capture) return;
    _capture(p, d.state);
  }

  void _capture(Position p, String state) {
    final tag = _firstCapture ? 'START' : state;
    _firstCapture = false;
    _trackingState = state;
    final ping = LocationPing(
      // Idempotency key: employee + capture time + a counter. Travels with the
      // ping through the durable queue, so a batch retried after a timeout is
      // stored once and cannot be counted twice inside a visit.
      clientPingId:
          '$employeeId-${p.timestamp.toUtc().millisecondsSinceEpoch}-${_pingSeq++}',
      recordedAt: p.timestamp.toUtc(),
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMeters: p.accuracy,
      speedMps: p.speed,
      headingDegrees: p.heading,
      deviceId: deviceId,
      // Android reports spoofed positions; iOS has no equivalent signal, so
      // null there means "unknown", not "genuine".
      mockLocation: p.isMocked,
      batteryLevel: _battery,
      provider: Platform.isIOS ? 'IOS' : 'FUSED',
      trackingState: tag,
      appVersion: appVersion,
      elapsedRealtimeMs: _clock.elapsedMilliseconds,
    );
    _buffer.add(ping);
    // Durable first: an offline ping is never lost if the OS kills the process
    // before it can be uploaded. A write failure is surfaced, not swallowed.
    unawaited(store.append(employeeId, [ping]).catchError((Object e) {
      _lastError = 'Could not save a GPS point on the phone: $e';
      _emit();
    }));
    _lastCaptureAt = DateTime.now();
    _lastCapturedPosition = p;
    _emit();
    _maybeAutoFlush();
  }

  // ── Upload ───────────────────────────────────────────────────────────────

  void _maybeAutoFlush() {
    if (_buffer.isEmpty) return;
    final byCount = _buffer.length >= _flushAtCount;
    final byAge = _lastFlushedAt == null ||
        DateTime.now().difference(_lastFlushedAt!) >= _flushInterval;
    if (byCount || byAge) unawaited(_flush());
  }

  bool _inBackoff(DateTime now) {
    final last = _lastFlushAttemptAt;
    if (last == null) return false;
    final wait = _authExpired ? _authBackoff : _backoff;
    return now.difference(last) < wait;
  }

  Future<void> _flush({bool force = false}) {
    return _flushInFlight ??= () async {
      try {
        await _doFlush(force: force);
      } finally {
        _flushInFlight = null;
      }
    }();
  }

  Future<void> _doFlush({required bool force}) async {
    if (_buffer.isEmpty) return;
    final now = DateTime.now();
    // Back-off applies to retries after a failure; a forced flush right after
    // a failure would just fail again.
    if (_lastError != null && _inBackoff(now) && !force) return;
    if (_authExpired && _inBackoff(now)) return;

    while (_buffer.isNotEmpty) {
      final slice = _buffer.take(_flushChunk).toList(growable: false);
      _lastFlushAttemptAt = DateTime.now();
      try {
        final result = await repo.uploadBatchAcked(
          LocationPingBatch(employeeId: employeeId, pings: slice),
        );
        await _applyAcks(slice, result);
        _lastFlushedAt = DateTime.now();
        _lastError = null;
        _authExpired = false;
        _backoff = _backoffMin;
        if (_flushChunk < _flushChunkMax) {
          _flushChunk = (_flushChunk * 2).clamp(1, _flushChunkMax);
        }
        _emit();
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          // Token gone (signed in elsewhere / expired). Keep queueing; the
          // next login drains it. Never log the user out from here.
          _authExpired = e.statusCode == 401;
          _lastError = e.statusCode == 401
              ? 'Session expired — points are being saved on this phone'
              : e.message;
        } else if (e.statusCode == 413) {
          // Too large for the server: send smaller slices from now on.
          _flushChunk = (_flushChunk ~/ 2).clamp(1, _flushChunkMax);
          _lastError = e.message;
          continue;
        } else if (e.statusCode == 400 || e.statusCode == 422) {
          // The server refused the slice outright. Never drop 200 points for one
          // bad one: split and retry; a single refused point is dropped and counted.
          if (slice.length > 1) {
            _flushChunk = (slice.length ~/ 2).clamp(1, _flushChunkMax);
            _lastError = e.message;
            continue;
          }
          _buffer.removeRange(0, 1);
          await store.removeConfirmed(employeeId, slice);
          _droppedCount++;
          _lastError = 'Server refused a GPS point: ${e.message}';
          continue;
        } else {
          _lastError = e.message;
        }
        _growBackoff();
        _emit();
        return;
      } catch (e) {
        _lastError = e.toString();
        _growBackoff();
        _emit();
        return;
      }
    }
    // Network is known-good: let the heartbeat ride on it so the on/off status
    // keeps pace with the trail.
    if (_active) {
      final n = DateTime.now();
      if (_statusDirty ||
          _lastHeartbeatAt == null ||
          n.difference(_lastHeartbeatAt!) >= _heartbeatMinGap) {
        _lastHeartbeatAt = n;
        unawaited(_sendHeartbeat(tracking: true));
      }
    }
  }

  /// Forgets exactly what the server acknowledged. Accepted and duplicate ids
  /// leave the queue; samples the server can never store are dropped and
  /// counted; anything unacknowledged (should not happen) is retried later.
  Future<void> _applyAcks(List<LocationPing> slice, LocationPingBatchResult r) async {
    final done = <String>{...r.acceptedClientIds, ...r.duplicateClientIds};
    final dropped = <String>{};
    for (final ref in r.rejectedRefs) {
      if (ref.startsWith('#')) {
        final idx = int.tryParse(ref.substring(1));
        if (idx != null && idx >= 0 && idx < slice.length) {
          final id = slice[idx].clientPingId;
          if (id != null) dropped.add(id);
        }
      } else {
        dropped.add(ref);
      }
    }
    final forget = <String>{...done, ...dropped};
    var legacyWithoutId = 0;
    _buffer.removeWhere((p) {
      final id = p.clientPingId;
      if (id == null) {
        // Pre-id pings cannot be matched; treat the uploaded ones as done.
        if (slice.contains(p)) {
          legacyWithoutId++;
          return true;
        }
        return false;
      }
      return forget.contains(id);
    });
    _droppedCount += dropped.length;
    _sentCount += r.saved;
    await store.removeByIds(employeeId, forget, withoutId: legacyWithoutId);
    if (dropped.isNotEmpty) {
      _lastError = '${dropped.length} GPS point(s) refused by the server and dropped';
    }
  }

  void _growBackoff() {
    final next = _backoff * 2;
    _backoff = next > _backoffMax ? _backoffMax : next;
  }

  // ── Heartbeat & config ───────────────────────────────────────────────────

  Future<void> _readBattery() async {
    _lastBatteryReadAt = DateTime.now();
    try {
      _battery = await _batteryPlugin.batteryLevel;
    } catch (_) {
      // Plugin unavailable on this platform — battery stays unknown.
    }
  }

  Future<void> _sendHeartbeat({required bool tracking}) async {
    try {
      bool enabled;
      try {
        enabled = await Geolocator.isLocationServiceEnabled();
      } catch (_) {
        enabled = _locationEnabled;
      }
      _locationEnabled = enabled;
      final perm = await Geolocator.checkPermission();
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      bool? batteryExempt;
      if (!kIsWeb && Platform.isAndroid) {
        try {
          batteryExempt = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
        } catch (_) {}
      }
      final pos = _lastPosition;
      await repo.sendStatus(
        locationEnabled: enabled,
        permissionGranted: granted,
        tracking: tracking,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
        diagnostics: HeartbeatDiagnostics(
          fixAt: pos?.timestamp.toUtc(),
          accuracyMeters: pos?.accuracy,
          pendingPings: _buffer.length,
          lastCaptureAt: _lastCapturedPosition?.timestamp.toUtc(),
          batteryLevel: _battery,
          batteryOptimisationIgnored: batteryExempt,
          backgroundLocationGranted: perm == LocationPermission.always,
          serviceRunning: tracking && serviceHosted,
          appVersion: appVersion,
          poorFixesDiscarded: _poorFixes,
        ),
      );
      _statusDirty = false;
    } catch (_) {
      // Best-effort — the ping queue carries the trail regardless. A status
      // CHANGE that failed to send stays dirty and is retried on the next tick.
    }
  }

  Future<void> _maybeRefreshConfig({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastConfigRefreshAt != null &&
        now.difference(_lastConfigRefreshAt!) < _configRefreshInterval) {
      return;
    }
    _lastConfigRefreshAt = now;
    try {
      final cfg = await ApiClient.instance.get<FieldVisitConfig>(
        '/api/customers/nearby/config',
        parse: (d) => FieldVisitConfig.fromJson(d as Map<String, dynamic>),
      );
      _cfg = TrackingConfig.fromFieldVisit(cfg);
    } catch (_) {
      // Keep whatever we have.
    }
  }

  void _emit() {
    try {
      onSnapshot?.call(snapshot);
    } catch (_) {}
  }
}
