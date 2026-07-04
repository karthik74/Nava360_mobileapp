import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/secure_storage.dart';
import '../auth_controller.dart';
import 'biometric_models.dart';
import 'biometric_repository.dart';
import 'biometric_service.dart';
import 'device_info_service.dart';

/// Observable biometric state for the UI (login button, settings toggle).
class BiometricState {
  final bool enabled; // an enrollment is stored on this device
  final BiometricAvailability availability;
  final String label; // "Fingerprint" | "Face ID" | "Biometric"
  final bool busy;

  const BiometricState({
    this.enabled = false,
    this.availability = BiometricAvailability.unavailable,
    this.label = 'Biometric',
    this.busy = false,
  });

  /// The device can actually perform a biometric check right now (Case A).
  bool get canUse => availability == BiometricAvailability.available;

  /// Show the "Login with …" button only when enrolled AND usable (Cases B/C hide it).
  bool get canOfferLogin => enabled && canUse;

  BiometricState copyWith({
    bool? enabled,
    BiometricAvailability? availability,
    String? label,
    bool? busy,
  }) =>
      BiometricState(
        enabled: enabled ?? this.enabled,
        availability: availability ?? this.availability,
        label: label ?? this.label,
        busy: busy ?? this.busy,
      );
}

/// Thrown by biometric operations with a user-friendly message.
class BiometricException implements Exception {
  final String message;
  BiometricException(this.message);
  @override
  String toString() => message;
}

class BiometricController extends StateNotifier<BiometricState> {
  BiometricController(this._ref, this._service, this._device, this._repo)
      : super(const BiometricState()) {
    refresh();
  }

  final Ref _ref;
  final BiometricService _service;
  final DeviceInfoService _device;
  final BiometricRepository _repo;

  /// Re-reads device capability + stored enrollment. Safe to call often.
  Future<void> refresh() async {
    final availability = await _service.availability();
    final enabled = await SecureStorage.readBiometricEnabled();
    final label = await _service.label();
    if (mounted) {
      state = state.copyWith(
          availability: availability, enabled: enabled, label: label);
    }
  }

  /// Enable biometric login for this device (called after the user opts in).
  /// Requires an active session. Verifies biometrics locally, then enrolls.
  /// Returns null on success, or an error message.
  Future<String?> enable() async {
    if (state.availability == BiometricAvailability.noHardware) {
      return "This device doesn't support biometric authentication.";
    }
    if (state.availability == BiometricAvailability.notEnrolled) {
      return 'To use biometric login, please add a fingerprint or Face ID in your device settings.';
    }
    final user = _ref.read(authControllerProvider).asData?.value;
    if (user == null) return 'Please sign in first.';

    state = state.copyWith(busy: true);
    try {
      final ok = await _service.authenticate('Verify to enable biometric login');
      if (!ok) return 'Biometric authentication failed.';

      final id = await _device.resolve();
      final res = await _repo.enable(
        deviceId: id.deviceId,
        deviceName: id.deviceName,
        platform: id.platform,
      );
      await SecureStorage.writeBiometricEnrollment(
        token: res.biometricToken,
        deviceId: res.deviceId,
        employeeId: user.employeeId,
        username: user.username,
        deviceLabel: id.deviceName,
      );
      state = state.copyWith(enabled: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not enable biometric login. Please try again.';
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Disable biometric login for this device: tell the backend, then wipe locally.
  Future<void> disable() async {
    state = state.copyWith(busy: true);
    try {
      final deviceId = await SecureStorage.readBiometricDeviceId();
      if (deviceId != null) {
        try {
          await _repo.disable(deviceId);
        } catch (_) {
          // Best-effort: even if the server call fails, remove the local secret.
        }
      }
      await SecureStorage.clearBiometric();
      state = state.copyWith(enabled: false);
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Full biometric login (device is signed out). Verifies locally, exchanges the
  /// stored credential for a fresh JWT, persists everything, and flips auth state.
  /// Returns null on success, or an error message. On a backend rejection the
  /// local enrollment is wiped so the user falls back to password login (spec §8).
  Future<String?> loginWithBiometric() async {
    if (!state.canUse) {
      return state.availability == BiometricAvailability.notEnrolled
          ? 'To use biometric login, please add a fingerprint or Face ID in your device settings.'
          : "This device doesn't support biometric authentication.";
    }
    final deviceId = await SecureStorage.readBiometricDeviceId();
    final token = await SecureStorage.readBiometricToken();
    if (deviceId == null || token == null) {
      await SecureStorage.clearBiometric();
      state = state.copyWith(enabled: false);
      return 'Biometric login has been disabled. Please login using your password.';
    }

    state = state.copyWith(busy: true);
    try {
      final ok = await _service.authenticate('Sign in with biometrics');
      if (!ok) return 'Biometric authentication failed.';

      final res = await _repo.biometricLogin(deviceId: deviceId, biometricToken: token);
      // Persist the new session + rotated credential, then sign in.
      await SecureStorage.writeToken(res.auth.token);
      await SecureStorage.writeUserJson(jsonEncode(res.auth.toJson()));
      await SecureStorage.updateBiometricToken(res.biometricToken);
      _ref.read(authControllerProvider.notifier).applySignedIn(res.auth);
      return null;
    } on ApiException catch (e) {
      // Enrollment is dead server-side (inactive / expired / revoked) → wipe local.
      await SecureStorage.clearBiometric();
      state = state.copyWith(enabled: false);
      return e.message;
    } catch (_) {
      return 'Biometric authentication failed. Please login using your password.';
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// List this user's registered devices for the Security screen.
  Future<List<RegisteredDevice>> listDevices() async {
    final deviceId = await SecureStorage.readBiometricDeviceId();
    return _repo.listDevices(currentDeviceId: deviceId);
  }

  /// Remove a specific device from the account (Registered Devices screen).
  Future<void> revokeDevice(String deviceId) async {
    await _repo.revokeDevice(deviceId);
    final current = await SecureStorage.readBiometricDeviceId();
    if (current == deviceId) {
      await SecureStorage.clearBiometric();
      state = state.copyWith(enabled: false);
    }
  }
}

final biometricControllerProvider =
    StateNotifierProvider<BiometricController, BiometricState>(
  (ref) => BiometricController(
    ref,
    ref.watch(biometricServiceProvider),
    ref.watch(deviceInfoServiceProvider),
    ref.watch(biometricRepositoryProvider),
  ),
);
