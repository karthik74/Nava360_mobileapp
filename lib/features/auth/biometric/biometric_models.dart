import '../auth_models.dart';

/// Result of `POST /api/auth/mobile/enable-biometric`.
class BiometricEnrollResult {
  final String biometricToken;
  final String deviceId;
  const BiometricEnrollResult({required this.biometricToken, required this.deviceId});

  factory BiometricEnrollResult.fromJson(Map<String, dynamic> j) => BiometricEnrollResult(
        biometricToken: j['biometricToken'] as String,
        deviceId: j['deviceId'] as String,
      );
}

/// Result of `POST /api/auth/mobile/biometric-login` — the normal auth payload
/// plus a rotated credential that replaces the one just used.
class BiometricLoginResult {
  final AuthUser auth;
  final String biometricToken;
  final String deviceId;
  const BiometricLoginResult({
    required this.auth,
    required this.biometricToken,
    required this.deviceId,
  });

  factory BiometricLoginResult.fromJson(Map<String, dynamic> j) => BiometricLoginResult(
        auth: AuthUser.fromJson(j['auth'] as Map<String, dynamic>),
        biometricToken: j['biometricToken'] as String,
        deviceId: j['deviceId'] as String,
      );
}

/// A registered device shown in Settings → Security → Registered Devices.
class RegisteredDevice {
  final int id;
  final String deviceId;
  final String? deviceName;
  final String? platform;
  final bool enabled;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool currentDevice;

  const RegisteredDevice({
    required this.id,
    required this.deviceId,
    this.deviceName,
    this.platform,
    required this.enabled,
    this.lastLoginAt,
    this.createdAt,
    this.expiresAt,
    required this.currentDevice,
  });

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory RegisteredDevice.fromJson(Map<String, dynamic> j) => RegisteredDevice(
        id: (j['id'] as num).toInt(),
        deviceId: j['deviceId'] as String,
        deviceName: j['deviceName'] as String?,
        platform: j['platform'] as String?,
        enabled: j['enabled'] == true,
        lastLoginAt: _date(j['lastLoginAt']),
        createdAt: _date(j['createdAt']),
        expiresAt: _date(j['expiresAt']),
        currentDevice: j['currentDevice'] == true,
      );
}

/// Local device identity captured for enrollment (never leaves basic metadata).
class DeviceIdentity {
  final String deviceId;
  final String deviceName;
  final String platform; // ANDROID | IOS
  const DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
  });
}
