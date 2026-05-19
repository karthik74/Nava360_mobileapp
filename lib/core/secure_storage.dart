import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted key/value store wrapper. Keychain on iOS, EncryptedSharedPreferences
/// on Android. Use for the JWT and any other secrets.
class SecureStorage {
  static const _opts = AndroidOptions(encryptedSharedPreferences: true);
  static const _storage = FlutterSecureStorage(aOptions: _opts);

  static const _kToken = 'auth.token';
  static const _kUserJson = 'auth.user';

  static Future<void> writeToken(String token) =>
      _storage.write(key: _kToken, value: token);

  static Future<String?> readToken() => _storage.read(key: _kToken);

  static Future<void> writeUserJson(String json) =>
      _storage.write(key: _kUserJson, value: json);

  static Future<String?> readUserJson() => _storage.read(key: _kUserJson);

  static Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUserJson);
  }
}
