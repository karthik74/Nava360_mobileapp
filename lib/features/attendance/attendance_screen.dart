import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';

final _todayRecordsProvider =
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

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(_todayRecordsProvider);
    final now = DateTime.now();

    int presentCount = 0;
    double totalHours = 0;
    records.whenData((list) {
      for (final r in list) {
        if (r.status == 'PRESENT') presentCount++;
        if (r.workingHours != null) totalHours += r.workingHours!;
      }
    });

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white.withOpacity(0.92),
        onRefresh: () async => ref.invalidate(_todayRecordsProvider),
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            mq.padding.top + AppChrome.appBarHeight + 12,
            16,
            mq.padding.bottom + AppChrome.bottomNavHeight + 16,
          ),
          children: [
            const _AttendanceHeader(),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Present days',
                    value: presentCount.toString(),
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Hours this month',
                    value: _fmtDuration(totalHours),
                    icon: Icons.access_time_rounded,
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            AppSectionHeader(
              title: 'This month',
              subtitle: DateFormat('MMMM yyyy').format(now),
              onDark: false,
            ),
            const SizedBox(height: 10),
            records.when(
              data: (list) {
                if (list.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.calendar_month_rounded,
                    message: 'No attendance yet this month.',
                  );
                }
                final sorted = [...list]
                  ..sort((a, b) => b.date.compareTo(a.date));
                return Column(
                  children: [
                    for (final r in sorted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecordTile(
                          date: _fmtDate(r.date),
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
                onRetry: () => ref.invalidate(_todayRecordsProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceHeader extends StatelessWidget {
  const _AttendanceHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.white.withOpacity(0.12),
                    Colors.transparent,
                    Colors.black.withOpacity(0.04),
                  ],
                  stops: const [0, 0.56, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                      child: const Text(
                        'MY ATTENDANCE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Attendance & Hours',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Review your detailed shift logs and total hours tracked for the month.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
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
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tone.color.withOpacity(0.22)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.event_note_rounded, color: tone.color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$inTime → $outTime  ·  $hours',
                  style: const TextStyle(
                    fontSize: 11.5,
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

String _fmtTime(String? iso) {
  if (iso == null) return '—';
  try {
    return DateFormat.jm().format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

String _fmtDate(String iso) {
  try {
    return DateFormat('EEE, d MMM').format(DateTime.parse(iso));
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
