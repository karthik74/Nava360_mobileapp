import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/secure_storage.dart';
import 'biometric_models.dart';

/// Resolves the two device identifiers the app uses, a human-readable device
/// name, and the platform string the backend expects (ANDROID / IOS).
///
/// Two ids, deliberately:
///  * [DeviceIdentity.deviceId]   — our own persisted UUID. Keys biometric
///    enrollment. Per-install: reinstalling produces a new one.
///  * [DeviceIdentity.hardwareId] — Android SSAID / iOS identifierForVendor.
///    Keys the per-shift device lock, so it must survive a reinstall; otherwise
///    every employee who reinstalled would be locked out until HR intervened.
///
/// A real IMEI is not obtainable: Android 10+ restricts `getImei()` to system /
/// carrier apps holding READ_PRIVILEGED_PHONE_STATE, iOS never exposed it, and
/// Play policy treats it as a restricted identifier. SSAID is the closest
/// compliant equivalent and needs no permission.
class DeviceInfoService {
  static const MethodChannel _identityChannel = MethodChannel('app/device_identity');

  final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  Future<DeviceIdentity> resolve() async {
    final deviceId = await SecureStorage.readOrCreateDeviceId(_uuidV4);
    final name = await _deviceName();
    final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
    final hardwareId = await _hardwareId() ?? deviceId;
    return DeviceIdentity(
      deviceId: deviceId,
      hardwareId: hardwareId,
      deviceName: name,
      platform: platform,
    );
  }

  /// SSAID on Android, identifierForVendor on iOS. Null when unavailable — the
  /// caller falls back to the persisted UUID rather than failing the login.
  Future<String?> _hardwareId() async {
    try {
      if (Platform.isIOS) {
        final ios = await _plugin.iosInfo;
        final idfv = ios.identifierForVendor;
        return (idfv == null || idfv.isEmpty) ? null : idfv;
      }
      return await _identityChannel.invokeMethod<String>('getHardwareId');
    } catch (_) {
      return null;
    }
  }

  Future<String> _deviceName() async {
    try {
      if (Platform.isIOS) {
        final ios = await _plugin.iosInfo;
        return '${ios.name} (${ios.model})';
      }
      final android = await _plugin.androidInfo;
      final maker = _capitalize(android.manufacturer);
      return '$maker ${android.model} (Android ${android.version.release})';
    } catch (_) {
      return Platform.isIOS ? 'iPhone' : 'Android device';
    }
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// RFC-4122 v4 UUID from a cryptographically secure RNG (no extra package).
  static String _uuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).toList();
    return '${h[0]}${h[1]}${h[2]}${h[3]}-${h[4]}${h[5]}-${h[6]}${h[7]}-'
        '${h[8]}${h[9]}-${h[10]}${h[11]}${h[12]}${h[13]}${h[14]}${h[15]}';
  }
}

final deviceInfoServiceProvider = Provider<DeviceInfoService>((_) => DeviceInfoService());
