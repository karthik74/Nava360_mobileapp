import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import 'app_version_models.dart';
import 'app_version_repository.dart';

Future<void> _openDownload(String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Wraps the whole app. On `forceUpdate` it replaces the UI with a blocking
/// update screen; on `updateAvailable` it shows a one-time dismissible banner.
/// If the check fails or is still loading, the app renders normally.
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  bool _softDismissed = false;

  @override
  Widget build(BuildContext context) {
    final check = ref.watch(appVersionCheckProvider).valueOrNull;

    if (check == null) return widget.child;

    if (check.forceUpdate) {
      return _ForceUpdateScreen(check: check);
    }

    return Stack(
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
            ),
          ),
      ],
    );
  }
}

class _SoftUpdateBanner extends StatelessWidget {
  const _SoftUpdateBanner({required this.check, required this.onDismiss});
  final AppVersionCheck check;
  final VoidCallback onDismiss;

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
                onPressed: () => _openDownload(check.downloadUrl),
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
  const _ForceUpdateScreen({required this.check});
  final AppVersionCheck check;

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
                    onPressed: () => _openDownload(check.downloadUrl),
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
