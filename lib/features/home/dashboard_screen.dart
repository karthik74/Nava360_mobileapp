import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
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

    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white.withOpacity(0.85),
      onRefresh: () async {
        ref.invalidate(_dashAttendanceProvider);
        ref.invalidate(_dashLeavesProvider);
        ref.invalidate(_dashTasksProvider);
        ref.invalidate(_dashTeamLeavesProvider);
      },
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          mq.padding.top + 8,
          16,
          mq.padding.bottom + AppChrome.bottomNavHeight + 10,
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
          const SizedBox(height: 18),

          // Stats grid (2×2, gap 10)
          Row(
            children: [
              Expanded(
                child: StatTileV2(
                  label: 'Present days',
                  value: presentCount.toString(),
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  onTap: () => context.go('/attendance'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTileV2(
                  label: 'Hours this month',
                  value: _fmtDuration(totalHours),
                  icon: Icons.access_time_rounded,
                  color: AppColors.info,
                  onTap: () => context.go('/attendance'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTileV2(
                  label: 'Pending leaves',
                  value: pendingLeaves.toString(),
                  icon: Icons.event_available_rounded,
                  color: AppColors.warning,
                  onTap: () => context.go('/leaves'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTileV2(
                  label: 'Active tasks',
                  value: activeTasks.toString(),
                  icon: Icons.task_alt_rounded,
                  color: AppColors.accent,
                  onTap: () => context.go('/tasks'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Today
          AppSectionHeader(
            title: 'Today',
            trailing: Text(
              DateFormat('EEEE, d MMM').format(_now),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
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

          // Team on leave (manager-aware, hide if empty)
          if (isManager && teamOnLeaveToday.isNotEmpty) ...[
            const SizedBox(height: 22),
            const AppSectionHeader(
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
        ],
      ),
        ),
        Positioned(
          right: 16,
          bottom: mq.padding.bottom + AppChrome.bottomNavHeight + 14,
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
class _ReportConcernButton extends StatelessWidget {
  const _ReportConcernButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.danger,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.push('/whistleblower'),
        child: const Padding(
          padding: EdgeInsets.all(15),
          child: Icon(Icons.shield_outlined, color: Colors.white, size: 24),
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

    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: Stack(
              children: [
                for (int i = 0; i < avatarsToShow.length; i++)
                  Positioned(
                    left: i * 24.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.7),
                          width: 2,
                        ),
                      ),
                      child: UserAvatar(
                        name: avatarsToShow[i].employeeName ?? '?',
                        size: 36,
                        radius: 18,
                      ),
                    ),
                  ),
                if (overflow > 0)
                  Positioned(
                    left: avatarsToShow.length * 24.0,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.55),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.7),
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '+$overflow',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < leaves.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _TeamLeaveRow(
              leave: leaves[i],
              onTap: onTapItem,
              humanLeaveType: humanLeaveType,
            ),
          ],
        ],
      ),
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
    return Material(
      color: Colors.white.withOpacity(0.45),
      borderRadius: BorderRadius.circular(AppRadii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.55)),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(name: name, size: 32, radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${humanLeaveType(leave.leaveType)} · '
                      '${leave.fromDate} → ${leave.toDate}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
