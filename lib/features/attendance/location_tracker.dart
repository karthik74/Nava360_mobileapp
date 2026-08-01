import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/branding.dart';
import '../auth/biometric/device_info_service.dart';
import 'location_ping_models.dart';
import 'location_ping_store.dart';
import 'location_repository.dart';

/// Public state of the tracker, exposed via Riverpod.
class LocationTrackerState {
  final bool active;
  final int? employeeId;
  final DateTime? lastCapturedAt;
  final DateTime? lastFlushedAt;
  final int bufferedCount;
  final int sentCount;
  final String? lastError;

  const LocationTrackerState({
    required this.active,
    required this.employeeId,
    required this.lastCapturedAt,
    required this.lastFlushedAt,
    required this.bufferedCount,
    required this.sentCount,
    required this.lastError,
  });

  static const idle = LocationTrackerState(
    active: false,
    employeeId: null,
    lastCapturedAt: null,
    lastFlushedAt: null,
    bufferedCount: 0,
    sentCount: 0,
    lastError: null,
  );

  LocationTrackerState copyWith({
    bool? active,
    int? employeeId,
    DateTime? lastCapturedAt,
    DateTime? lastFlushedAt,
    int? bufferedCount,
    int? sentCount,
    String? lastError,
    bool clearError = false,
  }) {
    return LocationTrackerState(
      active: active ?? this.active,
      employeeId: employeeId ?? this.employeeId,
      lastCapturedAt: lastCapturedAt ?? this.lastCapturedAt,
      lastFlushedAt: lastFlushedAt ?? this.lastFlushedAt,
      bufferedCount: bufferedCount ?? this.bufferedCount,
      sentCount: sentCount ?? this.sentCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Captures GPS samples on an adaptive schedule while the employee is "punched in"
/// and posts them to the server in batches.
///
/// Cadence (tuned for an accurate travel path while limiting battery use):
///   - Default                  → 5 minutes
///   - Moving fast (>3 m/s)     → 1 minute
///   - Stopped (<0.5 m/s)       → 30 minutes
///   - Distance-triggered       → 75 m moved
///   - Hard cap                 → at most one ping per 15 s
///
/// The tracker self-flushes when its buffer reaches [_flushAtCount] or
/// [_flushIntervalSeconds] have passed since the last successful upload.
class LocationTracker extends StateNotifier<LocationTrackerState>
    with WidgetsBindingObserver {
  LocationTracker(this._repo) : super(LocationTrackerState.idle) {
    // Observe app lifecycle so we can self-heal (resume a killed session) and
    // drain the offline queue the moment the app returns to the foreground.
    WidgetsBinding.instance.addObserver(this);
  }

  final LocationRepository _repo;

  /// Durable offline queue — every captured ping is persisted here and removed
  /// only once the server confirms it, so the trail survives app restarts / no
  /// internet and syncs when connectivity returns.
  final LocationPingStore _store = LocationPingStore.instance;

  // ---- Tunables ----
  // Compiled-in fallbacks. The live values come from the server
  // (/api/customers/nearby/config) via [applyConfig], so cadence can be retuned
  // for a company without an app release.
  static const Duration _intervalDefault = Duration(minutes: 5);
  static const Duration _intervalMoving = Duration(minutes: 1);
  static const Duration _intervalStopped = Duration(minutes: 30);
  static const double _movingThresholdMps = 3.0;
  static const double _stoppedThresholdMps = 0.5;
  static const int _distanceFilterMeters = 75;
  static const int _flushAtCount = 5;
  static const int _flushIntervalSeconds = 120;
  static const Duration _tick = Duration(seconds: 15);
  /// Minimum gap between two captured route pings (burst guard).
  static const Duration _minCaptureGap = Duration(seconds: 15);
  // How often the foreground timer fires a location-on/off heartbeat.
  static const Duration _statusInterval = Duration(minutes: 3);
  // Minimum gap between heartbeats (the location stream also triggers them, so they
  // keep flowing in the background where Dart timers are paused).
  static const Duration _statusMinGap = Duration(seconds: 90);
  // OS location-update interval. Drives the stream on a timer (not just on movement)
  // so heartbeats keep flowing in the background even when the device is stationary.
  static const Duration _streamInterval = Duration(minutes: 1);

  // ---- Persistent key (so we can resume after a process restart) ----
  static const _kActiveEmployee = 'tracker.activeEmployeeId';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ---- Runtime ----
  StreamSubscription<Position>? _streamSub;
  Timer? _ticker;
  Timer? _statusTicker;
  Position? _lastPosition;
  Position? _lastCapturedPosition;
  DateTime? _lastCaptureAt;
  DateTime? _lastStatusSentAt;
  final List<LocationPing> _buffer = [];
  Future<void>? _flushInFlight;

  /// Server-tuned cadence; falls back to the constants above until it arrives.
  Duration _cfgMoving = _intervalMoving;
  Duration _cfgStopped = _intervalStopped;
  Duration _cfgNearCustomer = const Duration(seconds: 30);
  int _cfgDistanceFilterMeters = _distanceFilterMeters;
  double _cfgNearCustomerRadiusMeters = 200;

  /// Coordinates of nearby customers, refreshed by the Nearby Customers screen.
  /// Used only to decide when to sample faster — never uploaded anywhere.
  List<({double lat, double lng})> _nearbyCustomerPoints = const [];

  /// Stable id for this device, attached to every fix so the backend can tell
  /// two phones sharing one login apart.
  String? _deviceId;

  /// Monotonic counter behind the per-sample idempotency key.
  int _pingSeq = 0;

  /// Start (or noop if already running for the same employee).
  Future<void> start(int employeeId) async {
    if (state.active && state.employeeId == employeeId) return;
    await stop(flushBuffer: false); // reset if a different employee was active

    if (!await _ensurePermissionAndService()) return;

    await _storage.write(key: _kActiveEmployee, value: '$employeeId');

    // Stamp every fix with this install's device id. Reuses the same persisted
    // UUID as biometric login — no hardware identifier, no PII — so the backend
    // can tell two phones on one login apart without learning anything new.
    try {
      _deviceId = (await DeviceInfoService().resolve()).deviceId;
    } catch (_) {
      // Optional context; tracking proceeds without it.
    }

    final settings = _platformSettings();
    _streamSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: _onStreamError);
    _ticker = Timer.periodic(_tick, (_) => _maybeCapture());
    // Foreground heartbeat. The location stream also fires heartbeats (see
    // _onPosition) so they keep flowing while the app is backgrounded. Also
    // attempt a flush here so queued pings sync even when the device is
    // stationary (no new captures) after connectivity is restored.
    _statusTicker = Timer.periodic(_statusInterval, (_) {
      _maybeSendStatus(tracking: true);
      _maybeAutoFlush();
    });

    state = state.copyWith(
      active: true,
      employeeId: employeeId,
      bufferedCount: 0,
      sentCount: 0,
      clearError: true,
    );
    _lastStatusSentAt = DateTime.now();
    unawaited(_sendStatus(tracking: true)); // report ON immediately

    // Re-load any pings persisted but not yet uploaded (a previous session that
    // ended offline, or an app kill) so they sync as soon as we're online again.
    try {
      final persisted = await _store.load(employeeId);
      if (persisted.isNotEmpty) {
        _buffer.insertAll(0, persisted); // oldest first
        state = state.copyWith(bufferedCount: _buffer.length);
        _maybeAutoFlush();
      }
    } catch (_) {
      // A read failure must not block tracking.
    }

    // Try to capture an immediate baseline sample so the user sees activity right away.
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _onPosition(pos);
    } catch (_) {
      // Initial fix can fail (cold start, indoors); the stream will catch up.
    }
  }

  /// Stop tracking. Flushes any buffered pings unless [flushBuffer] is false.
  Future<void> stop({bool flushBuffer = true}) async {
    await _streamSub?.cancel();
    _ticker?.cancel();
    _statusTicker?.cancel();
    _streamSub = null;
    _ticker = null;
    _statusTicker = null;

    // Report that tracking has stopped (so HR sees "checked out", not a stale state).
    await _sendStatus(tracking: false);

    _lastPosition = null;
    _lastCapturedPosition = null;
    _lastCaptureAt = null;
    _lastStatusSentAt = null;

    if (flushBuffer && _buffer.isNotEmpty && state.employeeId != null) {
      await _flush();
    } else {
      _buffer.clear();
    }

    await _storage.delete(key: _kActiveEmployee);

    state = LocationTrackerState.idle;
  }

  /// Best-effort heartbeat reporting whether device location/GPS is on right now.
  Future<void> _sendStatus({required bool tracking}) async {
    if (state.employeeId == null) return;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      await _repo.sendStatus(
        locationEnabled: enabled,
        permissionGranted: granted,
        tracking: tracking,
        latitude: _lastPosition?.latitude,
        longitude: _lastPosition?.longitude,
      );
    } catch (_) {
      // Best-effort — ignore network / permission errors.
    }
  }

  /// On app start: if a tracking session was persisted, reattach to it.
  Future<void> restoreIfActive() async {
    final raw = await _storage.read(key: _kActiveEmployee);
    if (raw == null) return;
    final empId = int.tryParse(raw);
    if (empId == null) return;
    await start(empId);
  }

  /// Uploads any pings left in the durable offline queue — e.g. captured while
  /// the employee had no internet and then checked out, so no tracking session
  /// is active to drain them. Call once on app start / when back online. The
  /// currently-tracked employee (if any) is skipped, since [start]/[_flush]
  /// already own that queue and draining it here would race.
  Future<void> syncPendingPings() async {
    try {
      final grouped = await _store.loadGrouped();
      for (final entry in grouped.entries) {
        final empId = entry.key;
        final pings = entry.value;
        if (pings.isEmpty || empId == state.employeeId) continue;
        try {
          await _repo.uploadBatch(
            LocationPingBatch(employeeId: empId, pings: pings),
          );
          await _store.removeOldest(empId, pings.length);
        } catch (_) {
          // Still offline — leave them queued for the next attempt.
        }
      }
    } catch (_) {
      // Never let a queue-drain failure surface at startup.
    }
  }

  /// When the app returns to the foreground: drain the offline queue promptly
  /// and, if a session should be running but was killed by the OS, resume it —
  /// so no ping sits unsynced and tracking self-heals without a manual re-start.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    if (state.active) {
      _maybeAutoFlush(); // push the active employee's buffered/queued pings
    } else {
      unawaited(restoreIfActive()); // a killed session? bring it back
    }
    unawaited(syncPendingPings()); // leftover queues from prior sessions
  }

  // -------------------- internals --------------------

  /// Applies server-side tuning. Safe to call repeatedly; takes effect on the
  /// next capture decision.
  void applyConfig({
    int? movingSeconds,
    int? stationarySeconds,
    int? nearCustomerSeconds,
    int? nearCustomerRadiusMeters,
    int? minDisplacementMeters,
  }) {
    if (movingSeconds != null && movingSeconds > 0) {
      _cfgMoving = Duration(seconds: movingSeconds);
    }
    if (stationarySeconds != null && stationarySeconds > 0) {
      _cfgStopped = Duration(seconds: stationarySeconds);
    }
    if (nearCustomerSeconds != null && nearCustomerSeconds > 0) {
      _cfgNearCustomer = Duration(seconds: nearCustomerSeconds);
    }
    if (nearCustomerRadiusMeters != null && nearCustomerRadiusMeters > 0) {
      _cfgNearCustomerRadiusMeters = nearCustomerRadiusMeters.toDouble();
    }
    if (minDisplacementMeters != null && minDisplacementMeters > 0) {
      _cfgDistanceFilterMeters = minDisplacementMeters;
    }
  }

  /// Tells the tracker where the employee's nearby customers are, so it can
  /// sample faster when close to one. Coordinates stay on the device.
  void setNearbyCustomerPoints(List<({double lat, double lng})> points) {
    _nearbyCustomerPoints = points;
  }

  /// True when the last fix is within the "near a customer" radius.
  ///
  /// This is what makes short visits detectable at all: at the everyday
  /// stationary cadence a two-minute stop produces at most one fix, and one fix
  /// is not evidence of a visit. Near a customer we sample often enough for the
  /// backend to see an arrival, a stay and a departure.
  bool _nearCustomer() {
    final p = _lastPosition;
    if (p == null || _nearbyCustomerPoints.isEmpty) return false;
    for (final c in _nearbyCustomerPoints) {
      final d = Geolocator.distanceBetween(p.latitude, p.longitude, c.lat, c.lng);
      if (d <= _cfgNearCustomerRadiusMeters) return true;
    }
    return false;
  }

  Duration _currentInterval() {
    if (_nearCustomer()) return _cfgNearCustomer;
    final speed = _lastPosition?.speed ?? 0;
    if (speed > _movingThresholdMps) return _cfgMoving;
    if (speed < _stoppedThresholdMps) return _cfgStopped;
    return _intervalDefault;
  }

  void _onPosition(Position p) {
    _lastPosition = p;
    // Stream now fires on a time interval (so it keeps flowing in the background
    // even when stationary). Capture a route ping only when enough distance/time
    // has elapsed; always send a location-ON heartbeat (throttled).
    _maybeCapture();
    _maybeSendStatus(tracking: true);
  }

  /// Sends a heartbeat at most once per [_statusMinGap].
  void _maybeSendStatus({required bool tracking}) {
    final now = DateTime.now();
    if (_lastStatusSentAt != null &&
        now.difference(_lastStatusSentAt!) < _statusMinGap) {
      return;
    }
    _lastStatusSentAt = now;
    unawaited(_sendStatus(tracking: tracking));
  }

  void _onStreamError(Object e) {
    state = state.copyWith(lastError: e.toString());
  }

  void _maybeCapture() {
    if (!state.active || _lastPosition == null) return;
    final p = _lastPosition!;
    final now = DateTime.now();

    final interval = _currentInterval();
    final dueByTime =
        _lastCaptureAt == null || now.difference(_lastCaptureAt!) >= interval;
    final movedFar = _lastCapturedPosition == null ||
        Geolocator.distanceBetween(
              _lastCapturedPosition!.latitude,
              _lastCapturedPosition!.longitude,
              p.latitude,
              p.longitude,
            ) >=
            _cfgDistanceFilterMeters;

    if (!dueByTime && !movedFar) return;
    // Avoid bursts — at most one ping per _minCaptureGap.
    if (_lastCaptureAt != null &&
        now.difference(_lastCaptureAt!) < _minCaptureGap) {
      return;
    }

    _capture(p);
    _maybeAutoFlush();
  }

  void _capture(Position p) {
    final empId = state.employeeId;
    final ping = LocationPing(
      // Idempotency key: employee + capture time + a counter. Survives in the
      // durable queue, so a batch retried after a timeout is stored once and
      // cannot be counted twice inside a visit.
      clientPingId: '$empId-${p.timestamp.toUtc().millisecondsSinceEpoch}-${_pingSeq++}',
      recordedAt: p.timestamp.toUtc(),
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMeters: p.accuracy,
      speedMps: p.speed,
      headingDegrees: p.heading,
      deviceId: _deviceId,
      // Android reports spoofed positions; iOS has no equivalent signal, so
      // null there means "unknown", not "genuine".
      mockLocation: p.isMocked,
    );
    _buffer.add(ping);
    // Persist immediately so an offline ping is never lost if the OS kills the
    // app before it can be uploaded (this is what fills the gaps in the trail).
    if (empId != null) {
      unawaited(_store.append(empId, [ping]));
    }
    _lastCaptureAt = DateTime.now();
    _lastCapturedPosition = p;
    state = state.copyWith(
      lastCapturedAt: _lastCaptureAt,
      bufferedCount: _buffer.length,
    );
  }

  void _maybeAutoFlush() {
    final byCount = _buffer.length >= _flushAtCount;
    final byAge = state.lastFlushedAt == null ||
        DateTime.now().difference(state.lastFlushedAt!) >=
            const Duration(seconds: _flushIntervalSeconds);
    if (byCount || (byAge && _buffer.isNotEmpty)) {
      _flushInFlight ??=
          _flush(heartbeat: true).whenComplete(() => _flushInFlight = null);
    }
  }

  /// Uploads the buffered pings. When [heartbeat] is true, a location heartbeat
  /// is piggybacked onto a successful upload (see below) — pass false for the
  /// final checkout flush, which has already reported tracking:false.
  Future<void> _flush({bool heartbeat = false}) async {
    if (_buffer.isEmpty || state.employeeId == null) return;
    final empId = state.employeeId!;
    final pending = List<LocationPing>.from(_buffer);
    try {
      final saved = await _repo.uploadBatch(
        LocationPingBatch(employeeId: empId, pings: pending),
      );
      _buffer.removeRange(0, pending.length);
      // Drop the confirmed pings from the durable queue (FIFO — pings captured
      // during this in-flight upload stay queued for the next flush).
      await _store.removeOldest(empId, pending.length);
      state = state.copyWith(
        lastFlushedAt: DateTime.now(),
        bufferedCount: _buffer.length,
        sentCount: state.sentCount + saved,
        clearError: true,
      );
      // Piggyback a status heartbeat on the just-confirmed connection. Heartbeats
      // are otherwise best-effort/fire-and-forget with no retry queue, so a run of
      // failures (poor signal, or the OS deferring background requests) freezes the
      // server's status at an old fix while the durable ping queue still carries the
      // trail forward. Sending here — right after a successful upload, when the
      // network is known-good — keeps the on/off status (and its position) advancing
      // in step with the trail. Guarded to the active session so it never overrides
      // the tracking:false we send at checkout.
      if (heartbeat && state.active) {
        _maybeSendStatus(tracking: true);
      }
    } catch (e) {
      // Keep buffer AND the durable queue so the next tick / next session retries.
      state = state.copyWith(lastError: e.toString());
      if (kDebugMode) debugPrint('Location flush failed: $e');
    }
  }

  Future<bool> _ensurePermissionAndService() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      state = state.copyWith(lastError: 'Location services are disabled.');
      return false;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      state = state.copyWith(lastError: 'Location permission denied.');
      return false;
    }

    // iOS (App Store): "While Using the App" is enough — tracking runs while
    // the app is in the foreground. Never escalate to Always or bounce the user
    // to Settings (rejected under guideline 5.1.1).
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    }

    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }

    if (perm != LocationPermission.always) {
      state = state.copyWith(
        lastError:
            'Background tracking needs Location set to "Allow all the time".',
      );
      await Geolocator.openAppSettings();
      return false;
    }

    // Best-effort: ask the OS to exempt the app from battery optimisation so the
    // foreground tracking service isn't killed/dozed — the single biggest lever
    // for keeping GPS capture (and therefore pings) alive in the background.
    await _requestBatteryExemption();

    return true;
  }

  /// Prompts (once) to disable battery optimisation for this app on Android.
  /// Never blocks tracking — a denied/failed request just means the OS may kill
  /// the service more aggressively; the durable offline queue still protects
  /// already-captured pings.
  Future<void> _requestBatteryExemption() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Permission unavailable on this OS/OEM — ignore.
    }
  }

  /// Platform-specific stream settings. We use a TIME interval (not a distance
  /// filter) so the OS delivers updates on a schedule — keeping the foreground
  /// service active and the on/off heartbeat flowing even when the device is
  /// stationary in the background. Route pings are de-duplicated by distance in
  /// [_maybeCapture], so a 0 distance filter doesn't flood the server.
  LocationSettings _platformSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: _streamInterval,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: '${Branding.current.productName} attendance',
          notificationText: 'Recording your location while you are checked in',
          enableWakeLock: true,
          notificationChannelName: 'Attendance tracking',
        ),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamSub?.cancel();
    _ticker?.cancel();
    _statusTicker?.cancel();
    super.dispose();
  }
}

final locationTrackerProvider =
    StateNotifierProvider<LocationTracker, LocationTrackerState>(
  (ref) => LocationTracker(ref.watch(locationRepositoryProvider)),
);
