import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Why biometric login is / isn't offered on this device. Maps directly to the
/// spec's Cases B (noHardware) and C (notEnrolled).
enum BiometricAvailability {
  /// Hardware present and at least one fingerprint / face is enrolled.
  available,

  /// No biometric hardware — hide the biometric button (Case B).
  noHardware,

  /// Hardware present but nothing enrolled — prompt the user to add one (Case C).
  notEnrolled,

  /// Could not be determined (permission / platform error) — treat as unusable.
  unavailable,
}

/// Thin wrapper over `local_auth`. Biometric data never leaves the OS — this only
/// asks the platform to verify and returns pass/fail. No secrets are handled here.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<BiometricAvailability> availability() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported && !canCheck) return BiometricAvailability.noHardware;
      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) return BiometricAvailability.notEnrolled;
      return BiometricAvailability.available;
    } catch (_) {
      return BiometricAvailability.unavailable;
    }
  }

  /// A user-facing label for the enrolled modality: "Face ID" vs "Fingerprint".
  Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong) ||
          types.contains(BiometricType.weak)) {
        return 'Fingerprint';
      }
      return 'Biometric';
    } catch (_) {
      return 'Biometric';
    }
  }

  /// Prompts the OS biometric sheet. Returns true only on a successful match.
  /// [biometricOnly] keeps device PIN/pattern out of the flow per the spec.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricServiceProvider = Provider<BiometricService>((_) => BiometricService());
