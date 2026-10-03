import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import '../../core/branding.dart';
import '../auth/biometric/device_info_service.dart';
import '../customers/nearby_customer_models.dart';
import 'location_ping_models.dart';
import 'location_ping_store.dart';
import 'location_repository.dart';
import 'tracking/tracking_engine.dart';
import 'tracking/tracking_task.dart';

/// Public state of the tracker, exposed via Riverpod.
class LocationTrackerState {
  final bool active;
  final int? employeeId;
  final DateTime? lastCapturedAt;
  final DateTime? lastFlushedAt;
  final int bufferedCount;
  final int sentCount;
  final String? lastError;
  /// Device location services are currently on (as last reported).
  final bool locationEnabled;
  /// The background service holds the session (Android) rather than this process.
  final bool backgroundService;

  const LocationTrackerState({
    required this.active,
    required this.employeeId,
    required this.lastCapturedAt,
    required this.lastFlushedAt,
    required this.bufferedCount,
    required this.sentCount,
    required this.lastError,
    this.locationEnabled = true,
    this.backgroundService = false,
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
    bool? locationEnabled,
    bool? backgroundService,
  }) {
    return LocationTrackerState(
      active: active ?? this.active,
      employeeId: employeeId ?? this.employeeId,
      lastCapturedAt: lastCapturedAt ?? this.lastCapturedAt,
      lastFlushedAt: lastFlushedAt ?? this.lastFlushedAt,
      bufferedCount: bufferedCount ?? this.bufferedCount,
      sentCount: sentCount ?? this.sentCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
      locationEnabled: locationEnabled ?? this.locationEnabled,
      backgroundService: backgroundService ?? this.backgroundService,
    );
  }

  LocationTrackerState fromSnapshot(TrackingSnapshot s) => copyWith(
        active: s.active,
        employeeId: s.employeeId,
        lastCapturedAt: s.lastCapturedAt,
        lastFlushedAt: s.lastFlushedAt,
        bufferedCount: s.bufferedCount,
        sentCount: s.sentCount,
        lastError: s.lastError,
        clearError: s.lastError == null,
        locationEnabled: s.locationEnabled,
      );
}

/// Controls GPS tracking for the "punched in" employee.
///
/// On Android the capture loop runs in a native foreground service with its
/// own Dart isolate (`tracking/tracking_task.dart`), so it keeps recording when
/// the app is swiped away or killed by the launcher and comes back by itself
/// after a reboot. This class only starts/stops that service, relays commands
/// to it and mirrors its snapshots into Riverpod state.
///
/// On iOS (and if the service ever fails to start on Android) the same
/// [TrackingEngine] runs in-process as a fallback.
class LocationTracker extends StateNotifier<LocationTrackerState>
    with WidgetsBindingObserver {
  LocationTracker(this._repo) : super(LocationTrackerState.idle) {
    WidgetsBinding.instance.addObserver(this);
    if (_useService) {
      FlutterForegroundTask.addTaskDataCallback(_onServiceData);
    }
  }

  final LocationRepository _repo;
  final LocationPingStore _store = LocationPingStore.instance;

  static bool get _useService =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // Persistent key: which employee's session is open (also read by the
  // sign-out guard path and kept for compatibility with older builds).
  static const _kActiveEmployee = 'tracker.activeEmployeeId';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// In-process engine (iOS, or Android fallback).
  TrackingEngine? _localEngine;
  Timer? _localTicker;
  Completer<void>? _stopAck;
  bool _serviceInitialised = false;
  TrackingConfig _cfg = TrackingConfig.fallback;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Start (or noop if already running for the same employee).
  Future<void> start(int employeeId) async {
    if (state.active && state.employeeId == employeeId) return;
    await stop(flushBuffer: false); // reset if a different employee was active

    if (!await _ensurePermissionAndService()) return;

    await _storage.write(key: _kActiveEmployee, value: '$employeeId');

    String? deviceId;
    try {
      deviceId = (await DeviceInfoService().resolve()).deviceId;
    } catch (_) {
      // Optional context; tracking proceeds without it.
    }

    // Best-effort server cadence, bounded so a slow network can't delay check-in.
    await _loadConfig().timeout(const Duration(seconds: 4), onTimeout: () {});

    state = state.copyWith(
      active: true,
      employeeId: employeeId,
      bufferedCount: 0,
      sentCount: 0,
      clearError: true,
      backgroundService: false,
    );

    if (_useService) {
      final ok = await _startService(employeeId, deviceId);
      if (ok) {
        state = state.copyWith(backgroundService: true);
        return;
      }
      // Fall back to in-process tracking so the check-in still goes ahead.
    }
    await _startLocal(employeeId, deviceId);
  }

  /// Stop tracking. Flushes any buffered pings unless [flushBuffer] is false.
  Future<void> stop({bool flushBuffer = true}) async {
    final wasActive = state.active;
    if (_useService && (wasActive || await FlutterForegroundTask.isRunningService)) {
      await _stopService(flush: flushBuffer);
    }
    if (_localEngine != null) {
      _localTicker?.cancel();
      _localTicker = null;
      final e = _localEngine!;
      _localEngine = null;
      try {
        await e.stop(flush: flushBuffer);
      } catch (_) {}
    }
    await _storage.delete(key: _kActiveEmployee);
    state = LocationTrackerState.idle;
  }

  /// On app start: if a tracking session was persisted, reattach to it (the
  /// service may well still be running) or restart it.
  Future<void> restoreIfActive() async {
    final raw = await _storage.read(key: _kActiveEmployee);
    final empId = raw == null ? null : int.tryParse(raw);

    if (_useService) {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        final serviceEmp =
            await FlutterForegroundTask.getData<int>(key: TrackingKeys.employeeId);
        if (serviceEmp == null) {
          // Orphaned service (checked out, but the stop never completed).
          await FlutterForegroundTask.stopService();
        } else {
          _initService();
          state = state.copyWith(
            active: true,
            employeeId: serviceEmp,
            backgroundService: true,
            clearError: true,
          );
          FlutterForegroundTask.sendDataToTask(TrackingMsg.encode(TrackingMsg.cmdSnapshot));
          FlutterForegroundTask.sendDataToTask(TrackingMsg.encode(TrackingMsg.cmdFlush));
          if (empId == null) {
            await _storage.write(key: _kActiveEmployee, value: '$serviceEmp');
          }
          return;
        }
      }
    }
    if (empId == null) return;
    await start(empId);
  }

  /// Uploads any pings left in the durable offline queue by an earlier session
  /// (checked out offline, app killed before the final upload). The employee
  /// whose session is running is skipped — the engine owns that queue.
  Future<void> syncPendingPings() async {
    try {
      await _store.purgeStale();
      final grouped = await _store.loadGrouped();
      for (final entry in grouped.entries) {
        final empId = entry.key;
        final pings = entry.value;
        if (pings.isEmpty || (state.active && empId == state.employeeId)) continue;
        for (var i = 0; i < pings.length; i += 200) {
          final slice = pings.sublist(i, (i + 200).clamp(0, pings.length));
          try {
            await _repo.uploadBatch(LocationPingBatch(employeeId: empId, pings: slice));
            await _store.removeConfirmed(empId, slice);
          } on ApiException catch (e) {
            // Not ours to upload with this login (400/403) or offline: leave
            // them for the owner's next login; stale ones age out above.
            if (e.statusCode == 401) return;
            break;
          } catch (_) {
            break; // offline — next time
          }
        }
      }
    } catch (_) {
      // Never let a queue-drain failure surface at startup.
    }
  }

  /// When the app returns to the foreground: nudge an upload and, if a session
  /// should be running but isn't, bring it back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    if (state.active) {
      if (state.backgroundService) {
        FlutterForegroundTask.sendDataToTask(TrackingMsg.encode(TrackingMsg.cmdFlush));
        FlutterForegroundTask.sendDataToTask(TrackingMsg.encode(TrackingMsg.cmdSnapshot));
        unawaited(_verifyServiceAlive());
      } else {
        unawaited(_localEngine?.flushNow());
      }
    } else {
      unawaited(restoreIfActive());
    }
    unawaited(syncPendingPings());
  }

  /// Applies server-side tuning. Safe to call repeatedly.
  void applyConfig({
    int? movingSeconds,
    int? stationarySeconds,
    int? nearCustomerSeconds,
    int? nearCustomerRadiusMeters,
    int? minDisplacementMeters,
  }) {
    _cfg = _cfg.merge(
      movingSeconds: movingSeconds,
      stationarySeconds: stationarySeconds,
      nearCustomerSeconds: nearCustomerSeconds,
      nearCustomerRadiusMeters: nearCustomerRadiusMeters,
      minDisplacementMeters: minDisplacementMeters,
    );
    _localEngine?.applyConfig(_cfg);
    if (state.backgroundService) {
      FlutterForegroundTask.sendDataToTask(
          TrackingMsg.encode(TrackingMsg.cmdConfig, {'config': _cfg.toJson()}));
    }
  }

  /// Tells the tracker where the employee's nearby customers are, so it can
  /// sample faster when close to one. Coordinates stay on the device.
  void setNearbyCustomerPoints(List<({double lat, double lng})> points) {
    _localEngine?.setNearbyCustomerPoints(points);
    if (state.backgroundService) {
      FlutterForegroundTask.sendDataToTask(TrackingMsg.encode(TrackingMsg.cmdNearby, {
        'points': [
          for (final p in points) {'lat': p.lat, 'lng': p.lng},
        ],
      }));
    }
  }

  // ── Android foreground service ───────────────────────────────────────────

  void _initService() {
    if (_serviceInitialised) return;
    _serviceInitialised = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: TrackingKeys.channelId,
        channelName: TrackingKeys.channelName,
        channelDescription:
            'Shown while your route is being recorded between check-in and check-out.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(TrackingKeys.tickMillis),
        // Bring the session back after a reboot / app update / OS kill.
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowAutoRestart: true,
        allowWakeLock: true,
        allowWifiLock: true,
        // Swiping the app away must not end the session.
        stopWithTask: false,
      ),
    );
  }

  Future<bool> _startService(int employeeId, String? deviceId) async {
    try {
      _initService();
      await FlutterForegroundTask.saveData(key: TrackingKeys.employeeId, value: employeeId);
      await FlutterForegroundTask.saveData(
          key: TrackingKeys.startedAt, value: DateTime.now().toUtc().toIso8601String());
      await FlutterForegroundTask.saveData(
          key: TrackingKeys.productName, value: Branding.current.productName);
      await FlutterForegroundTask.saveData(
          key: TrackingKeys.config, value: jsonEncode(_cfg.toJson()));
      if (deviceId != null) {
        await FlutterForegroundTask.saveData(key: TrackingKeys.deviceId, value: deviceId);
      } else {
        await FlutterForegroundTask.removeData(key: TrackingKeys.deviceId);
      }

      final ServiceRequestResult result;
      if (await FlutterForegroundTask.isRunningService) {
        result = await FlutterForegroundTask.restartService();
      } else {
        result = await FlutterForegroundTask.startService(
          serviceId: TrackingKeys.serviceId,
          serviceTypes: [ForegroundServiceTypes.location],
          notificationTitle: '${Branding.current.productName} attendance',
          notificationText: 'Recording your route while you are checked in',
          callback: trackingServiceStart,
        );
      }
      if (result is ServiceRequestFailure) {
        state = state.copyWith(
            lastError: 'Background tracking could not start: ${result.error}');
        if (kDebugMode) debugPrint('Tracking service start failed: ${result.error}');
        await FlutterForegroundTask.removeData(key: TrackingKeys.employeeId);
        return false;
      }
      return true;
    } catch (e) {
      state = state.copyWith(lastError: 'Background tracking could not start: $e');
      if (kDebugMode) debugPrint('Tracking service start threw: $e');
      return false;
    }
  }

  Future<void> _stopService({required bool flush}) async {
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.removeData(key: TrackingKeys.employeeId);
        return;
      }
      _stopAck = Completer<void>();
      FlutterForegroundTask.sendDataToTask(
          TrackingMsg.encode(TrackingMsg.cmdStop, {'flush': flush}));
      try {
        // The service flushes, reports tracking:false and stops itself.
        await _stopAck!.future.timeout(const Duration(seconds: 20));
      } catch (_) {
        // Didn't answer — stop it from here. Pings are still on disk.
        await FlutterForegroundTask.removeData(key: TrackingKeys.employeeId);
        await FlutterForegroundTask.stopService();
        if (flush && state.employeeId != null) {
          unawaited(_drainQueueFor(state.employeeId!));
        }
        await _sendStatusOff();
      }
    } catch (_) {
    } finally {
      _stopAck = null;
    }
  }

  /// The system can kill even a foreground service on some phones. If the
  /// session should be running but the service is gone, start it again.
  Future<void> _verifyServiceAlive() async {
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      final empId = state.employeeId;
      if (empId == null) return;
      state = state.copyWith(active: false, backgroundService: false);
      await start(empId);
    } catch (_) {}
  }

  void _onServiceData(Object data) {
    final msg = TrackingMsg.decode(data);
    if (msg == null) return;
    switch (msg['type']) {
      case TrackingMsg.evtSnapshot:
        final body = msg['snapshot'];
        if (body is Map<String, dynamic> && state.active && state.backgroundService) {
          final snap = TrackingSnapshot.fromJson(body);
          if (snap.employeeId == state.employeeId) {
            state = state.fromSnapshot(snap).copyWith(active: true);
          }
        }
      case TrackingMsg.evtStopped:
        _stopAck?.complete();
        _stopAck = null;
      case TrackingMsg.evtExpired:
        // Forgotten check-out: the service ended the session on its own.
        unawaited(_storage.delete(key: _kActiveEmployee));
        state = LocationTrackerState.idle.copyWith(
            lastError:
                'Tracking stopped automatically after 20 hours without a check-out.');
    }
  }

  // ── In-process engine (iOS / fallback) ───────────────────────────────────

  Future<void> _startLocal(int employeeId, String? deviceId) async {
    final engine = TrackingEngine(
      employeeId: employeeId,
      repo: _repo,
      store: _store,
      deviceId: deviceId,
      config: _cfg,
      onSnapshot: (s) {
        if (_localEngine != null && s.employeeId == state.employeeId) {
          state = state.fromSnapshot(s).copyWith(active: true, backgroundService: false);
        }
      },
      onSessionExpired: () => unawaited(stop()),
    );
    _localEngine = engine;
    await engine.start(
      androidForegroundNotification: _useService
          ? ForegroundNotificationConfig(
              notificationTitle: '${Branding.current.productName} attendance',
              notificationText: 'Recording your location while you are checked in',
              enableWakeLock: true,
              notificationChannelName: TrackingKeys.channelName,
            )
          : null,
    );
    _localTicker = Timer.periodic(const Duration(seconds: 15), (_) => engine.tick());
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _loadConfig() async {
    try {
      final cfg = await ApiClient.instance.get<FieldVisitConfig>(
        '/api/customers/nearby/config',
        parse: (d) => FieldVisitConfig.fromJson(d as Map<String, dynamic>),
      );
      _cfg = TrackingConfig.fromFieldVisit(cfg);
    } catch (_) {
      // Compiled-in / previous values stay.
    }
  }

  Future<void> _drainQueueFor(int employeeId) async {
    try {
      final pings = await _store.load(employeeId);
      for (var i = 0; i < pings.length; i += 200) {
        final slice = pings.sublist(i, (i + 200).clamp(0, pings.length));
        await _repo.uploadBatch(LocationPingBatch(employeeId: employeeId, pings: slice));
        await _store.removeConfirmed(employeeId, slice);
      }
    } catch (_) {}
  }

  Future<void> _sendStatusOff() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      await _repo.sendStatus(
        locationEnabled: enabled,
        permissionGranted: perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse,
        tracking: false,
      );
    } catch (_) {}
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

    await _requestBatteryExemption();
    return true;
  }

  /// Asks the OS to exempt the app from battery optimisation on Android. This
  /// is also what lets the system restart the service from the background
  /// (reboot, OS kill) on Android 12+. Never blocks tracking.
  Future<void> _requestBatteryExemption() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Permission unavailable on this OS/OEM — ignore.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_useService) FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
    _localTicker?.cancel();
    super.dispose();
  }
}

final locationTrackerProvider =
    StateNotifierProvider<LocationTracker, LocationTrackerState>(
  (ref) => LocationTracker(ref.watch(locationRepositoryProvider)),
);
