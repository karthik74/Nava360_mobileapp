import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';
import 'push_service.dart';

/// Demo builds only (the same `--dart-define=DEMO_LOGIN_PASSWORD` that shows the
/// Test FO / Test BM buttons): shows new in-app task alerts — e.g. a new or
/// broken PTP — as notification banners without Firebase, by polling the
/// signed-in user's `/api/task-notifications` every 10 s while the app runs.
/// Tapping a banner opens the notification's own route (see
/// [notificationRoute]). It stands down while Firebase push really reaches
/// this device ([PushService.isPushRegistered]): the backend sends a push AND
/// writes an in-app row for the same alert (an FTOD digest, a broken PTP), so
/// polling too would show every alert twice. A normal build compiles this to
/// nothing.
const _kDemoAlerts = String.fromEnvironment('DEMO_LOGIN_PASSWORD') != '';

/// Where tapping an in-app notification should land: the row's own `route`
/// (PTP rows → '/ptp', FTOD digests → '/ftod'), else the task list the older
/// task alerts always opened. Only in-app paths are honoured.
String notificationRoute(Map<String, dynamic> n) {
  final route = n['route']?.toString().trim();
  return route != null && route.startsWith('/') ? route : '/tasks';
}

final demoAlertPollerProvider = Provider<void>((ref) {
  if (!_kDemoAlerts) return;

  Timer? timer;
  int? lastSeen; // null until the first poll: alerts already there are not re-announced

  Future<void> poll() async {
    if (ref.read(pushServiceProvider).isPushRegistered) {
      // FCM delivers these itself. Forget the baseline so that, should push
      // stop, the first poll re-baselines instead of replaying old rows.
      lastSeen = null;
      return;
    }
    try {
      final items = await ApiClient.instance.get<List<Map<String, dynamic>>>(
        '/api/task-notifications',
        query: {'page': 0, 'size': 10},
        parse: (d) => ((d as Map)['content'] as List? ?? const [])
            .cast<Map<String, dynamic>>(),
      );
      final ids = items.map((n) => (n['id'] as num).toInt()).toList();
      final newest = ids.isEmpty ? 0 : ids.reduce(max);
      final seen = lastSeen;
      lastSeen = max(seen ?? 0, newest);
      if (seen == null) return;
      for (final n in items.reversed) {
        final id = (n['id'] as num).toInt();
        if (id <= seen || n['read'] == true) continue;
        await ref.read(pushServiceProvider).showLocal(
              id: id,
              title: (n['title'] ?? 'Nava360').toString(),
              body: (n['message'] ?? '').toString(),
              route: notificationRoute(n),
            );
      }
    } catch (e) {
      debugPrint('Demo alert poll failed: $e');
    }
  }

  ref.listen<AsyncValue<dynamic>>(
    authControllerProvider,
    (prev, next) {
      final signedIn = next.asData?.value != null;
      timer?.cancel();
      timer = null;
      lastSeen = null;
      if (signedIn) {
        poll();
        timer = Timer.periodic(const Duration(seconds: 10), (_) => poll());
      }
    },
    fireImmediately: true,
  );
  ref.onDispose(() => timer?.cancel());
});
