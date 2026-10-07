import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/branding.dart';
import '../../core/navigation/mobile_menu_config.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../announcements/announcements_models.dart';
import '../announcements/announcements_repository.dart';
import '../attendance/attendance_models.dart';
import '../attendance/attendance_repository.dart';
import '../attendance/location_tracker.dart';
import '../auth/auth_controller.dart';
import '../leaves/leave_models.dart';
import '../leaves/leave_repository.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';

final _dashAttendanceProvider =
    FutureProvider.autoDispose<List<AttendanceRecord>>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return [];
  final now = DateTime.now();
  final from = DateFormat('yyyy-MM-01').format(now);
  final last = DateTime(now.year, now.month + 1, 0);
  final to = DateFormat('yyyy-MM-dd').format(last);
  return ref
      .watch(attendanceRepositoryProvider)
      .listForEmployee(user!.employeeId!, from: from, to: to);
});

final _dashLeavesProvider =
    FutureProvider.autoDispose<List<LeaveRequest>>((ref) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref.watch(leaveRepositoryProvider).listForEmployee(user!.employeeId!);
});

final _dashTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref.watch(taskRepositoryProvider).listForEmployee(user!.employeeId!);
});

final _dashTeamLeavesProvider =
    FutureProvider.autoDispose<List<LeaveRequest>>((ref) {
  final user = ref.watch(authUserProvider);
  final isManager = user?.hasRole(const {'ADMIN', 'HR'}) ?? false;
  if (!isManager) return Future.value([]);
  return ref.watch(leaveRepositoryProvider).listForTeam();
});

/// Reverse-geocodes a check-in coordinate into a short, human place label
/// (e.g. "Madhapur, Hyderabad"). Falls back to the raw coordinates when the
/// device has no geocoder / is offline. Keyed by the coordinate so the lookup
/// is cached per location.
final _checkInPlaceProvider = FutureProvider.autoDispose
    .family<String, ({double lat, double lng})>((ref, c) async {
  String coords() =>
      '${c.lat.toStringAsFixed(4)}, ${c.lng.toStringAsFixed(4)}';
  try {
    final marks = await placemarkFromCoordinates(c.lat, c.lng);
    if (marks.isNotEmpty) {
      final p = marks.first;
      final parts = <String>[
        for (final s in [p.subLocality, p.locality, p.administrativeArea])
          if (s != null && s.trim().isNotEmpty) s.trim(),
      ];
      if (parts.isNotEmpty) return parts.take(2).join(', ');
    }
  } catch (_) {/* no geocoder / offline → fall back to coordinates */}
  return coords();
});

/// Hero quick actions: HRMS menu keys (in priority order) → short label. Only
/// entries the user can see in the HRMS hub are shown (max 4).
const Map<String, String> _kQuickActionKeys = {
  'hrms.leaves': 'Leaves',
  'hrms.tasks': 'Tasks',
  'hrms.travelClaims': 'Claims',
  'hrms.helpdesk': 'Helpdesk',
  'hrms.announcements': 'Notices',
  'hrms.policies': 'Policies',
  'hrms.profile': 'Profile',
};

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _attendanceActionBusy = false;
  bool _batteryPromptedThisSession = false;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat.jm().format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  String _fmtDuration(double? hours) {
    if (hours == null) return '—';
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String _fmtTimer(Duration? duration) {
    if (duration == null || duration.isNegative) return '00:00:00';
    final total = duration.inSeconds;
    final hh = (total ~/ 3600).toString().padLeft(2, '0');
    final mm = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Duration? _workDuration(AttendanceRecord? rec) {
    if (rec?.checkIn == null) return null;
    final inTime = DateTime.tryParse(rec!.checkIn!);
    if (inTime == null) return null;
    if (rec.checkOut != null) {
      final out = DateTime.tryParse(rec.checkOut!);
      if (out != null) return out.difference(inTime);
    }
    return _now.difference(inTime);
  }

  String _humanLeaveType(String t) {
    final s = t.toLowerCase().replaceAll('_', ' ');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  Future<void> _runAttendanceAction({
    required bool hasCheckedIn,
    required bool hasCheckedOut,
  }) async {
    if (_attendanceActionBusy) return;
    if (hasCheckedOut) {
      context.go('/attendance');
      return;
    }

    // Confirm the punch — same pattern for check-in and check-out.
    final confirmed = await _confirmPunch(isCheckOut: hasCheckedIn);
    if (!confirmed || !mounted) return;

    final employeeId = ref.read(authUserProvider)?.employeeId;
    if (employeeId == null) {
      _showSnack('Employee profile is missing. Please sign in again.');
      return;
    }

    setState(() => _attendanceActionBusy = true);
    try {
      if (hasCheckedIn) {
        final locationError = await _locationBlocker();
        if (locationError != null) {
          _showSnack(locationError);
          return;
        }
        final position = await _tryCurrentPosition();
        await ref.read(attendanceRepositoryProvider).checkOut(
              employeeId,
              latitude: position?.latitude,
              longitude: position?.longitude,
            );
        await ref.read(locationTrackerProvider.notifier).stop();
        _showSnack('Checked out successfully.');
      } else {
        // Gate: any published announcement that requires acknowledgement and is
        // still unacknowledged must be acknowledged before the employee can
        // check in. Blocks here and sends them to the Announcements screen.
        final pending = await _pendingMandatoryAcks();
        if (pending.isNotEmpty) {
          if (!mounted) return;
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Acknowledgement required'),
              content: Text(
                pending.length == 1
                    ? 'You have 1 announcement that must be acknowledged before you can check in.'
                    : 'You have ${pending.length} announcements that must be acknowledged before you can check in.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Review & acknowledge'),
                ),
              ],
            ),
          );
          if (go == true && mounted) context.push('/announcements');
          return; // check-in stays blocked until they acknowledge
        }

        await ref.read(locationTrackerProvider.notifier).start(employeeId);
        final tracker = ref.read(locationTrackerProvider);
        if (!tracker.active) {
          _showSnack(
            tracker.lastError ?? 'Location permission is required to check in.',
          );
          return;
        }

        final position = await _tryCurrentPosition();
        if (position == null) {
          await ref
              .read(locationTrackerProvider.notifier)
              .stop(flushBuffer: false);
          _showSnack(
            'Could not get your location. Move to an open area with a clear sky '
            'view and try again.',
          );
          return;
        }
        try {
          await ref.read(attendanceRepositoryProvider).checkIn(
                employeeId,
                latitude: position.latitude,
                longitude: position.longitude,
              );
          _showSnack('Checked in successfully.');
          // Ask to lift battery restrictions so background tracking stays reliable.
          await _ensureBatteryUnrestricted();
        } catch (_) {
          await ref
              .read(locationTrackerProvider.notifier)
              .stop(flushBuffer: false);
          rethrow;
        }
      }

      ref.invalidate(_dashAttendanceProvider);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _attendanceActionBusy = false);
    }
  }

  /// Published announcements addressed to this employee that REQUIRE
  /// acknowledgement and are still unacknowledged (and not expired) — these must
  /// be acknowledged before checking in. Fails open on a network error so a
  /// transient issue never traps the employee out of attendance.
  Future<List<MyAnnouncement>> _pendingMandatoryAcks() async {
    try {
      final all =
          await ref.read(announcementsRepositoryProvider).getMyAnnouncements();
      final now = DateTime.now();
      return all
          .where((a) =>
              a.requiresAcknowledgement &&
              !a.acknowledged &&
              (a.expiryDatetime == null || a.expiryDatetime!.isAfter(now)))
          .toList();
    } catch (_) {
      return const <MyAnnouncement>[];
    }
  }

  /// Returns a user-facing error string if location is unavailable for an
  /// attendance punch (services off, or permission denied/revoked), or `null`
  /// when location is ready. Used to gate check-out the same way check-in is
  /// gated through the tracker — so a punch is never recorded without location.
  Future<String?> _locationBlocker() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Turn on location services to check out.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return 'Location permission is required to check out. '
            'Enable it in app settings.';
      }
      return null;
    } catch (_) {
      return 'Could not verify location permission. Please try again.';
    }
  }

  /// Best-effort current position with fallbacks so a slow GPS fix doesn't
  /// record a check-in without coordinates:
  ///   1) a fresh high-accuracy fix (12s)
  ///   2) the last known position (instant)
  ///   3) a fresh medium-accuracy fix with a longer timeout (20s)
  Future<Position?> _tryCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
    } catch (_) {
      // fall through
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
    } catch (_) {
      // fall through
    }
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      );
    } catch (_) {
      return null;
    }
  }

  /// On Android, asks the user to exclude the app from battery optimisation so
  /// background location tracking keeps running with the screen off. Shown at most
  /// once per session, and never once already granted.
  Future<void> _ensureBatteryUnrestricted() async {
    if (!Platform.isAndroid || _batteryPromptedThisSession) return;
    try {
      if (await Permission.ignoreBatteryOptimizations.isGranted) return;
      _batteryPromptedThisSession = true;
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keep tracking reliable'),
          content: const Text(
            'To record your location accurately while you are checked in — even with '
            'the screen off — please allow this app to ignore battery optimisation. '
            'Tap “Allow” on the next screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed == true) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Best-effort — never block check-in on this.
    }
  }

  /// Confirmation dialog shown before a punch. The same pattern is used for both
  /// check-in and check-out for a consistent attendance experience:
  ///   • Check In  → "Do you want to check in?"  [Cancel] [Check In]
  ///   • Check Out → "Do you want to check out?" [Cancel] [Check Out]
  Future<bool> _confirmPunch({required bool isCheckOut}) async {
    final label = isCheckOut ? 'Check Out' : 'Check In';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: Text(
          isCheckOut ? 'Do you want to check out?' : 'Do you want to check in?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final attendance = ref.watch(_dashAttendanceProvider);
    final leaves = ref.watch(_dashLeavesProvider);
    final tasks = ref.watch(_dashTasksProvider);
    final teamLeaves = ref.watch(_dashTeamLeavesProvider);

    final today = DateFormat('yyyy-MM-dd').format(_now);
    AttendanceRecord? todayRec;
    int presentCount = 0;
    double totalHours = 0;

    attendance.whenData((list) {
      for (final r in list) {
        if (r.date == today) todayRec = r;
        if (r.status == 'PRESENT') presentCount++;
        if (r.workingHours != null) totalHours += r.workingHours!;
      }
    });

    final hasCheckedIn = todayRec?.checkIn != null;
    final hasCheckedOut = todayRec?.checkOut != null;
    final timerText = _fmtTimer(_workDuration(todayRec));

    // Actual punch-in location: reverse-geocode today's check-in coordinates
    // (per employee), falling back to coordinates / a clear status string.
    final checkInLat = todayRec?.checkInLatitude;
    final checkInLng = todayRec?.checkInLongitude;
    final String heroLocation;
    if (hasCheckedIn && checkInLat != null && checkInLng != null) {
      heroLocation = ref
              .watch(_checkInPlaceProvider((lat: checkInLat, lng: checkInLng)))
              .valueOrNull ??
          '${checkInLat.toStringAsFixed(4)}, ${checkInLng.toStringAsFixed(4)}';
    } else if (hasCheckedIn) {
      heroLocation = 'Location not captured';
    } else {
      heroLocation = 'Not checked in';
    }

    int pendingLeaves = 0;
    List<LeaveRequest> leavesList = const [];
    leaves.whenData((list) {
      leavesList = list;
      pendingLeaves = list.where((l) => l.status == 'PENDING').length;
    });

    int pendingTasks = 0;
    int inProgressTasks = 0;
    List<Task> tasksList = const [];
    tasks.whenData((list) {
      tasksList = list;
      pendingTasks = list.where((t) => t.status == 'PENDING').length;
      inProgressTasks = list.where((t) => t.status == 'IN_PROGRESS').length;
    });

    List<LeaveRequest> teamLeavesList = const [];
    teamLeaves.whenData((list) {
      teamLeavesList = list;
    });

    final isManager = user?.hasRole(const {'ADMIN', 'HR'}) ?? false;
    final teamOnLeaveToday = teamLeavesList
        .where((l) =>
            l.status == 'APPROVED' &&
            today.compareTo(l.fromDate) >= 0 &&
            today.compareTo(l.toDate) <= 0)
        .toList();
    final todayItems = _buildTodayItems(
      context,
      todayRec: todayRec,
      tasks: tasksList,
      leaves: leavesList,
      todayStr: today,
      checkInLocation: heroLocation,
    );

    final activeTasks = pendingTasks + inProgressTasks;

    // Deployment-configured widget hiding (DASHBOARD_WIDGETS setting) — the
    // mobile sections reuse the web's widget keys where they overlap.
    final hiddenWidgets = ref.watch(brandingProvider).hiddenDashboardWidgets;

    // Quick actions: shortcuts to menu entries the user can already open from
    // the HRMS hub (same visibility rules, same push navigation).
    final menuItems = {for (final m in menuFor(MobileModule.hrms, user)) m.key: m};
    final quickActions = <ProAction>[];
    for (final k in _kQuickActionKeys.keys) {
      final m = menuItems[k];
      if (m == null) continue;
      quickActions.add(ProAction(
        icon: m.icon,
        label: _kQuickActionKeys[k]!,
        primary: quickActions.isEmpty,
        onTap: () => context.push(m.route),
      ));
      if (quickActions.length == 4) break;
    }

    // First word only — a long full name wraps the hero title on small phones.
    final firstName =
        (user?.firstName?.trim() ?? '').split(RegExp(r'\s+')).first;
    final greetName = firstName.isNotEmpty ? firstName : (user?.username ?? '');
    final hour = _now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        ProPage(
          topInset: mq.padding.top,
          clearNav: true,
          gap: 22,
          onRefresh: () async {
            ref.invalidate(_dashAttendanceProvider);
            ref.invalidate(_dashLeavesProvider);
            ref.invalidate(_dashTasksProvider);
            ref.invalidate(_dashTeamLeavesProvider);
          },
          hero: ProHero(
            // Reference style: small "Hello Name," over a big bold line.
            titleWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (greetName.isNotEmpty)
                  Text(
                    'Hello $greetName,',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.88),
                    ),
                  ),
                Text(
                  '$greeting!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.9,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat('EEEE, d MMM').format(_now),
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
              ],
            ),
            children: [
              if (quickActions.isNotEmpty) ProHeroActions(actions: quickActions),
            ],
          ),
          children: [
            // Attendance hero
            AttendanceHeroCard(
              timerText: timerText,
              hasCheckedIn: hasCheckedIn,
              hasCheckedOut: hasCheckedOut,
              checkInTime: _fmtTime(todayRec?.checkIn),
              checkOutTime: _fmtTime(todayRec?.checkOut),
              location: heroLocation,
              busy: _attendanceActionBusy,
              onTap: () => _runAttendanceAction(
                hasCheckedIn: hasCheckedIn,
                hasCheckedOut: hasCheckedOut,
              ),
            ),

            // This month — 2×2 "lesson card" tiles (soft theme)
            if (!hiddenWidgets.contains('stats'))
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProSectionHeader(title: 'This month'),
                  const SizedBox(height: 10),
                  GridView.count(
                    padding: EdgeInsets.zero,
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.32,
                    children: [
                      _MonthTile(
                        icon: Icons.check_circle_rounded,
                        color: AppColors.success,
                        value: presentCount.toString(),
                        label: 'Present days',
                        onTap: () => context.go('/attendance'),
                      ),
                      _MonthTile(
                        icon: Icons.access_time_rounded,
                        color: AppColors.info,
                        value: _fmtDuration(totalHours),
                        label: 'Hours worked',
                        onTap: () => context.go('/attendance'),
                      ),
                      _MonthTile(
                        icon: Icons.event_available_rounded,
                        color: AppColors.warning,
                        value: pendingLeaves.toString(),
                        label: pendingLeaves > 0
                            ? 'Leave requests waiting'
                            : 'Pending leave requests',
                        onTap: () => context.go('/leaves'),
                      ),
                      _MonthTile(
                        icon: Icons.task_alt_rounded,
                        color: AppColors.primary,
                        value: activeTasks.toString(),
                        label: 'Active tasks',
                        onTap: () => context.go('/tasks'),
                      ),
                    ],
                  ),
                ],
              ),

            // Today
            if (!hiddenWidgets.contains('attendance'))
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title: 'Today',
                    trailing: Text(
                      todayItems.isEmpty
                          ? DateFormat('d MMM').format(_now)
                          : '${todayItems.length} '
                              '${todayItems.length == 1 ? 'item' : 'items'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  attendance.when(
                    data: (_) => TodayScheduleList(items: todayItems),
                    loading: () => const AppLoadingBlock(height: 120),
                    error: (e, _) => AppErrorPanel(
                      message: e.toString(),
                      onRetry: () => ref.invalidate(_dashAttendanceProvider),
                    ),
                  ),
                ],
              ),

            // Team on leave (manager-aware, hide if empty)
            if (isManager && teamOnLeaveToday.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProSectionHeader(
                    title: 'Team on leave',
                    subtitle: 'Out of office today',
                  ),
                  const SizedBox(height: 10),
                  _TeamOnLeaveCard(
                    leaves: teamOnLeaveToday,
                    onTapItem: () => context.go('/team'),
                    humanLeaveType: _humanLeaveType,
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          right: 16,
          // Inside the shell padding.bottom already includes the tab bar.
          bottom: (mq.padding.bottom > AppChrome.bottomNavHeight
                  ? mq.padding.bottom
                  : AppChrome.bottomNavHeight) +
              8,
          child: const _ReportConcernButton(),
        ),
      ],
    );
  }

  List<TodayScheduleItem> _buildTodayItems(
    BuildContext context, {
    required AttendanceRecord? todayRec,
    required List<Task> tasks,
    required List<LeaveRequest> leaves,
    required String todayStr,
    required String checkInLocation,
  }) {
    final items = <TodayScheduleItem>[];
    final timeFmt = DateFormat('HH:mm');

    DateTime? parseLocal(String? iso) {
      if (iso == null) return null;
      try {
        return DateTime.parse(iso).toLocal();
      } catch (_) {
        return null;
      }
    }

    final inTime = parseLocal(todayRec?.checkIn);
    if (inTime != null) {
      items.add(TodayScheduleItem(
        time: timeFmt.format(inTime),
        title: 'Checked in',
        meta: checkInLocation.isNotEmpty ? checkInLocation : 'Location not captured',
        tone: AppColors.success,
        onTap: () => context.go('/attendance'),
      ));
    }
    final outTime = parseLocal(todayRec?.checkOut);
    if (outTime != null) {
      items.add(TodayScheduleItem(
        time: timeFmt.format(outTime),
        title: 'Checked out',
        meta: 'Shift complete',
        tone: AppColors.info,
        onTap: () => context.go('/attendance'),
      ));
    }

    for (final t in tasks) {
      final due = t.dueDate?.toLocal();
      if (due == null) continue;
      final dueDay = DateFormat('yyyy-MM-dd').format(due);
      if (dueDay != todayStr) continue;
      items.add(TodayScheduleItem(
        time: timeFmt.format(due),
        title: t.title,
        meta: 'Due · ${_humanTaskStatus(t.status)}',
        tone: AppColors.warning,
        onTap: () => context.go('/tasks'),
      ));
    }

    for (final l in leaves) {
      if (l.status != 'APPROVED') continue;
      if (l.fromDate != todayStr) continue;
      items.add(TodayScheduleItem(
        time: 'All',
        title: '${_humanLeaveType(l.leaveType)} starts',
        meta: 'Until ${l.toDate}',
        tone: AppColors.accent,
        onTap: () => context.go('/leaves'),
      ));
    }

    items.sort((a, b) {
      if (a.time == 'All' && b.time != 'All') return -1;
      if (b.time == 'All' && a.time != 'All') return 1;
      return a.time.compareTo(b.time);
    });
    return items;
  }

  String _humanTaskStatus(String s) {
    switch (s) {
      case 'PENDING':
        return 'Pending';
      case 'IN_PROGRESS':
        return 'In progress';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return s.toLowerCase();
    }
  }
}

/// Bottom-left "Report a Concern" launcher → confidential whistleblower form.
/// Hidden when the deployment turns the whistleblower feature off.
class _ReportConcernButton extends ConsumerWidget {
  const _ReportConcernButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(brandingProvider).featureEnabled('FEATURE_WHISTLEBLOWER')) {
      return const SizedBox.shrink();
    }
    // Small and dark — red is reserved for "check out" on this screen.
    return Tooltip(
      message: 'Report a concern',
      child: Material(
        color: AppColors.deep,
        elevation: 3,
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withOpacity(0.14)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push('/whistleblower'),
          child: const Padding(
            padding: EdgeInsets.all(11),
            child: Icon(Icons.shield_outlined, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _TeamOnLeaveCard extends StatelessWidget {
  const _TeamOnLeaveCard({
    required this.leaves,
    required this.onTapItem,
    required this.humanLeaveType,
  });

  final List<LeaveRequest> leaves;
  final VoidCallback onTapItem;
  final String Function(String) humanLeaveType;

  @override
  Widget build(BuildContext context) {
    const maxAvatars = 5;
    final overflow = leaves.length - maxAvatars;
    final avatarsToShow = leaves.take(maxAvatars).toList();
    const size = 30.0;
    const step = 22.0;
    final stackWidth =
        size + step * (avatarsToShow.length - 1 + (overflow > 0 ? 1 : 0));

    return ProListGroup(
      dividerIndent: 0,
      children: [
        // Summary: stacked avatars + count.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              SizedBox(
                width: stackWidth,
                height: size,
                child: Stack(
                  children: [
                    for (int i = 0; i < avatarsToShow.length; i++)
                      Positioned(
                        left: i * step,
                        child: _RingedAvatar(
                          child: ProAvatar(
                            name: avatarsToShow[i].employeeName ?? '?',
                            size: size,
                          ),
                        ),
                      ),
                    if (overflow > 0)
                      Positioned(
                        left: avatarsToShow.length * step,
                        child: _RingedAvatar(
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: AppColors.neutralTint,
                              borderRadius: BorderRadius.circular(size * 0.31),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '+$overflow',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  leaves.length == 1
                      ? '1 teammate out today'
                      : '${leaves.length} teammates out today',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final leave in leaves)
          _TeamLeaveRow(
            leave: leave,
            onTap: onTapItem,
            humanLeaveType: humanLeaveType,
          ),
      ],
    );
  }
}

/// Thin white ring so overlapping avatars stay distinct.
class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
      ),
      child: child,
    );
  }
}

class _TeamLeaveRow extends StatelessWidget {
  const _TeamLeaveRow({
    required this.leave,
    required this.onTap,
    required this.humanLeaveType,
  });

  final LeaveRequest leave;
  final VoidCallback onTap;
  final String Function(String) humanLeaveType;

  @override
  Widget build(BuildContext context) {
    final name = leave.employeeName ?? 'Teammate';
    return ProListRow(
      leading: ProAvatar(name: name, size: 36),
      title: name,
      subtitle: '${humanLeaveType(leave.leaveType)} · '
          '${leave.fromDate} → ${leave.toDate}',
      onTap: onTap,
    );
  }
}

/// White stat card: ring icon, big value, label (dashboard "This month").
class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProRingIcon(icon: icon, color: color, size: 42),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.6,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
