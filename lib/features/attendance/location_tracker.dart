import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

import 'location_ping_models.dart';
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
/// Cadence:
///   - Default                  → 5 minutes
///   - Moving fast (>3 m/s)     → 2 minutes
///   - Stopped (<0.5 m/s)       → 30 minutes
///   - Distance-triggered       → 200 m (Geolocator stream filter)
///
/// The tracker self-flushes when its buffer reaches [_flushAtCount] or
/// [_flushIntervalSeconds] have passed since the last successful upload.
class LocationTracker extends StateNotifier<LocationTrackerState> {
  LocationTracker(this._repo) : super(LocationTrackerState.idle);

  final LocationRepository _repo;

  // ---- Tunables ----
  static const Duration _intervalDefault = Duration(minutes: 5);
  static const Duration _intervalMoving = Duration(minutes: 2);
  static const Duration _intervalStopped = Duration(minutes: 30);
  static const double _movingThresholdMps = 3.0;
  static const double _stoppedThresholdMps = 0.5;
  static const int _distanceFilterMeters = 200;
  static const int _flushAtCount = 5;
  static const int _flushIntervalSeconds = 120;
  static const Duration _tick = Duration(seconds: 30);

  // ---- Persistent key (so we can resume after a process restart) ----
  static const _kActiveEmployee = 'tracker.activeEmployeeId';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ---- Runtime ----
  StreamSubscription<Position>? _streamSub;
  Timer? _ticker;
  Position? _lastPosition;
  DateTime? _lastCaptureAt;
  final List<LocationPing> _buffer = [];
  Future<void>? _flushInFlight;

  /// Start (or noop if already running for the same employee).
  Future<void> start(int employeeId) async {
    if (state.active && state.employeeId == employeeId) return;
    await stop(flushBuffer: false); // reset if a different employee was active

    if (!await _ensurePermissionAndService()) return;

    await _storage.write(key: _kActiveEmployee, value: '$employeeId');

    final settings = _platformSettings();
    _streamSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: _onStreamError);
    _ticker = Timer.periodic(_tick, (_) => _maybeCapture());

    state = state.copyWith(
      active: true,
      employeeId: employeeId,
      bufferedCount: 0,
      sentCount: 0,
      clearError: true,
    );

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
    _streamSub = null;
    _ticker = null;
    _lastPosition = null;
    _lastCaptureAt = null;

    if (flushBuffer && _buffer.isNotEmpty && state.employeeId != null) {
      await _flush();
    } else {
      _buffer.clear();
    }

    await _storage.delete(key: _kActiveEmployee);

    state = LocationTrackerState.idle;
  }

  /// On app start: if a tracking session was persisted, reattach to it.
  Future<void> restoreIfActive() async {
    final raw = await _storage.read(key: _kActiveEmployee);
    if (raw == null) return;
    final empId = int.tryParse(raw);
    if (empId == null) return;
    await start(empId);
  }

  // -------------------- internals --------------------

  Duration _currentInterval() {
    final speed = _lastPosition?.speed ?? 0;
    if (speed > _movingThresholdMps) return _intervalMoving;
    if (speed < _stoppedThresholdMps) return _intervalStopped;
    return _intervalDefault;
  }

  void _onPosition(Position p) {
    _lastPosition = p;
    // The OS already filtered by distance, so a stream event is "interesting".
    // Still honor the minimum cadence to avoid runaway sampling in noisy areas.
    _maybeCapture(distanceTriggered: true);
  }

  void _onStreamError(Object e) {
    state = state.copyWith(lastError: e.toString());
  }

  void _maybeCapture({bool distanceTriggered = false}) {
    if (!state.active || _lastPosition == null) return;

    final now = DateTime.now();
    final interval = _currentInterval();
    final dueByTime = _lastCaptureAt == null ||
        now.difference(_lastCaptureAt!) >= interval;

    if (!distanceTriggered && !dueByTime) return;

    // Even on a distance event, if we just captured <30s ago, skip — that's noise.
    if (distanceTriggered &&
        _lastCaptureAt != null &&
        now.difference(_lastCaptureAt!) < const Duration(seconds: 30)) {
      return;
    }

    _capture(_lastPosition!);
    _maybeAutoFlush();
  }

  void _capture(Position p) {
    final ping = LocationPing(
      recordedAt: p.timestamp.toUtc(),
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMeters: p.accuracy,
      speedMps: p.speed,
    );
    _buffer.add(ping);
    _lastCaptureAt = DateTime.now();
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
      _flushInFlight ??= _flush().whenComplete(() => _flushInFlight = null);
    }
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty || state.employeeId == null) return;
    final pending = List<LocationPing>.from(_buffer);
    try {
      final saved = await _repo.uploadBatch(
        LocationPingBatch(employeeId: state.employeeId!, pings: pending),
      );
      _buffer.removeRange(0, pending.length);
      state = state.copyWith(
        lastFlushedAt: DateTime.now(),
        bufferedCount: _buffer.length,
        sentCount: state.sentCount + saved,
        clearError: true,
      );
    } catch (e) {
      // Keep buffer so the next tick retries.
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
    return true;
  }

  /// Platform-specific stream settings. On Android we enable a foreground notification
  /// so the OS keeps location updates flowing while the app isn't in front.
  LocationSettings _platformSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'HRMS attendance',
          notificationText: 'Recording your location while you are checked in',
          enableWakeLock: true,
          notificationChannelName: 'Attendance tracking',
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
        activityType: ActivityType.other,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}

final locationTrackerProvider =
    StateNotifierProvider<LocationTracker, LocationTrackerState>(
  (ref) => LocationTracker(ref.watch(locationRepositoryProvider)),
);
