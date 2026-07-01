import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/secure_storage.dart';
import 'biometric_models.dart';

/// Resolves a stable device id (a persisted random UUID), a human-readable
/// device name, and the platform string the backend expects (ANDROID / IOS).
///
/// The device id is our own persisted UUID rather than a hardware id so it stays
/// stable and carries no PII; the name/platform are for the Registered Devices list.
class DeviceInfoService {
  final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  Future<DeviceIdentity> resolve() async {
    final deviceId = await SecureStorage.readOrCreateDeviceId(_uuidV4);
    final name = await _deviceName();
    final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
    return DeviceIdentity(deviceId: deviceId, deviceName: name, platform: platform);
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
