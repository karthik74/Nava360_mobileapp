import 'package:flutter/services.dart';

/// Blocks screenshots / screen recording while any claiming screen is mounted.
///
/// - Android: `FLAG_SECURE` — the OS refuses the screenshot outright and
///   blanks the app-switcher preview.
/// - iOS: the secure-text-field layer technique — the screenshot/recording is
///   taken but the app's content comes out BLACK (iOS has no API to refuse a
///   screenshot; this is the same approach WhatsApp-class apps use).
///
/// Reference-counted: chat list → thread → image viewer can each hold a claim
/// and protection is only lifted when the LAST one releases. Calls are
/// fire-and-forget and safely no-op where the channel isn't available (tests).
class SecureScreen {
  SecureScreen._();

  static const _channel = MethodChannel('app/secure_screen');
  static int _claims = 0;

  /// Call from a confidential screen's initState.
  static Future<void> acquire() async {
    _claims++;
    if (_claims == 1) {
      try {
        await _channel.invokeMethod('enable');
      } catch (_) {
        // Platform without the channel (iOS/tests) — nothing to do.
      }
    }
  }

  /// Call from the same screen's dispose.
  static Future<void> release() async {
    if (_claims > 0) _claims--;
    if (_claims == 0) {
      try {
        await _channel.invokeMethod('disable');
      } catch (_) {
        // Platform without the channel — nothing to do.
      }
    }
  }
}
