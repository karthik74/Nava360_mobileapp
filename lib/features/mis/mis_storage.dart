import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted storage for the MIS (Grow With Me) session.
///
/// Kept deliberately SEPARATE from [SecureStorage] (`auth.token` / `auth.user`)
/// because MIS is a different backend with its own token — the two sessions must
/// never collide. Keychain on iOS, EncryptedSharedPreferences on Android.
class MisStorage {
  static const _opts = AndroidOptions(encryptedSharedPreferences: true);
  static const _storage = FlutterSecureStorage(aOptions: _opts);

  static const _kToken = 'mis.token';
  static const _kUser = 'mis.user'; // JSON { user, scope }

  static Future<void> writeToken(String token) =>
      _storage.write(key: _kToken, value: token);

  static Future<String?> readToken() async {
    try {
      return await _storage.read(key: _kToken);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeUserJson(String json) =>
      _storage.write(key: _kUser, value: json);

  static Future<String?> readUserJson() async {
    try {
      return await _storage.read(key: _kUser);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
  }
}
