import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// Drives Google Play's native in-app update flow (Android only). It checks for
/// an update once on startup and:
///   • runs a blocking full-screen *immediate* update when Play marks one as
///     high-priority (`immediateUpdateAllowed`), otherwise
///   • downloads a *flexible* update in the background and offers an "Install"
///     SnackBar once it's ready.
///
/// This is the Play-compliant replacement for the old self-hosted APK updater —
/// the OS owns the download and install, so no extra permissions are needed.
/// On iOS / non-Android the check is skipped and the child renders unchanged.
class InAppUpdateGate extends StatefulWidget {
  const InAppUpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<InAppUpdateGate> createState() => _InAppUpdateGateState();
}

class _InAppUpdateGateState extends State<InAppUpdateGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    // Defer until the first frame so a ScaffoldMessenger is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_checked || !Platform.isAndroid) return;
    _checked = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }
      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        await _runFlexibleUpdate();
      }
    } catch (e) {
      // A failed check must never block the app from opening.
      debugPrint('In-app update check failed: $e');
    }
  }

  Future<void> _runFlexibleUpdate() async {
    final result = await InAppUpdate.startFlexibleUpdate();
    if (result != AppUpdateResult.success || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(days: 1),
          content: const Text('An update has been downloaded.'),
          action: SnackBarAction(
            label: 'Install',
            onPressed: () => InAppUpdate.completeFlexibleUpdate(),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
