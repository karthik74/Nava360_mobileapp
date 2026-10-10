import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../location_ping_store.dart';
import '../location_repository.dart';
import 'tracking_engine.dart';

/// Keys shared by the UI controller and the service isolate. Values live in the
/// plugin's SharedPreferences (`FlutterForegroundTask.saveData`) so a service
/// restarted by the system — after a reboot, an app update or a low-memory kill
/// — can rebuild the session without the app ever opening.
abstract final class TrackingKeys {
  static const employeeId = 'tracking.employeeId';
  static const deviceId = 'tracking.deviceId';
  static const startedAt = 'tracking.startedAt';
  static const config = 'tracking.config';
  static const productName = 'tracking.productName';
  static const appVersion = 'tracking.appVersion';

  /// Android foreground-service id (any stable non-zero int).
  static const serviceId = 7100;
  static const channelId = 'attendance_tracking';
  static const channelName = 'Attendance tracking';

  /// How often the service's clock calls [TrackingEngine.tick].
  static const tickMillis = 15000;
}

/// Messages between the UI isolate and the service isolate (JSON strings).
abstract final class TrackingMsg {
  // UI → service
  static const cmdStop = 'stop';
  static const cmdFlush = 'flush';
  static const cmdConfig = 'config';
  static const cmdNearby = 'nearby';
  static const cmdSnapshot = 'snapshot';

  // service → UI
  static const evtSnapshot = 'snapshot';
  static const evtStopped = 'stopped';
  static const evtExpired = 'expired';

  static String encode(String type, [Map<String, dynamic>? body]) =>
      jsonEncode({'type': type, ...?body});

  static Map<String, dynamic>? decode(Object data) {
    if (data is! String) return null;
    try {
      final j = jsonDecode(data);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }
}

/// Service entry point. Must be a top-level function kept alive for the
/// background engine, hence the pragma.
@pragma('vm:entry-point')
void trackingServiceStart() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}

/// Hosts a [TrackingEngine] inside the Android foreground service.
///
/// The service (and this isolate) outlives the app: swiping the app away,
/// the launcher killing the UI process, or a reboot (the plugin re-starts the
/// service on BOOT_COMPLETED) all leave the engine running or bring it back.
/// The plugin registers the app's plugins in the service engine, so geolocator,
/// secure storage (for the token), battery and the file queue all work here.
///
/// What it cannot survive, and does not claim to: a force-stop from app
/// settings, a revoked location permission, or location switched off. Those
/// end up on the server as status, so the resulting gap is explained there.
class TrackingTaskHandler extends TaskHandler {
  TrackingEngine? _engine;
  String _productName = 'Nava360';
  DateTime? _lastNotificationUpdate;
  bool _stopping = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final empId = await FlutterForegroundTask.getData<int>(key: TrackingKeys.employeeId);
    if (empId == null) {
      // Nothing to resume (a restart after the employee already checked out).
      await FlutterForegroundTask.stopService();
      return;
    }
    _productName =
        await FlutterForegroundTask.getData<String>(key: TrackingKeys.productName) ??
            _productName;
    final deviceId =
        await FlutterForegroundTask.getData<String>(key: TrackingKeys.deviceId);
    final appVersion =
        await FlutterForegroundTask.getData<String>(key: TrackingKeys.appVersion);
    final startedRaw =
        await FlutterForegroundTask.getData<String>(key: TrackingKeys.startedAt);
    final startedAt = startedRaw == null ? null : DateTime.tryParse(startedRaw)?.toLocal();

    TrackingConfig cfg = TrackingConfig.fallback;
    final cfgRaw = await FlutterForegroundTask.getData<String>(key: TrackingKeys.config);
    if (cfgRaw != null) {
      try {
        cfg = TrackingConfig.fromJson(jsonDecode(cfgRaw) as Map<String, dynamic>);
      } catch (_) {}
    }

    // A session restored by the system long after check-in may already be a
    // forgotten one; the engine's own guard handles that on the first tick.
    final engine = TrackingEngine(
      employeeId: empId,
      repo: LocationRepository(ApiClient.instance),
      store: LocationPingStore.instance,
      deviceId: deviceId,
      appVersion: appVersion,
      serviceHosted: true,
      config: cfg,
      onSnapshot: _publish,
      onSessionExpired: _onSessionExpired,
    );
    _engine = engine;
    await engine.start(sessionStartedAt: startedAt);
    _updateNotification(force: true);
    if (kDebugMode) {
      debugPrint('Tracking service started for employee $empId (${starter.name})');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final engine = _engine;
    if (engine == null || _stopping) return;
    engine.tick();
    _updateNotification();
  }

  @override
  void onReceiveData(Object data) {
    final msg = TrackingMsg.decode(data);
    if (msg == null) return;
    final engine = _engine;
    switch (msg['type']) {
      case TrackingMsg.cmdStop:
        unawaited(_stopAndExit(flush: msg['flush'] != false));
      case TrackingMsg.cmdFlush:
        unawaited(engine?.flushNow());
      case TrackingMsg.cmdConfig:
        final body = msg['config'];
        if (engine != null && body is Map<String, dynamic>) {
          engine.applyConfig(TrackingConfig.fromJson(body));
          unawaited(FlutterForegroundTask.saveData(
              key: TrackingKeys.config, value: jsonEncode(body)));
        }
      case TrackingMsg.cmdNearby:
        final pts = msg['points'];
        if (engine != null && pts is List) {
          engine.setNearbyCustomerPoints([
            for (final p in pts)
              if (p is Map)
                (
                  lat: (p['lat'] as num).toDouble(),
                  lng: (p['lng'] as num).toDouble(),
                ),
          ]);
        }
      case TrackingMsg.cmdSnapshot:
        if (engine != null) _publish(engine.snapshot);
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Reached on an orderly stop (already handled) or when the system tears the
    // service down. Captured pings are already on disk; try a quick upload but
    // do NOT tell the server tracking stopped — auto-restart brings the session
    // back, and a false "not tracking" would mislabel the gap.
    final engine = _engine;
    _engine = null;
    if (engine != null && engine.active) {
      try {
        await engine
            .stop(flush: true, announce: false, flushTimeout: const Duration(seconds: 5))
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<void> _stopAndExit({required bool flush}) async {
    if (_stopping) return;
    _stopping = true;
    final engine = _engine;
    _engine = null;
    try {
      if (engine != null) {
        await engine.stop(flush: flush, announce: true).timeout(const Duration(seconds: 20));
      }
    } catch (_) {
    } finally {
      await FlutterForegroundTask.removeData(key: TrackingKeys.employeeId);
      await FlutterForegroundTask.removeData(key: TrackingKeys.startedAt);
      FlutterForegroundTask.sendDataToMain(TrackingMsg.encode(TrackingMsg.evtStopped));
      await FlutterForegroundTask.stopService();
    }
  }

  void _onSessionExpired() {
    FlutterForegroundTask.sendDataToMain(TrackingMsg.encode(TrackingMsg.evtExpired));
    unawaited(_stopAndExit(flush: true));
  }

  void _publish(TrackingSnapshot s) {
    FlutterForegroundTask.sendDataToMain(
        TrackingMsg.encode(TrackingMsg.evtSnapshot, {'snapshot': s.toJson()}));
  }

  void _updateNotification({bool force = false}) {
    final engine = _engine;
    if (engine == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastNotificationUpdate != null &&
        now.difference(_lastNotificationUpdate!) < const Duration(minutes: 1)) {
      return;
    }
    _lastNotificationUpdate = now;
    final s = engine.snapshot;
    final time = s.lastCapturedAt == null
        ? 'waiting for GPS'
        : 'last point ${DateFormat('HH:mm').format(s.lastCapturedAt!)}';
    final queued = s.bufferedCount > 0 ? ' · ${s.bufferedCount} to upload' : '';
    final status = !s.locationEnabled
        ? 'Location is OFF — turn it on to keep tracking'
        : s.authExpired
            ? 'Open the app to sign in again — points are saved on this phone'
            : s.gpsWeak
                ? 'GPS signal weak — move to open sky · $time$queued'
                : 'Recording your route while checked in · $time$queued';
    unawaited(FlutterForegroundTask.updateService(
      notificationTitle: '$_productName attendance',
      notificationText: status,
    ));
  }
}
