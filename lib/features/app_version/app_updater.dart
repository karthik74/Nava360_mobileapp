import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Downloads the new app build and launches the OS installer.
///
/// Android: streams the APK to the app cache, then opens it with the system
/// package installer (needs the REQUEST_INSTALL_PACKAGES permission).
/// Other platforms / non-APK links (e.g. a Play Store or App Store URL) just
/// open the link externally.
class AppUpdater {
  // ── Download-progress notification ─────────────────────────────────────────
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();
  static const _channelId = 'app_update_channel';
  static const _notifId = 424242;
  static bool _channelReady = false;
  static int _lastShownPercent = -1;

  /// Creates the (low-importance, silent) update channel once. Relies on the
  /// native plugin already being initialised by PushService at startup, so we
  /// never call initialize() here (which would override the tap handler).
  static Future<void> _ensureChannel() async {
    if (_channelReady) return;
    try {
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        'App updates',
        description: 'Download progress for app updates',
        importance: Importance.low,
      ));
      _channelReady = true;
    } catch (e) {
      debugPrint('Update channel create failed: $e');
    }
  }

  static Future<void> _showProgress(int percent) async {
    if (percent == _lastShownPercent) return; // throttle to whole-percent steps
    _lastShownPercent = percent;
    try {
      await _fln.show(
        _notifId,
        'Downloading update',
        '$percent%',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'App updates',
            channelDescription: 'Download progress for app updates',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: false,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Update progress notification failed: $e');
    }
  }

  static Future<void> _showDone() async {
    try {
      await _fln.show(
        _notifId,
        'Update downloaded',
        'Tap the installer to finish updating.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'App updates',
            channelDescription: 'Download progress for app updates',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            ongoing: false,
            autoCancel: true,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (_) {/* ignored */}
  }

  static Future<void> _cancelNotif() async {
    try {
      await _fln.cancel(_notifId);
    } catch (_) {/* ignored */}
  }

  /// Returns true when [url] is an APK we can download + install in-app.
  static bool canInstallInApp(String url) =>
      Platform.isAndroid && url.toLowerCase().split('?').first.endsWith('.apk');

  /// Opens [url] in the browser / store app. Throws if nothing can handle it.
  static Future<void> openExternally(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('Invalid download link.');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open the download link.');
    }
  }

  /// Downloads the APK at [url] (reporting 0..1 progress) and launches the
  /// installer. Falls back to opening the link for non-APK / non-Android.
  static Future<void> downloadAndInstall(
    String url, {
    void Function(double progress)? onProgress,
    void Function()? onInstalling,
  }) async {
    if (!canInstallInApp(url)) {
      await openExternally(url);
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/nava360-update.apk';
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }

    await _ensureChannel();
    _lastShownPercent = -1;
    await _showProgress(0);

    try {
      final dio = Dio();
      await dio.download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final fraction = received / total;
          onProgress?.call(fraction);
          _showProgress((fraction * 100).round());
        },
      );

      onInstalling?.call();
      await _showDone();
      final result = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        await _cancelNotif();
        throw Exception(result.message.isEmpty
            ? 'Could not open the installer.'
            : result.message);
      }
    } catch (_) {
      await _cancelNotif();
      rethrow;
    }
  }
}
