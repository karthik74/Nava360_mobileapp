import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/api_client.dart';
import '../../customers/nearby_customer_models.dart';
import '../location_ping_models.dart';
import '../location_ping_store.dart';
import '../location_repository.dart';

/// Server-tunable capture cadence. Mirrors the tracking fields of
/// `/api/customers/nearby/config`; every value has a compiled-in fallback so
/// tracking never depends on a reachable server.
class TrackingConfig {
  const TrackingConfig({
    this.movingSeconds = 60,
    this.stationarySeconds = 300,
    this.nearCustomerSeconds = 30,
    this.nearCustomerRadiusMeters = 200,
    this.minDisplacementMeters = 25,
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
      movingSeconds: pick('movingSeconds', 60),
      stationarySeconds: pick('stationarySeconds', 300),
      nearCustomerSeconds: pick('nearCustomerSeconds', 30),
      nearCustomerRadiusMeters: pick('nearCustomerRadiusMeters', 200),
      minDisplacementMeters: pick('minDisplacementMeters', 25),
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
///  * subscribes to the OS position stream (and the location on/off stream),
///  * decides which fixes become route pings (time- and distance-based, faster
///    while moving or near a customer, never more than one per [_minCaptureGap]),
///  * persists each ping to the durable queue before anything else,
///  * uploads in chunks with exponential back-off, dropping confirmed pings
///    from the queue by id,
///  * sends the location on/off heartbeat,
///  * self-heals: a silent stream is re-subscribed, a location toggle is
///    reacted to immediately, and the server cadence is re-fetched periodically.
class TrackingEngine {
  TrackingEngine({
    required this.employeeId,
    required this.repo,
    required this.store,
    this.deviceId,
    TrackingConfig? config,
    this.onSnapshot,
    this.onSessionExpired,
  }) : _cfg = config ?? TrackingConfig.fallback;

  final int employeeId;
  final LocationRepository repo;
  final LocationPingStore store;
  final String? deviceId;
  final void Function(TrackingSnapshot snapshot)? onSnapshot;
  /// Fired once when a session has outlived [maxSessionLength] — the employee
  /// forgot to check out. The host should stop the engine and the service.
  final void Function()? onSessionExpired;

  // ── Tunables (compiled-in; cadence itself comes from [TrackingConfig]) ──
  /// Below this speed the device is treated as stationary unless displacement
  /// says otherwise.
  static const double _movingSpeedMps = 1.5;
  /// Never two route pings closer together than this.
  static const Duration _minCaptureGap = Duration(seconds: 15);
  /// Fixes worse than this are not worth a row — the server would reject them.
  static const double _maxCaptureAccuracyMeters = 500;
  /// Upload when the buffer reaches this many pings …
  static const int _flushAtCount = 5;
  /// … or this long after the last successful upload, whichever comes first.
  static const Duration _flushInterval = Duration(seconds: 60);
  /// Largest batch per request — a long offline stretch is drained in slices.
  static const int _flushChunk = 200;
  static const Duration _backoffMin = Duration(seconds: 30);
  static const Duration _backoffMax = Duration(minutes: 10);
  /// A 401 is not a transient network error; wait longer before retrying.
  static const Duration _authBackoff = Duration(minutes: 10);
  static const Duration _heartbeatInterval = Duration(minutes: 3);
  static const Duration _heartbeatMinGap = Duration(seconds: 90);
  /// No fix for this long while location is on = the stream has died; rebuild it.
  static const Duration _streamSilenceLimit = Duration(minutes: 3);
  static const Duration _configRefreshInterval = Duration(minutes: 30);
  /// OS stream cadence. Fine-grained on purpose: the engine decides what to
  /// keep, and frequent fixes are what make displacement-triggered capture
  /// follow a road instead of cutting corners.
  static const Duration _streamInterval = Duration(seconds: 20);
  /// A session this old without a check-out is a forgotten one.
  static const Duration maxSessionLength = Duration(hours: 20);

  // ── Runtime ──
  TrackingConfig _cfg;
  List<({double lat, double lng})> _nearbyCustomerPoints = const [];
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  Position? _lastPosition;
  Position? _lastCapturedPosition;
  DateTime? _lastFixAt;
  DateTime? _lastCaptureAt;
  DateTime? _lastFlushedAt;
  DateTime? _lastFlushAttemptAt;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastConfigRefreshAt;
  DateTime? _startedAt;
  Duration _backoff = _backoffMin;
  bool _authExpired = false;
  bool _locationEnabled = true;
  bool _active = false;
  bool _expiredFired = false;
  String? _lastError;
  int _sentCount = 0;
  int _pingSeq = 0;
  final List<LocationPing> _buffer = [];
  Future<void>? _flushInFlight;
  Future<void>? _resubscribeInFlight;

  bool get active => _active;
  TrackingSnapshot get snapshot => TrackingSnapshot(
        active: _active,
        employeeId: employeeId,
        lastCapturedAt: _lastCaptureAt,
        lastFlushedAt: _lastFlushedAt,
        lastFixAt: _lastFixAt,
        bufferedCount: _buffer.length,
        sentCount: _sentCount,
        lastError: _lastError,
        locationEnabled: _locationEnabled,
        authExpired: _authExpired,
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
    _startedAt = sessionStartedAt ?? DateTime.now();
    _androidForegroundNotification = androidForegroundNotification;

    // Whatever an earlier process left in the durable queue goes first.
    try {
      final persisted = await store.load(employeeId);
      if (persisted.isNotEmpty) {
        _buffer.insertAll(0, persisted);
      }
    } catch (_) {
      // A read failure must not block tracking.
    }

    await _subscribe();
    _serviceSub = Geolocator.getServiceStatusStream().listen(
      _onServiceStatus,
      onError: (_) {},
    );

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
  /// [flushTimeout]) and the server is told tracking is off.
  Future<void> stop({
    bool flush = true,
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
    try {
      await _sendHeartbeat(tracking: false).timeout(const Duration(seconds: 5));
    } catch (_) {}
    _buffer.clear();
    _lastPosition = null;
    _lastCapturedPosition = null;
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

    if (_lastHeartbeatAt == null ||
        now.difference(_lastHeartbeatAt!) >= _heartbeatInterval) {
      _lastHeartbeatAt = now;
      unawaited(_sendHeartbeat(tracking: true));
    }

    // Watchdog: location is on but the stream has gone quiet — rebuild it.
    final lastFix = _lastFixAt ?? _startedAt ?? now;
    if (_locationEnabled && now.difference(lastFix) > _streamSilenceLimit) {
      _lastFixAt = now; // don't re-trigger every tick while recovering
      unawaited(_resubscribe());
      unawaited(_primeWithCurrentPosition());
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
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: _streamInterval,
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
        activityType: ActivityType.other,
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
    _lastFixAt = DateTime.now();
    _locationEnabled = true;
    // Ignore wild fixes entirely (a cell-tower guess 2 km wide tells us
    // nothing); everything else is kept and the server grades it.
    if (p.accuracy > _maxCaptureAccuracyMeters) return;
    _lastPosition = p;
    _maybeCapture();
  }

  void _onStreamError(Object e) {
    _lastError = e.toString();
    if (e is LocationServiceDisabledException) {
      _locationEnabled = false;
      _lastHeartbeatAt = DateTime.now();
      unawaited(_sendHeartbeat(tracking: true));
    }
    _emit();
  }

  void _onServiceStatus(ServiceStatus status) {
    final enabled = status == ServiceStatus.enabled;
    if (enabled == _locationEnabled) return;
    _locationEnabled = enabled;
    // Tell HR right away — this is the "location turned off" signal.
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

  bool _isMoving(Position p) {
    if (p.speed > _movingSpeedMps) return true;
    final last = _lastCapturedPosition;
    if (last == null) return false;
    // Speed is often 0 on a phone in a pocket; displacement since the last
    // captured point is the second opinion.
    final d = Geolocator.distanceBetween(
        last.latitude, last.longitude, p.latitude, p.longitude);
    return d >= _cfg.minDisplacementMeters * 2;
  }

  Duration _intervalFor(Position p) {
    if (_nearCustomer(p)) return Duration(seconds: _cfg.nearCustomerSeconds);
    if (_isMoving(p)) return Duration(seconds: _cfg.movingSeconds);
    return Duration(seconds: _cfg.stationarySeconds);
  }

  void _maybeCapture() {
    final p = _lastPosition;
    if (!_active || p == null) return;
    final now = DateTime.now();

    if (_lastCaptureAt != null &&
        now.difference(_lastCaptureAt!) < _minCaptureGap) {
      return;
    }

    final dueByTime = _lastCaptureAt == null ||
        now.difference(_lastCaptureAt!) >= _intervalFor(p);

    var movedFar = _lastCapturedPosition == null;
    if (!movedFar) {
      final d = Geolocator.distanceBetween(
          _lastCapturedPosition!.latitude,
          _lastCapturedPosition!.longitude,
          p.latitude,
          p.longitude);
      // The jump has to clear the configured displacement AND the fix's own
      // error radius, so a noisy fix while parked isn't travel.
      final threshold = math.max(_cfg.minDisplacementMeters.toDouble(),
          math.min(p.accuracy, _maxCaptureAccuracyMeters));
      movedFar = d >= threshold;
    }

    if (!dueByTime && !movedFar) return;
    _capture(p);
  }

  void _capture(Position p) {
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
    );
    _buffer.add(ping);
    // Durable first: an offline ping is never lost if the OS kills the process
    // before it can be uploaded.
    unawaited(store.append(employeeId, [ping]).catchError((_) {}));
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
        final saved = await repo.uploadBatch(
          LocationPingBatch(employeeId: employeeId, pings: slice),
        );
        _buffer.removeRange(0, slice.length);
        await store.removeConfirmed(employeeId, slice);
        _sentCount += saved;
        _lastFlushedAt = DateTime.now();
        _lastError = null;
        _authExpired = false;
        _backoff = _backoffMin;
        _emit();
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          // Token gone (signed in elsewhere / expired). Keep queueing; the
          // next login drains it. Never log the user out from here.
          _authExpired = e.statusCode == 401;
          _lastError = e.statusCode == 401
              ? 'Session expired — pings are being saved on the device'
              : e.message;
        } else if (e.statusCode == 400) {
          // The server refused this slice outright (e.g. the payload shape). It
          // will refuse it forever; drop it rather than wedge the queue.
          _buffer.removeRange(0, slice.length);
          await store.removeConfirmed(employeeId, slice);
          _lastError = e.message;
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
      if (_lastHeartbeatAt == null ||
          n.difference(_lastHeartbeatAt!) >= _heartbeatMinGap) {
        _lastHeartbeatAt = n;
        unawaited(_sendHeartbeat(tracking: true));
      }
    }
  }

  void _growBackoff() {
    final next = _backoff * 2;
    _backoff = next > _backoffMax ? _backoffMax : next;
  }

  // ── Heartbeat & config ───────────────────────────────────────────────────

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
      await repo.sendStatus(
        locationEnabled: enabled,
        permissionGranted: granted,
        tracking: tracking,
        latitude: _lastPosition?.latitude,
        longitude: _lastPosition?.longitude,
      );
    } catch (_) {
      // Best-effort — the ping queue carries the trail regardless.
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
