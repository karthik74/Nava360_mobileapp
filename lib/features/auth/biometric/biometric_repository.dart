import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import 'biometric_models.dart';

/// API layer for the mobile biometric endpoints (`/api/auth/mobile/**`).
class BiometricRepository {
  BiometricRepository(this._api);
  final ApiClient _api;

  /// Enroll the current (authenticated) device. Returns the raw opaque credential.
  Future<BiometricEnrollResult> enable({
    required String deviceId,
    required String deviceName,
    required String platform,
  }) {
    return _api.post<BiometricEnrollResult>(
      '/api/auth/mobile/enable-biometric',
      body: {'deviceId': deviceId, 'deviceName': deviceName, 'platform': platform},
      parse: (d) => BiometricEnrollResult.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Public exchange of a stored credential (+ device id) for a fresh JWT.
  Future<BiometricLoginResult> biometricLogin({
    required String deviceId,
    required String biometricToken,
  }) {
    return _api.post<BiometricLoginResult>(
      '/api/auth/mobile/biometric-login',
      body: {'deviceId': deviceId, 'biometricToken': biometricToken},
      parse: (d) => BiometricLoginResult.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Remove the enrollment for the current device.
  Future<void> disable(String deviceId) {
    return _api.post<void>(
      '/api/auth/mobile/disable-biometric',
      body: {'deviceId': deviceId},
      parse: (_) {},
    );
  }

  /// Remove a specific registered device (may be another device).
  Future<void> revokeDevice(String deviceId) {
    return _api.post<void>(
      '/api/auth/mobile/revoke-device',
      body: {'deviceId': deviceId},
      parse: (_) {},
    );
  }

  /// End the current session; optionally tear down this device's enrollment too.
  Future<void> logout({String? deviceId, bool disableBiometric = false}) {
    return _api.post<void>(
      '/api/auth/mobile/logout',
      body: {'deviceId': deviceId, 'disableBiometric': disableBiometric},
      parse: (_) {},
    );
  }

  /// List the caller's registered devices (flagging the current one).
  Future<List<RegisteredDevice>> listDevices({String? currentDeviceId}) {
    return _api.get<List<RegisteredDevice>>(
      '/api/auth/mobile/devices',
      query: currentDeviceId == null ? null : {'deviceId': currentDeviceId},
      parse: (d) => (d as List)
          .map((e) => RegisteredDevice.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

final biometricRepositoryProvider = Provider<BiometricRepository>(
  (ref) => BiometricRepository(ref.watch(apiClientProvider)),
);
