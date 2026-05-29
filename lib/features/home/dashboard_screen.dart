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

    int pendingApprovals = 0;
    List<LeaveRequest> teamLeavesList = const [];
    teamLeaves.whenData((list) {
      teamLeavesList = list;
      pendingApprovals = list.where((l) => l.status == 'PENDING').length;
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
    );

    final activeTasks = pendingTasks + inProgressTasks;

    final mq = MediaQuery.of(context);
    return RefreshIndicator(
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
          mq.padding.top+ 8,
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
            onTap: () => context.go('/attendance'),
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

          // Quick actions
          const AppSectionHeader(
            title: 'Quick actions',
            subtitle: 'Get things done in a tap',
          ),
          const SizedBox(height: 8),
          QuickActionRow(
            icon: Icons.fingerprint_rounded,
            title: hasCheckedOut
                ? 'Done for today'
                : hasCheckedIn
                    ? 'Check out now'
                    : 'Check in now',
            description: hasCheckedOut
                ? 'Shift completed for today'
                : hasCheckedIn
                    ? 'Clock out and end your shift'
                    : 'Open attendance to clock in',
            color: AppColors.primary,
            onTap: () => context.go('/attendance'),
          ),
          const SizedBox(height: 8),
          QuickActionRow(
            icon: Icons.event_available_rounded,
            title: 'Apply for leave',
            description: 'Submit a new leave request',
            color: AppColors.success,
            onTap: () => context.go('/leaves'),
          ),
          const SizedBox(height: 8),
          QuickActionRow(
            icon: Icons.task_alt_rounded,
            title: 'View tasks',
            description: activeTasks > 0
                ? '$activeTasks active · tap to review'
                : 'See what\'s on your plate',
            color: AppColors.accent,
            onTap: () => context.go('/tasks'),
          ),
          if (isManager && pendingApprovals > 0) ...[
            const SizedBox(height: 10),
            QuickActionRow(
              icon: Icons.groups_2_rounded,
              title: 'Review $pendingApprovals team request'
                  '${pendingApprovals == 1 ? '' : 's'}',
              description: 'Approve or decline pending leaves',
              color: AppColors.pink,
              onTap: () => context.go('/team'),
            ),
          ],
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
    );
  }

  List<TodayScheduleItem> _buildTodayItems(
    BuildContext context, {
    required AttendanceRecord? todayRec,
    required List<Task> tasks,
    required List<LeaveRequest> leaves,
    required String todayStr,
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
        meta: 'Hyderabad HQ',
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
