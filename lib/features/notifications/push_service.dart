import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications_repository.dart';

/// Background handler — must be a top-level / static function so Firebase can
/// invoke it from an isolate when the app is killed. It does nothing beyond
/// letting the system show the notification; we keep heavy work for the
/// foreground path.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The notification is already rendered by the system tray for "notification"
  // payloads. For data-only payloads we'd schedule a local notification here.
  debugPrint('FCM background: ${message.messageId}');
}

/// Wraps Firebase Messaging + `flutter_local_notifications` and registers the
/// device token with the backend.
class PushService {
  PushService({required NotificationsRepository repo}) : _repo = repo;

  final NotificationsRepository _repo;

  static const _androidChannel = AndroidNotificationChannel(
    'hrms_default_channel',
    'HRMS notifications',
    description: 'Tasks, leaves, attendance and announcements.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _started = false;
  bool _firebaseReady = false;
  bool _localReady = false;

  /// True once Firebase initialised AND local notifications are wired up.
  /// Use this to short-circuit FCM calls when the native plugin is missing
  /// (e.g. running on a dev device without `google-services.json`).
  bool get isAvailable => _firebaseReady && _localReady;

  /// One-shot initialisation. Brings up Firebase, local notifications and
  /// the Android notification channel. Catches and logs everything so a
  /// misconfigured device cannot prevent the app from booting.
  Future<void> init() async {
    // 1) Local notifications — works without Firebase, useful even if FCM is
    //    unavailable (e.g. for manually-triggered in-app reminders).
    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
      _localReady = true;
    } catch (e) {
      debugPrint('Local notifications init failed: $e');
    }

    // 2) Firebase + Messaging — guarded against missing google-services.json
    //    or absent Play Services on the device.
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _firebaseReady = true;
    } on FirebaseException catch (e) {
      debugPrint('Firebase init failed (${e.code}): ${e.message}');
    } on PlatformException catch (e) {
      debugPrint(
        'Firebase plugin channel-error: ${e.code}. '
        'Did you add android/app/google-services.json and rebuild?',
      );
    } catch (e) {
      debugPrint('Firebase init failed: $e');
    }
  }

  /// Starts listening for messages and registers the device token. Idempotent.
  /// Silently no-ops when Firebase is unavailable.
  Future<void> start() async {
    if (_started) return;
    if (!_firebaseReady) {
      debugPrint('PushService.start skipped: Firebase not available');
      return;
    }
    _started = true;

    await _registerCurrentToken();

    try {
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) => _register(token),
        onError: (Object e) => debugPrint('FCM token refresh error: $e'),
      );
      _foregroundSub = FirebaseMessaging.onMessage.listen(_showLocal);
    } catch (e) {
      debugPrint('PushService.start subscribe failed: $e');
    }
  }

  /// Stops listeners. Call on logout.
  Future<void> stop() async {
    await _foregroundSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _tokenRefreshSub = null;
    _started = false;
  }

  Future<void> _registerCurrentToken() async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _register(token);
      }
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
    }
  }

  Future<void> _register(String token) async {
    final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
    debugPrint('Registering FCM token ($platform): ${_redact(token)}');
    await _repo.registerDeviceToken(token: token, platform: platform);
  }

  /// Renders a foreground FCM message as a local notification so the user
  /// sees it even when the app is open. FCM does NOT auto-display in the
  /// foreground — this fills that gap.
  Future<void> _showLocal(RemoteMessage message) async {
    if (!_localReady) return;
    try {
      final n = message.notification;
      final android = message.notification?.android;
      final title =
          n?.title ?? message.data['title']?.toString() ?? 'Notification';
      final body = n?.body ?? message.data['body']?.toString() ?? '';

      await _local.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
            ticker: title,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data.isEmpty ? null : message.data.toString(),
      );
    } catch (e) {
      debugPrint('Local notification show failed: $e');
    }
  }

  String _redact(String token) {
    if (token.length <= 12) return '***';
    return '${token.substring(0, 6)}…${token.substring(token.length - 6)}';
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(repo: ref.watch(notificationsRepositoryProvider)),
);
