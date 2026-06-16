import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/secure_storage.dart';
import '../attendance/live_location_responder.dart';
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
  // HR asked for this device's current location — answer even from the background.
  if (message.data['type'] == 'LOCATION_REQUEST') {
    await respondToLiveLocationRequest();
  }
}

/// Wraps Firebase Messaging + `flutter_local_notifications` and registers the
/// device token with the backend.
class PushService {
  PushService({required NotificationsRepository repo}) : _repo = repo;

  final NotificationsRepository _repo;

  static const _androidChannel = AndroidNotificationChannel(
    'hrms_default_channel',
    'Nava360 notifications',
    description: 'Tasks, leaves, attendance and announcements.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _started = false;
  bool _firebaseReady = false;
  bool _localReady = false;

  /// Called with a conversationId when a chat notification is tapped. Set by the
  /// app root (where the router is available). Any tap that arrives before this
  /// is wired is buffered and flushed once the callback is set.
  void Function(int conversationId)? _onOpenChat;
  int? _pendingChatId;

  set onOpenChat(void Function(int conversationId)? cb) {
    _onOpenChat = cb;
    final pending = _pendingChatId;
    if (cb != null && pending != null) {
      _pendingChatId = null;
      cb(pending);
    }
  }

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
        onDidReceiveNotificationResponse: _onLocalTap,
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
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      // Tap handling: app in background → onMessageOpenedApp; app launched cold
      // from a tapped notification → getInitialMessage.
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteTap);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleRemoteTap(initial);
    } catch (e) {
      debugPrint('PushService.start subscribe failed: $e');
    }
  }

  /// Enables or disables push notifications for this device.
  ///
  /// Disabling unregisters the device's FCM token with the backend (so the
  /// server stops pushing) and tears down the listeners. Enabling re-registers
  /// the token and re-attaches listeners. The persisted preference itself is
  /// owned by [NotificationsEnabledController]; this only applies the effect.
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      if (_started) {
        await _registerCurrentToken();
      } else {
        await start();
      }
      return;
    }
    // Disabling: best-effort unregister of the current token, then stop.
    try {
      if (_firebaseReady) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await _repo.unregisterDeviceToken(token);
        }
      }
    } catch (e) {
      debugPrint('Disable notifications: unregister failed: $e');
    }
    await stop();
  }

  /// Stops listeners. Call on logout.
  Future<void> stop() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _tokenRefreshSub = null;
    _started = false;
  }

  // ── Notification tap → open chat ──────────────────────────────────────────

  void _handleRemoteTap(RemoteMessage message) => _handleTapData(message.data);

  void _onLocalTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = (jsonDecode(payload) as Map).cast<String, dynamic>();
      _handleTapData(data);
    } catch (_) {
      // Non-JSON payloads (older notifications) are ignored.
    }
  }

  void _handleTapData(Map<String, dynamic> data) {
    if (data['type']?.toString() != 'CHAT') return;
    final id = int.tryParse('${data['conversationId']}');
    if (id == null) return;
    final cb = _onOpenChat;
    if (cb != null) {
      cb(id);
    } else {
      // Router not wired yet (cold start) — flush once onOpenChat is set.
      _pendingChatId = id;
    }
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
    // Respect the user's notifications preference — never register the token
    // (e.g. on a token refresh) while notifications are disabled.
    if (!await SecureStorage.readNotificationsEnabled()) {
      debugPrint('Notifications disabled — skipping token registration');
      return;
    }
    final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
    debugPrint('Registering FCM token ($platform): ${_redact(token)}');
    await _repo.registerDeviceToken(token: token, platform: platform);
  }

  /// Routes a foreground message: silent control messages (e.g. a live-location
  /// request) are handled without a notification; everything else is shown.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'LOCATION_REQUEST') {
      await respondToLiveLocationRequest();
      return;
    }
    await _showLocal(message);
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

      // A large image (e.g. a greeting poster) arrives either on the
      // notification payload or as `posterUrl` in the data payload. Download it
      // so the foreground notification shows the poster like the system tray.
      final imageUrl = android?.imageUrl ??
          message.notification?.apple?.imageUrl ??
          message.data['posterUrl']?.toString();
      final imagePath =
          (imageUrl != null && imageUrl.isNotEmpty) ? await _downloadImage(imageUrl) : null;

      StyleInformation? androidStyle;
      List<DarwinNotificationAttachment> iosAttachments = const [];
      if (imagePath != null) {
        androidStyle = BigPictureStyleInformation(
          FilePathAndroidBitmap(imagePath),
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: true,
        );
        iosAttachments = [DarwinNotificationAttachment(imagePath)];
      }

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
            styleInformation: androidStyle,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            attachments: iosAttachments,
          ),
        ),
        payload: message.data.isEmpty ? null : jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('Local notification show failed: $e');
    }
  }

  /// Downloads an image to a temp file for use as a notification big-picture /
  /// attachment. Returns the local path, or null on any failure.
  Future<String?> _downloadImage(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final file =
          '${dir.path}/greeting_${url.hashCode}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final resp = await Dio().download(url, file,
          options: Options(receiveTimeout: const Duration(seconds: 20)));
      if (resp.statusCode != null && resp.statusCode! < 300) return file;
      return null;
    } catch (e) {
      debugPrint('Notification image download failed: $e');
      return null;
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

/// Holds the "push notifications enabled" preference (default on) and applies
/// changes to the [PushService]. Backed by [SecureStorage] so it persists.
class NotificationsEnabledController extends StateNotifier<bool> {
  NotificationsEnabledController(this._push) : super(true) {
    _load();
  }

  final PushService _push;

  Future<void> _load() async {
    state = await SecureStorage.readNotificationsEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await SecureStorage.writeNotificationsEnabled(enabled);
    await _push.setEnabled(enabled);
  }
}

final notificationsEnabledProvider =
    StateNotifierProvider<NotificationsEnabledController, bool>(
  (ref) => NotificationsEnabledController(ref.watch(pushServiceProvider)),
);
