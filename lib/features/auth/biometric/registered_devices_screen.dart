import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/pro_ui.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import 'biometric_controller.dart';
import 'biometric_models.dart';

/// Settings → Security → Registered Devices. Lists the account's biometric
/// enrollments, flags the current device, and allows removing one.
class RegisteredDevicesScreen extends ConsumerStatefulWidget {
  const RegisteredDevicesScreen({super.key});

  @override
  ConsumerState<RegisteredDevicesScreen> createState() =>
      _RegisteredDevicesScreenState();
}

class _RegisteredDevicesScreenState
    extends ConsumerState<RegisteredDevicesScreen> {
  late Future<List<RegisteredDevice>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(biometricControllerProvider.notifier).listDevices();
  }

  void _reload() {
    setState(() {
      _future = ref.read(biometricControllerProvider.notifier).listDevices();
    });
  }

  Future<void> _remove(RegisteredDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(d.currentDevice ? 'Remove this device?' : 'Remove device?'),
        content: Text(
          d.currentDevice
              ? 'Biometric login will be turned off on this device. You can re-enable it anytime.'
              : 'Biometric login will be turned off on "${d.deviceName ?? 'this device'}".',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerTint,
              foregroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(biometricControllerProvider.notifier).revokeDevice(d.deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Device removed')));
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove device: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: FutureBuilder<List<RegisteredDevice>>(
        future: _future,
        builder: (context, snap) {
          final waiting = snap.connectionState == ConnectionState.waiting;
          final devices = snap.data ?? const <RegisteredDevice>[];
          final used = devices.where((d) => d.lastLoginAt != null).length;
          final ready = !waiting && !snap.hasError;

          final hero = ProHero(
            title: 'Registered devices',
            subtitle: !ready
                ? 'Devices registered for biometric login'
                : '${devices.length} ${devices.length == 1 ? 'device' : 'devices'} registered for biometric login',
            children: [
              ProHeroStats(
                stats: [
                  ProStat(
                    label: 'Registered',
                    value: ready ? '${devices.length}' : '–',
                    sub: 'all devices',
                    dot: const Color(0xFF6CC3D5),
                  ),
                  ProStat(
                    label: 'Used',
                    value: ready ? '$used' : '–',
                    sub: 'signed in',
                    dot: AppColors.live,
                  ),
                  ProStat(
                    label: 'Not used',
                    value: ready ? '${devices.length - used}' : '–',
                    sub: 'yet to sign in',
                    dot: const Color(0xFFB3C0C3),
                  ),
                ],
              ),
            ],
          );

          final List<Widget> body;
          if (waiting) {
            body = const [AppLoadingBlock(height: 72), AppLoadingBlock(height: 72)];
          } else if (snap.hasError) {
            body = [
              AppErrorPanel(
                message: 'Could not load devices.\n${snap.error}',
                onRetry: _reload,
              ),
            ];
          } else if (devices.isEmpty) {
            body = const [
              ProEmpty(
                icon: Icons.devices_other_rounded,
                title: 'No registered devices',
                message: 'No devices are registered for biometric login yet.',
              ),
            ];
          } else {
            body = [
              ProSectionHeader(
                title: 'Devices · ${devices.length}',
                small: true,
              ),
              ProListGroup(
                children: [
                  for (final d in devices)
                    _DeviceRow(device: d, onRemove: () => _remove(d)),
                ],
              ),
            ];
          }

          return ProPage(
            onRefresh: () async => _reload(),
            hero: hero,
            children: [
              ...body,
              const ProNote(
                'Removing a device turns off biometric login on it. You can '
                'turn it on again from My profile → Security.',
                tone: ProNoteTone.info,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onRemove});
  final RegisteredDevice device;
  final VoidCallback onRemove;

  String get _platformIcon => device.platform == 'IOS' ? 'iOS' : 'Android';

  @override
  Widget build(BuildContext context) {
    final last = device.lastLoginAt;
    final lastLogin = last == null
        ? 'Not used yet'
        : 'Last login ${DateFormat('d MMM yyyy, h:mm a').format(last.toLocal())}';
    return ProListRow(
      leading: ProIconWell(
        icon: device.platform == 'IOS'
            ? Icons.phone_iphone_rounded
            : Icons.phone_android_rounded,
        color: device.currentDevice ? AppColors.success : AppColors.primary,
      ),
      title: device.deviceName ?? 'Unknown device',
      subtitle: '$_platformIcon · $lastLogin',
      pill: device.currentDevice ? ProPill.ok('This device') : null,
      chevron: false,
      trailing: IconButton(
        tooltip: 'Remove',
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline_rounded,
            color: AppColors.danger, size: 20),
      ),
    );
  }
}
