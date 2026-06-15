import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'app_updater.dart';
import 'app_version_models.dart';
import 'app_version_repository.dart';

/// Wraps the whole app. On `forceUpdate` it replaces the UI with a blocking
/// update screen; on `updateAvailable` it shows a one-time dismissible banner.
/// If the check fails or is still loading, the app renders normally.
///
/// The update progress is rendered as an overlay owned by this widget — NOT via
/// showDialog — because this gate sits above the app's Navigator (and replaces
/// it during a force-update), so a dialog would have no Navigator to attach to.
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  bool _softDismissed = false;

  // Update-flow state (drives the overlay).
  bool _updating = false;
  double _progress = 0;
  String _status = 'Starting download…';
  bool _failed = false;
  String? _error;
  String? _activeUrl;

  Future<void> _runUpdate(String? url) async {
    if (url == null || url.isEmpty) {
      setState(() {
        _updating = true;
        _failed = true;
        _error = 'No download link is configured. Please contact your administrator.';
        _activeUrl = null;
      });
      return;
    }
    // Non-APK / non-Android links just open externally (browser / store).
    if (!AppUpdater.canInstallInApp(url)) {
      try {
        await AppUpdater.openExternally(url);
      } catch (e) {
        setState(() {
          _updating = true;
          _failed = true;
          _error = e.toString();
          _activeUrl = url;
        });
      }
      return;
    }
    setState(() {
      _updating = true;
      _failed = false;
      _error = null;
      _progress = 0;
      _status = 'Starting download…';
      _activeUrl = url;
    });
    try {
      await AppUpdater.downloadAndInstall(
        url,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _status = 'Downloading… ${(p * 100).round()}%';
          });
        },
        onInstalling: () {
          if (mounted) setState(() => _status = 'Opening installer…');
        },
      );
      if (mounted) setState(() => _updating = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _error = e.toString();
          _status = 'Update failed';
        });
      }
    }
  }

  void _dismissOverlay() {
    setState(() {
      _updating = false;
      _failed = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final check = ref.watch(appVersionCheckProvider).valueOrNull;

    Widget content;
    if (check == null) {
      content = widget.child;
    } else if (check.forceUpdate) {
      content = _ForceUpdateScreen(
        check: check,
        onUpdate: () => _runUpdate(check.downloadUrl),
      );
    } else {
      content = Stack(
        children: [
          widget.child,
          if (check.updateAvailable && !_softDismissed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SoftUpdateBanner(
                check: check,
                onDismiss: () => setState(() => _softDismissed = true),
                onUpdate: () => _runUpdate(check.downloadUrl),
              ),
            ),
        ],
      );
    }

    return Stack(
      children: [
        content,
        if (_updating)
          Positioned.fill(
            child: _UpdateOverlay(
              progress: _progress,
              status: _status,
              failed: _failed,
              error: _error,
              onRetry: _activeUrl == null ? null : () => _runUpdate(_activeUrl),
              onOpenBrowser: _activeUrl == null
                  ? null
                  : () {
                      AppUpdater.openExternally(_activeUrl!).catchError((_) {});
                      _dismissOverlay();
                    },
              onClose: _dismissOverlay,
            ),
          ),
      ],
    );
  }
}

/// Full-screen progress / error overlay for the in-app update.
class _UpdateOverlay extends StatelessWidget {
  const _UpdateOverlay({
    required this.progress,
    required this.status,
    required this.failed,
    required this.error,
    required this.onRetry,
    required this.onOpenBrowser,
    required this.onClose,
  });
  final double progress;
  final String status;
  final bool failed;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenBrowser;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                failed ? 'Update failed' : 'Updating Nava360',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 14),
              if (!failed) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress,
                    minHeight: 8,
                    backgroundColor: AppColors.hairline,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 12),
                Text(status,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
              ] else ...[
                Text(
                  error ?? 'Something went wrong while downloading the update.',
                  style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: onClose, child: const Text('Close')),
                    if (onOpenBrowser != null)
                      TextButton(
                        onPressed: onOpenBrowser,
                        child: const Text('Open in browser'),
                      ),
                    if (onRetry != null)
                      FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftUpdateBanner extends StatelessWidget {
  const _SoftUpdateBanner({
    required this.check,
    required this.onDismiss,
    required this.onUpdate,
  });
  final AppVersionCheck check;
  final VoidCallback onDismiss;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, mq.padding.bottom + 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: AppColors.primary.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.system_update_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Update available',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      'Version ${check.latestVersionName} is ready to install.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: onUpdate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForceUpdateScreen extends StatelessWidget {
  const _ForceUpdateScreen({required this.check, required this.onUpdate});
  final AppVersionCheck check;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.system_update_rounded,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A newer version of the app is required to continue. '
                  'Please update to version ${check.latestVersionName} to keep using Nava360.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkSoft,
                    height: 1.45,
                  ),
                ),
                if (check.releaseNotes != null &&
                    check.releaseNotes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.muted.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "WHAT'S NEW",
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          check.releaseNotes!.trim(),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.inkSoft,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onUpdate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text(
                      'Update now',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
