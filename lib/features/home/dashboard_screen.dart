import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../attendance/attendance_models.dart';
import '../attendance/attendance_repository.dart';
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

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

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

  String get _greeting {
    final h = _now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
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

    int pendingLeaves = 0;
    leaves.whenData((list) {
      pendingLeaves = list.where((l) => l.status == 'PENDING').length;
    });

    int pendingTasks = 0;
    int inProgressTasks = 0;
    tasks.whenData((list) {
      pendingTasks = list.where((t) => t.status == 'PENDING').length;
      inProgressTasks = list.where((t) => t.status == 'IN_PROGRESS').length;
    });

    int pendingApprovals = 0;
    teamLeaves.whenData((list) {
      pendingApprovals = list.where((l) => l.status == 'PENDING').length;
    });

    final isManager = user?.hasRole(const {'ADMIN', 'HR'}) ?? false;

    return RefreshIndicator(
      color: AppColors.primary,
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Greeting
          Text(
            '$_greeting,',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.username ?? 'User',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),

          // Attendance hero mini
          _AttendanceMiniCard(
            now: _now,
            hasCheckedIn: hasCheckedIn,
            hasCheckedOut: hasCheckedOut,
            timerText: timerText,
            checkInTime: _fmtTime(todayRec?.checkIn),
            checkOutTime: _fmtTime(todayRec?.checkOut),
            onTap: () => context.go('/attendance'),
          ),
          const SizedBox(height: 20),

          // Stats grid
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Present days',
                  value: presentCount.toString(),
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  onTap: () => context.go('/attendance'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Hours this month',
                  value: _fmtDuration(totalHours),
                  icon: Icons.access_time_rounded,
                  color: AppColors.info,
                  onTap: () => context.go('/attendance'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Pending leaves',
                  value: pendingLeaves.toString(),
                  icon: Icons.event_available_rounded,
                  color: AppColors.warning,
                  onTap: () => context.go('/leaves'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Active tasks',
                  value: '${pendingTasks + inProgressTasks}',
                  icon: Icons.task_alt_rounded,
                  color: AppColors.accent,
                  onTap: () => context.go('/tasks'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Quick actions
          const AppSectionHeader(
            title: 'Quick actions',
            subtitle: 'Get things done in a tap',
          ),
          const SizedBox(height: 14),
          AppQuickAction(
            icon: Icons.fingerprint_rounded,
            label: hasCheckedOut
                ? 'Done for today'
                : hasCheckedIn
                    ? 'Check out now'
                    : 'Check in now',
            color: AppColors.primary,
            onTap: () => context.go('/attendance'),
          ),
          const SizedBox(height: 10),
          AppQuickAction(
            icon: Icons.event_available_rounded,
            label: 'Apply for leave',
            color: AppColors.success,
            onTap: () => context.go('/leaves'),
          ),
          const SizedBox(height: 10),
          AppQuickAction(
            icon: Icons.task_alt_rounded,
            label: 'View my tasks',
            color: AppColors.accent,
            onTap: () => context.go('/tasks'),
          ),
          if (isManager && pendingApprovals > 0) ...[
            const SizedBox(height: 10),
            AppQuickAction(
              icon: Icons.groups_2_rounded,
              label:
                  'Review $pendingApprovals team request${pendingApprovals == 1 ? '' : 's'}',
              color: AppColors.pink,
              onTap: () => context.go('/team'),
            ),
          ],
          const SizedBox(height: 28),

          // Today's date
          AppSectionHeader(
            title: 'Today',
            trailing: Text(
              DateFormat('EEEE, d MMMM').format(_now),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Recent attendance
          attendance.when(
            data: (list) {
              final recent = list.where((r) => r.date != today).toList()
                ..sort((a, b) => b.date.compareTo(a.date));
              final shown = recent.take(3).toList();
              if (shown.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.calendar_month_rounded,
                  message: 'No recent attendance records.',
                );
              }
              return Column(
                children: [
                  for (final r in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RecentAttendanceTile(
                        date: DateFormat('EEE, d MMM')
                            .format(DateTime.parse(r.date)),
                        inTime: _fmtTime(r.checkIn),
                        outTime: _fmtTime(r.checkOut),
                        hours: _fmtDuration(r.workingHours),
                        status: r.status,
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 140),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(_dashAttendanceProvider),
            ),
          ),
          const SizedBox(height: 28),

          // Upcoming leaves
          const AppSectionHeader(
            title: 'Upcoming leaves',
            subtitle: 'Your scheduled time off',
          ),
          const SizedBox(height: 14),
          leaves.when(
            data: (list) {
              final upcoming = list
                  .where((l) =>
                      l.status == 'APPROVED' &&
                      DateTime.tryParse(l.fromDate)?.isAfter(
                            DateTime.now().subtract(const Duration(days: 1)),
                          ) ==
                          true)
                  .toList()
                ..sort((a, b) => a.fromDate.compareTo(b.fromDate));
              final shown = upcoming.take(3).toList();
              if (shown.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.beach_access_rounded,
                  message: 'No upcoming approved leaves.',
                );
              }
              return Column(
                children: [
                  for (final l in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _UpcomingLeaveTile(
                        type: l.leaveType,
                        from: l.fromDate,
                        to: l.toDate,
                        days: l.numberOfDays ?? 1,
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 140),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(_dashLeavesProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceMiniCard extends StatelessWidget {
  const _AttendanceMiniCard({
    required this.now,
    required this.hasCheckedIn,
    required this.hasCheckedOut,
    required this.timerText,
    required this.checkInTime,
    required this.checkOutTime,
    required this.onTap,
  });

  final DateTime now;
  final bool hasCheckedIn;
  final bool hasCheckedOut;
  final String timerText;
  final String checkInTime;
  final String checkOutTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badgeLabel = hasCheckedOut
        ? 'DONE'
        : hasCheckedIn
            ? 'LIVE'
            : 'READY';
    final badgeColor = hasCheckedOut
        ? Colors.white.withOpacity(0.85)
        : hasCheckedIn
            ? const Color(0xFF34D399)
            : Colors.white.withOpacity(0.65);

    return AnimatedGradientCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        badgeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('EEE, d MMM').format(now),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              timerText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasCheckedOut
                  ? 'Shift complete'
                  : hasCheckedIn
                      ? 'Timer running'
                      : 'Tap to check in',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _MiniTimeBlock(
                      icon: Icons.login_rounded,
                      label: 'In',
                      value: checkInTime,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: Colors.white.withOpacity(0.18),
                  ),
                  Expanded(
                    child: _MiniTimeBlock(
                      icon: Icons.logout_rounded,
                      label: 'Out',
                      value: checkOutTime,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTimeBlock extends StatelessWidget {
  const _MiniTimeBlock({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: Colors.white.withOpacity(0.8)),
        const SizedBox(width: 6),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentAttendanceTile extends StatelessWidget {
  const _RecentAttendanceTile({
    required this.date,
    required this.inTime,
    required this.outTime,
    required this.hours,
    required this.status,
  });

  final String date;
  final String inTime;
  final String outTime;
  final String hours;
  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = StatusTone.forAttendance(status);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tone.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.event_note_rounded, color: tone.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$inTime → $outTime  ·  $hours',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(label: tone.label, color: tone.color),
        ],
      ),
    );
  }
}

class _UpcomingLeaveTile extends StatelessWidget {
  const _UpcomingLeaveTile({
    required this.type,
    required this.from,
    required this.to,
    required this.days,
  });

  final String type;
  final String from;
  final String to;
  final int days;

  String _humanType(String t) {
    final s = t.toLowerCase().replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.beach_access_rounded,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _humanType(type),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$from → $to  ·  $days day${days == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const StatusPill(label: 'Approved', color: AppColors.success),
        ],
      ),
    );
  }
}
