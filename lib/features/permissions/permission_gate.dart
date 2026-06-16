import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../auth/auth_controller.dart';

/// Hard permission wall that gates the app once the user is signed in.
///
/// While signed out (login / welcome / reset flows) it's a pass-through. As soon
/// as the user is authenticated the app is unusable until every required
/// permission is granted:
///   • Location set to "Allow all the time" (background) + location services ON
///   • Battery optimisation exemption (Android only)
///   • Background activity allowed — not "Restricted" (Android only)
///   • Notifications
///
/// Because background-location and battery-optimisation can only be granted from
/// the system Settings screen (not an in-app dialog on modern Android), the gate
/// re-checks every time the app returns to the foreground — so the wall clears
/// the instant the user comes back from Settings with everything enabled.
class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

enum _PermKind { notifications, locationAlways, battery, backgroundActivity }

class _PermissionGateState extends ConsumerState<PermissionGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _requesting = false;

  bool _servicesOn = true;
  bool _notifOk = false;
  bool _locOk = false;
  bool _batteryOk = false;
  bool _bgActivityOk = false;

  // The gate only applies on the mobile targets that have these permissions;
  // on desktop/web it's a pass-through (those plugins would otherwise throw).
  static final bool _gated = Platform.isAndroid || Platform.isIOS;

  static const MethodChannel _batteryChannel = MethodChannel('app/battery');

  List<_PermKind> get _required => [
        _PermKind.notifications,
        _PermKind.locationAlways,
        if (Platform.isAndroid) _PermKind.battery,
        if (Platform.isAndroid) _PermKind.backgroundActivity,
      ];

  bool _isOk(_PermKind k) {
    switch (k) {
      case _PermKind.notifications:
        return _notifOk;
      case _PermKind.locationAlways:
        return _locOk;
      case _PermKind.battery:
        return _batteryOk;
      case _PermKind.backgroundActivity:
        return _bgActivityOk;
    }
  }

  bool get _allGranted => _required.every(_isOk);

  @override
  void initState() {
    super.initState();
    if (!_gated) {
      _checking = false;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user (likely) toggled something in system Settings.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    bool servicesOn;
    try {
      servicesOn = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      servicesOn = false;
    }
    final locAlways = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final battery = Platform.isAndroid
        ? await Permission.ignoreBatteryOptimizations.isGranted
        : true;
    final bgRestricted =
        Platform.isAndroid ? await _isBackgroundRestricted() : false;

    if (!mounted) return;
    setState(() {
      _servicesOn = servicesOn;
      // "Allow all the time" is meaningless without location services on.
      _locOk = servicesOn && locAlways;
      _notifOk = notif;
      _batteryOk = battery;
      _bgActivityOk = !bgRestricted;
      _checking = false;
    });
  }

  /// Whether the OS has put the app under "Restricted" background usage. On any
  /// error (or pre-Android 9) we treat it as not restricted so we never lock the
  /// user out over a flag we couldn't read.
  Future<bool> _isBackgroundRestricted() async {
    try {
      final v =
          await _batteryChannel.invokeMethod<bool>('isBackgroundRestricted');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// One-tap "Enable all" — requests every missing permission in the order the
  /// OS expects (notifications, foreground location, then background), falling
  /// back to the Settings screen where an in-app dialog isn't allowed.
  Future<void> _requestAll() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      if (!_notifOk) await Permission.notification.request();
      if (!_locOk) await _requestLocationAlways();
      if (Platform.isAndroid && !_batteryOk) {
        await Permission.ignoreBatteryOptimizations.request();
      }
      // Background-restricted can only be cleared from Settings. Setting the app
      // to "Unrestricted" above usually clears it too; if it's still restricted,
      // send the user to Settings to flip "Allow background activity".
      if (Platform.isAndroid &&
          !_bgActivityOk &&
          await _isBackgroundRestricted()) {
        await openAppSettings();
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
      await _refresh();
    }
  }

  Future<void> _requestLocationAlways() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return;
    }
    // Background location requires foreground location first.
    final whenInUse = await Permission.locationWhenInUse.request();
    if (!whenInUse.isGranted) {
      await openAppSettings();
      return;
    }
    final always = await Permission.locationAlways.request();
    if (!always.isGranted) {
      // Android 11+ won't grant "Allow all the time" from a dialog — send the
      // user to Settings to flip it manually.
      await openAppSettings();
    }
  }

  Future<void> _fix(_PermKind kind) async {
    switch (kind) {
      case _PermKind.notifications:
        final r = await Permission.notification.request();
        if (!r.isGranted) await openAppSettings();
        break;
      case _PermKind.locationAlways:
        await _requestLocationAlways();
        break;
      case _PermKind.battery:
        final r = await Permission.ignoreBatteryOptimizations.request();
        if (!r.isGranted) await openAppSettings();
        break;
      case _PermKind.backgroundActivity:
        // No request API — the user must flip "Allow background activity" in the
        // app's battery settings.
        await openAppSettings();
        break;
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_gated) return widget.child;

    // Re-check the moment the user signs in (the logged-out → logged-in
    // transition doesn't fire an app-resume).
    ref.listen(authUserProvider, (prev, next) {
      if (prev == null && next != null) _refresh();
    });

    // Pass through while signed out — login/welcome/reset stay reachable.
    if (ref.watch(authUserProvider) == null) return widget.child;

    if (_checking) {
      return const Material(
        color: AppColors.bg,
        child: Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
      );
    }
    if (_allGranted) return widget.child;

    return _PermissionWall(
      required: _required,
      isOk: _isOk,
      servicesOn: _servicesOn,
      requesting: _requesting,
      onEnableAll: _requestAll,
      onFix: _fix,
      onRefresh: _refresh,
    );
  }
}

class _PermissionWall extends StatelessWidget {
  const _PermissionWall({
    required this.required,
    required this.isOk,
    required this.servicesOn,
    required this.requesting,
    required this.onEnableAll,
    required this.onFix,
    required this.onRefresh,
  });

  final List<_PermKind> required;
  final bool Function(_PermKind) isOk;
  final bool servicesOn;
  final bool requesting;
  final VoidCallback onEnableAll;
  final Future<void> Function(_PermKind) onFix;
  final Future<void> Function() onRefresh;

  _PermInfo _info(_PermKind k) {
    switch (k) {
      case _PermKind.notifications:
        return const _PermInfo(
          icon: Icons.notifications_active_rounded,
          title: 'Notifications',
          subtitle: 'Required for attendance alerts and messages.',
        );
      case _PermKind.locationAlways:
        return _PermInfo(
          icon: Icons.my_location_rounded,
          title: 'Location · Allow all the time',
          subtitle: servicesOn
              ? 'Set location access to “Allow all the time” so attendance '
                  'tracking works in the background.'
              : 'Turn on location services, then set access to “Allow all the '
                  'time”.',
        );
      case _PermKind.battery:
        return const _PermInfo(
          icon: Icons.battery_charging_full_rounded,
          title: 'Ignore battery optimisation',
          subtitle: 'Keeps location tracking alive while the app is in the '
              'background.',
        );
      case _PermKind.backgroundActivity:
        return const _PermInfo(
          icon: Icons.battery_saver_rounded,
          title: 'Allow background activity',
          subtitle: 'Set battery usage to “Unrestricted” so the OS doesn’t kill '
              'tracking in the background.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 28, 24, mq.padding.bottom + 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
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
                    child: const Icon(Icons.shield_moon_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Permissions required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nava360 needs these permissions to track attendance '
                    'reliably. Please enable all of them to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.inkSoft,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  for (final k in required) ...[
                    _PermissionRow(
                      info: _info(k),
                      granted: isOk(k),
                      onFix: () => onFix(k),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: requesting ? null : onEnableAll,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: requesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(
                        requesting ? 'Requesting…' : 'Enable all',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => onRefresh(),
                    child: const Text("I've enabled them — re-check"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermInfo {
  const _PermInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.info,
    required this.granted,
    required this.onFix,
  });
  final _PermInfo info;
  final bool granted;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final tone = granted ? AppColors.success : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: tone.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(info.icon, color: tone, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (granted)
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 24)
          else
            TextButton(
              onPressed: onFix,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
              ),
              child: const Text(
                'Enable',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
