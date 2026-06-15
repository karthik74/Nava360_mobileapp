import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted key/value store wrapper. Keychain on iOS, EncryptedSharedPreferences
/// on Android. Use for the JWT and any other secrets.
class SecureStorage {
  static const _opts = AndroidOptions(encryptedSharedPreferences: true);
  static const _storage = FlutterSecureStorage(aOptions: _opts);

  static const _kToken = 'auth.token';
  static const _kUserJson = 'auth.user';
  static const _kWelcomeSeen = 'onboarding.welcome_seen';
  static const _kNotifEnabled = 'notifications.enabled';

  static Future<void> writeToken(String token) => _write(_kToken, token);

  static Future<String?> readToken() => _read(_kToken);

  static Future<void> writeUserJson(String json) => _write(_kUserJson, json);

  static Future<String?> readUserJson() => _read(_kUserJson);

  /// Reads a key, self-healing if the encrypted store is unreadable.
  ///
  /// After an Android cloud-backup restore onto a NEW device, the encrypted
  /// blob is restored but the Keystore key that decrypts it is not — so reads
  /// throw (e.g. AEADBadTagException). Rather than letting that error bubble up
  /// into every API request (which manifests as spurious 401s once the token
  /// can't be read), we wipe the corrupt store and return null so the app
  /// degrades cleanly to a signed-out state.
  static Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      await _safeWipe();
      return null;
    }
  }

  /// Writes a key, recovering from a corrupt store by wiping and retrying once.
  /// This lets the very first login on a backup-restored device repair storage
  /// in place instead of failing forever.
  static Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      await _safeWipe();
      await _storage.write(key: key, value: value);
    }
  }

  static Future<void> _safeWipe() async {
    try {
      await _storage.deleteAll();
    } catch (_) {
      // Nothing more we can do; subsequent writes start from a clean slate.
    }
  }

  /// Has the user seen the welcome / onboarding screen at least once?
  /// Returns false on a fresh install.
  static Future<bool> readWelcomeSeen() async {
    final v = await _storage.read(key: _kWelcomeSeen);
    return v == '1';
  }

  static Future<void> markWelcomeSeen() =>
      _storage.write(key: _kWelcomeSeen, value: '1');

  /// Whether push notifications are enabled for this device. Defaults to true
  /// (opt-out). Preserved across sign-out so the preference sticks per device.
  static Future<bool> readNotificationsEnabled() async {
    final v = await _read(_kNotifEnabled);
    return v != '0';
  }

  static Future<void> writeNotificationsEnabled(bool enabled) =>
      _write(_kNotifEnabled, enabled ? '1' : '0');

  /// Clears auth credentials. The welcome flag is intentionally preserved
  /// so signing out doesn't replay the welcome screen.
  static Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUserJson);
  }
}
