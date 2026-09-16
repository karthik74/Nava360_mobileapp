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
  static const _kBranding = 'branding.json';

  // ── Biometric login (mobile only) — survive a "logout only" sign-out so the
  // next open can offer fingerprint / Face ID; wiped by clearBiometric(). ──
  static const _kBioEnabled = 'biometric.enabled';
  static const _kBioToken = 'biometric.token'; // rotated opaque credential
  static const _kBioDeviceId = 'biometric.device_id';
  static const _kBioEmployeeId = 'biometric.employee_id';
  static const _kBioUsername = 'biometric.username';
  static const _kBioLabel = 'biometric.device_label';

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

  /// Cached `/api/public/branding` payload — survives sign-out so the app
  /// paints branded on every launch, even before login.
  static Future<String?> readBrandingJson() => _read(_kBranding);

  static Future<void> writeBrandingJson(String json) => _write(_kBranding, json);

  /// AI-assistant voice preferences (JSON) — per device, survives sign-out.
  static Future<String?> readAssistantVoiceJson() => _read('assistant.voice');

  static Future<void> writeAssistantVoiceJson(String json) =>
      _write('assistant.voice', json);

  /// Clears auth credentials. The welcome flag and any biometric enrollment are
  /// intentionally preserved — a "logout only" keeps biometric login available.
  static Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUserJson);
  }

  // ── Biometric enrollment ──────────────────────────────────────────────────

  /// Whether this device currently has a biometric enrollment stored.
  static Future<bool> readBiometricEnabled() async {
    final v = await _read(_kBioEnabled);
    return v == '1';
  }

  /// Persist a biometric enrollment (after enable or a rotated login credential).
  static Future<void> writeBiometricEnrollment({
    required String token,
    required String deviceId,
    int? employeeId,
    String? username,
    String? deviceLabel,
  }) async {
    await _write(_kBioEnabled, '1');
    await _write(_kBioToken, token);
    await _write(_kBioDeviceId, deviceId);
    if (employeeId != null) await _write(_kBioEmployeeId, employeeId.toString());
    if (username != null) await _write(_kBioUsername, username);
    if (deviceLabel != null) await _write(_kBioLabel, deviceLabel);
  }

  /// Update just the rotated credential returned by a biometric login.
  static Future<void> updateBiometricToken(String token) => _write(_kBioToken, token);

  static Future<String?> readBiometricToken() => _read(_kBioToken);
  static Future<String?> readBiometricDeviceId() => _read(_kBioDeviceId);
  static Future<String?> readBiometricUsername() => _read(_kBioUsername);
  static Future<String?> readBiometricLabel() => _read(_kBioLabel);

  /// Remove the biometric enrollment entirely (disable / logout-and-disable).
  static Future<void> clearBiometric() async {
    await _storage.delete(key: _kBioEnabled);
    await _storage.delete(key: _kBioToken);
    await _storage.delete(key: _kBioDeviceId);
    await _storage.delete(key: _kBioEmployeeId);
    await _storage.delete(key: _kBioUsername);
    await _storage.delete(key: _kBioLabel);
  }

  /// A stable per-install device id: reuse the biometric one if present, else
  /// generate + persist a fresh UUID so it survives across enrollments.
  static Future<String> readOrCreateDeviceId(String Function() generate) async {
    final existing = await _read(_kBioDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = generate();
    await _write(_kBioDeviceId, id);
    return id;
  }
}
