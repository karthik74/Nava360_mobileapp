import 'package:flutter/foundation.dart';
import 'package:smart_auth/smart_auth.dart';

/// Auto-reads an incoming OTP SMS using Google's **SMS User Consent API**.
///
/// Why this and not `READ_SMS`: the User Consent API needs **no SMS permission**
/// at all. When a matching OTP arrives, Android shows a one-time
/// "Allow <app> to read this message?" prompt; if the user taps Allow, the
/// plugin hands us just that single message and we extract the code. This is the
/// Google-sanctioned, Play Protect–safe way to read OTPs — it does not trip the
/// restricted-permission wall or get blocked on sideloaded installs.
///
/// Android-only; on other platforms every method is a safe no-op.
class SmsOtpListener {
  final SmartAuth _smartAuth = SmartAuth();
  bool _active = false;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Start listening for an OTP of [digits] length. [onCode] is called with the
  /// extracted code once the SMS arrives and the user allows it. Calling again
  /// restarts the listener. The underlying API times out after ~5 minutes.
  Future<void> start({
    required int digits,
    required ValueChanged<String> onCode,
  }) async {
    if (!isSupported) return;
    await cancel();
    _active = true;
    try {
      final res = await _smartAuth.getSmsCode(
        useUserConsentApi: true,
        matcher: '\\d{$digits}',
      );
      if (_active && res.codeFound && res.code != null) {
        onCode(res.code!);
      }
    } catch (e) {
      debugPrint('[sms-otp] listen failed: $e');
    } finally {
      _active = false;
    }
  }

  /// Stop listening (call on dispose / when leaving the OTP step).
  Future<void> cancel() async {
    _active = false;
    if (!isSupported) return;
    try {
      await _smartAuth.removeSmsListener();
    } catch (_) {}
  }
}
