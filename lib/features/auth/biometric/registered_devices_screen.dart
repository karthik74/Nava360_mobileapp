import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(d.currentDevice ? 'Remove this device?' : 'Remove device?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text(
          d.currentDevice
              ? 'Biometric login will be turned off on this device. You can re-enable it anytime.'
              : 'Biometric login will be turned off on "${d.deviceName ?? 'this device'}".',
          style: const TextStyle(color: AppColors.inkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Registered devices'),
      ),
      body: GlassBackdrop(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder<List<RegisteredDevice>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _Message(
                  padTop: mq.padding.top,
                  icon: Icons.error_outline_rounded,
                  text: 'Could not load devices.\n${snap.error}',
                );
              }
              final devices = snap.data ?? const [];
              if (devices.isEmpty) {
                return _Message(
                  padTop: mq.padding.top,
                  icon: Icons.devices_other_rounded,
                  text: 'No devices are registered for biometric login yet.',
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(
                    16, mq.padding.top + kToolbarHeight + 8, 16, 24),
                itemCount: devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    _DeviceCard(device: devices[i], onRemove: () => _remove(devices[i])),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onRemove});
  final RegisteredDevice device;
  final VoidCallback onRemove;

  String get _platformIcon => device.platform == 'IOS' ? 'iOS' : 'Android';

  @override
  Widget build(BuildContext context) {
    final last = device.lastLoginAt;
    final lastLogin = last == null
        ? 'Not used yet'
        : 'Last login ${DateFormat('d MMM yyyy, h:mm a').format(last.toLocal())}';
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.22)),
            ),
            alignment: Alignment.center,
            child: Icon(
              device.platform == 'IOS'
                  ? Icons.phone_iphone_rounded
                  : Icons.phone_android_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.deviceName ?? 'Unknown device',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (device.currentDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: const Text(
                          'This device',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('$_platformIcon · $lastLogin',
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.danger, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.padTop, required this.icon, required this.text});
  final double padTop;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(24, padTop + kToolbarHeight + 60, 24, 24),
      children: [
        Icon(icon, size: 46, color: AppColors.muted.withOpacity(0.6)),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 14)),
      ],
    );
  }
}
