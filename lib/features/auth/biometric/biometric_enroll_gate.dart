import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../auth_controller.dart';
import 'biometric_controller.dart';

/// One-shot flag set by the login screen right after a successful PASSWORD login,
/// so the enroll gate knows to offer biometric enrollment on the next frame.
final justPasswordLoggedInProvider = StateProvider<bool>((_) => false);

/// After a fresh password login, offers "Enable Biometric Login?" exactly once —
/// only when the device supports biometrics and no enrollment exists yet.
/// Renders its [child] untouched at all other times, so existing flows are intact.
class BiometricEnrollGate extends ConsumerStatefulWidget {
  const BiometricEnrollGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<BiometricEnrollGate> createState() => _BiometricEnrollGateState();
}

class _BiometricEnrollGateState extends ConsumerState<BiometricEnrollGate> {
  bool _handling = false;

  @override
  Widget build(BuildContext context) {
    final justLoggedIn = ref.watch(justPasswordLoggedInProvider);
    final signedIn = ref.watch(authControllerProvider).asData?.value != null;

    if (justLoggedIn && signedIn && !_handling) {
      _handling = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
    }
    return widget.child;
  }

  Future<void> _maybePrompt() async {
    // Consume the flag so this never re-fires for the same login.
    ref.read(justPasswordLoggedInProvider.notifier).state = false;

    final ctrl = ref.read(biometricControllerProvider.notifier);
    await ctrl.refresh();
    final bio = ref.read(biometricControllerProvider);

    // Nothing to offer: no hardware, nothing enrolled, or already enabled.
    if (!bio.canUse || bio.enabled) {
      _handling = false;
      return;
    }
    if (!mounted) return;

    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable Biometric Login?'),
        content: Text(
          'Use ${bio.label} to sign in faster next time. '
          'You can turn this off anytime in Settings → Security.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (enable == true) {
      final err = await ctrl.enable();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? '${bio.label} login enabled'),
          backgroundColor: err == null ? AppColors.success : AppColors.danger,
        ));
      }
    }
    _handling = false;
  }
}
