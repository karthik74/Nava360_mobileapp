import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../leaves/leave_models.dart';
import '../leaves/leave_repository.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';

// ── Cycle + classification helpers (mirror of the web "my" attendance view) ──

/// Days of the attendance cycle ending in (year, [month] is 1-indexed).
/// cycleStartDay = 1 → the calendar month; e.g. 26 → prevMonth-26 … thisMonth-25.
/// (For June with start day 26 this returns 26 May … 25 June.)
List<DateTime> _buildCycleDates(int year, int month, int cycleStartDay) {
  final out = <DateTime>[];
  final dimThis = DateTime(year, month + 1, 0).day; // days in (year, month)
  if (cycleStartDay <= 1) {
    for (var d = 1; d <= dimThis; d++) {
      out.add(DateTime(year, month, d));
    }
    return out;
  }
  // Last calendar day of the previous month.
  final prevLast = DateTime(year, month, 1).subtract(const Duration(days: 1));
  final prevDim = prevLast.day;
  final startDay = cycleStartDay <= prevDim ? cycleStartDay : prevDim;
  for (var d = startDay; d <= prevDim; d++) {
    out.add(DateTime(prevLast.year, prevLast.month, d));
  }
  final endDay = (cycleStartDay - 1) <= dimThis ? (cycleStartDay - 1) : dimThis;
  for (var d = 1; d <= endDay; d++) {
    out.add(DateTime(year, month, d));
  }
  return out;
}

const _jsDayToEnum = {
  DateTime.monday: 'MONDAY',
  DateTime.tuesday: 'TUESDAY',
  DateTime.wednesday: 'WEDNESDAY',
  DateTime.thursday: 'THURSDAY',
  DateTime.friday: 'FRIDAY',
  DateTime.saturday: 'SATURDAY',
  DateTime.sunday: 'SUNDAY',
};

bool _matchesNonWorkingRule(DateTime d, List<NonWorkingRule> rules) {
  if (rules.isEmpty) return false;
  final dow = _jsDayToEnum[d.weekday];
  final weekOfMonth = (d.day / 7).ceil();
  final isLast = DateTime(d.year, d.month, d.day + 7).month != d.month;
  for (final r in rules) {
    if (!r.active || r.dayOfWeek != dow) continue;
    switch (r.week) {
      case 'ALL':
        return true;
      case 'FIRST':
        if (weekOfMonth == 1) return true;
        break;
      case 'SECOND':
        if (weekOfMonth == 2) return true;
        break;
      case 'THIRD':
        if (weekOfMonth == 3) return true;
        break;
      case 'FOURTH':
        if (weekOfMonth == 4) return true;
        break;
      case 'FIFTH':
        if (weekOfMonth == 5) return true;
        break;
      case 'LAST':
        if (isLast) return true;
        break;
    }
  }
  return false;
}

bool _isNonWorkingDay(DateTime d, List<NonWorkingRule> rules) {
  final active = rules.where((r) => r.active).toList();
  if (active.isNotEmpty) return _matchesNonWorkingRule(d, active);
  return d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
}

/// Buckets a day exactly like the web view.
String _deriveBucket(DateTime d, AttendanceRecord? rec, String? holidayName,
    List<NonWorkingRule> rules) {
  final today = DateTime.now();
  final isFuture = d.isAfter(DateTime(today.year, today.month, today.day));
  if (holidayName != null) return 'holiday';
  if (_isNonWorkingDay(d, rules)) return 'nonworking';
  if (isFuture) return 'future';
  if (rec != null) {
    switch (rec.status) {
      case 'PRESENT':
        return 'present';
      case 'HALF_DAY':
        return 'halfday';
      case 'ABSENT':
        return 'absent';
      case 'ON_LEAVE':
        return 'leave';
      case 'HOLIDAY':
        return 'holiday';
      default:
        return 'absent';
    }
  }
  return 'absent';
}

({Color color, String label, String type}) _bucketMeta(String b, [String? holidayName]) {
  switch (b) {
    case 'present':
      return (color: AppColors.success, label: 'Present', type: 'Working day');
    case 'halfday':
      return (color: AppColors.warning, label: 'Half day', type: 'Half day');
    case 'absent':
      return (color: AppColors.danger, label: 'Absent', type: 'Absent');
    case 'leave':
      return (color: AppColors.info, label: 'On Leave', type: 'On leave');
    case 'holiday':
      return (color: AppColors.pink, label: 'Holiday', type: holidayName ?? 'Holiday');
    case 'nonworking':
      return (color: AppColors.muted, label: 'Non-working', type: 'Non-working day');
    case 'future':
      return (color: AppColors.muted, label: 'Upcoming', type: 'Upcoming');
    default:
      return (color: AppColors.hairline, label: '—', type: '—');
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

final _cycleStartDayProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(attendanceRepositoryProvider).getCycleStartDay(),
);

class _MonthData {
  final List<DateTime> cycle;
  final Map<String, AttendanceRecord> recordsByDate;
  final Map<String, String> holidays; // date → name
  final List<NonWorkingRule> nonworking;
  final Map<String, String> regs; // date → regularization status
  final Set<String> pendingLeaves; // dates with a PENDING leave request
  const _MonthData(this.cycle, this.recordsByDate, this.holidays,
      this.nonworking, this.regs, this.pendingLeaves);
}

/// key = "year:month1:cycleStartDay" (month is 1-indexed)
final _monthDataProvider =
    FutureProvider.autoDispose.family<_MonthData, String>((ref, key) async {
  final user = ref.watch(authUserProvider);
  final parts = key.split(':');
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final sd = int.parse(parts[2]);
  final cycle = _buildCycleDates(y, m, sd);
  if (user?.employeeId == null || cycle.isEmpty) {
    return _MonthData(cycle, const {}, const {}, const [], const {}, const {});
  }
  final fmt = DateFormat('yyyy-MM-dd');
  final from = fmt.format(cycle.first);
  final to = fmt.format(cycle.last);
  final repo = ref.watch(attendanceRepositoryProvider);
  final records =
      await repo.listForEmployee(user!.employeeId!, from: from, to: to, size: 100);
  final holidays = await repo.listMyHolidays(from: from, to: to);
  final nonworking = await repo.listNonWorkingDays();
  final regs =
      await repo.myRegularizationStatusByDate(user.employeeId!, from: from, to: to);
  final pendingLeaves = await ref
      .watch(leaveRepositoryProvider)
      .myPendingLeaveDates(user.employeeId!, from: from, to: to);
  return _MonthData(
    cycle,
    {for (final r in records) r.date: r},
    holidays,
    nonworking,
    regs,
    pendingLeaves,
  );
});

final _leaveTypesProvider = FutureProvider.autoDispose<List<LeaveTypePolicy>>(
  (ref) => ref.watch(leaveRepositoryProvider).listLeaveTypes(),
);

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late int _year;
  late int _month; // 1-indexed (1 = January)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  String _keyFor(int startDay) => '$_year:$_month:$startDay';

  void _shiftMonth(int delta) {
    var nm = _month + delta;
    var ny = _year;
    if (nm < 1) {
      nm = 12;
      ny--;
    }
    if (nm > 12) {
      nm = 1;
      ny++;
    }
    setState(() {
      _month = nm;
      _year = ny;
    });
  }

  void _refresh(int startDay) {
    ref.invalidate(_monthDataProvider(_keyFor(startDay)));
  }

  @override
  Widget build(BuildContext context) {
    final startDay = ref.watch(_cycleStartDayProvider).valueOrNull ?? 1;
    final dataAsync = ref.watch(_monthDataProvider(_keyFor(startDay)));
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white.withOpacity(0.92),
        onRefresh: () async => _refresh(startDay),
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            mq.padding.top + AppChrome.appBarHeight + 12,
            16,
            mq.padding.bottom + 16,
          ),
          children: [
            const _AttendanceHeader(),
            const SizedBox(height: 18),
            _MonthSwitcher(
              year: _year,
              month: _month,
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
            ),
            const SizedBox(height: 12),
            dataAsync.when(
              data: (data) => _buildContent(context, data),
              loading: () => const AppLoadingBlock(height: 260),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => _refresh(startDay),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, _MonthData data) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // Build day cells; drop future days (per requirement).
    final cells = <_DayCellData>[];
    final counts = {
      'present': 0,
      'halfday': 0,
      'absent': 0,
      'leave': 0,
      'holiday': 0,
      'nonworking': 0,
    };
    double totalHours = 0;
    final fmt = DateFormat('yyyy-MM-dd');
    for (final date in data.cycle) {
      final iso = fmt.format(date);
      final isFuture = date.isAfter(todayStart);
      final regStatus = data.regs[iso];
      final leavePending = data.pendingLeaves.contains(iso);
      // Past/today days always show. Future days are normally hidden, but a future
      // day with a pending leave (leaves are usually future-dated) or pending
      // regularization must still appear so the request shows on its exact day.
      if (isFuture && !(leavePending || regStatus == 'PENDING')) continue;
      final holidayName = data.holidays[iso];
      final rec = data.recordsByDate[iso];
      final bucket = _deriveBucket(date, rec, holidayName, data.nonworking);
      if (counts.containsKey(bucket)) counts[bucket] = counts[bucket]! + 1;
      if (rec?.workingHours != null) totalHours += rec!.workingHours!;
      cells.add(_DayCellData(
        date: date,
        iso: iso,
        bucket: bucket,
        record: rec,
        holidayName: holidayName,
        hasReg: data.regs.containsKey(iso),
        regStatus: regStatus,
        leavePending: leavePending,
      ));
    }
    // Newest first.
    final sorted = [...cells]..sort((a, b) => b.iso.compareTo(a.iso));
    final worked = counts['present']! + counts['halfday']!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Worked days',
                value: worked.toString(),
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Hours this cycle',
                value: _fmtDuration(totalHours),
                icon: Icons.access_time_rounded,
                color: AppColors.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (sorted.isEmpty)
          const AppEmptyState(
            icon: Icons.calendar_month_rounded,
            message: 'No attendance days in this cycle yet.',
          )
        else
          for (final c in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DayRow(
                cell: c,
                isToday: c.date.year == now.year &&
                    c.date.month == now.month &&
                    c.date.day == now.day,
                onTap: () => _openDayActions(c),
              ),
            ),
        const SizedBox(height: 14),
        const _Legend(),
      ],
    );
  }

  // ── Day actions ────────────────────────────────────────────────────────────

  void _openDayActions(_DayCellData c) {
    final meta = _bucketMeta(c.bucket, c.holidayName);
    final regPending = c.regStatus == 'PENDING';
    // Regularization only for real, past working days (not holiday/non-working,
    // not future — the backend rejects regularizing a future date), and not when
    // one is already awaiting approval for this day.
    final canRegularize = c.bucket != 'holiday' &&
        c.bucket != 'nonworking' &&
        c.bucket != 'future' &&
        !regPending;
    // Leave only for days that aren't already present/leave/holiday/non-working,
    // and not when a leave request is already pending for this day.
    final canLeave =
        (c.bucket == 'absent' || c.bucket == 'halfday') && !c.leavePending;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEEE, d MMMM yyyy').format(c.date),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  StatusPill(label: meta.label, color: meta.color),
                ],
              ),
            ),
            if (c.record != null &&
                (c.record!.checkIn != null || c.record!.checkOut != null))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_fmtTime(c.record!.checkIn)} → ${_fmtTime(c.record!.checkOut)}  ·  ${_fmtDuration(c.record!.workingHours)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (regPending)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Regularization pending approval',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else if (c.hasReg)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Regularization ${(c.regStatus ?? '').toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (c.leavePending)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Leave request submitted',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.info,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            if (canRegularize)
              ListTile(
                leading: const Icon(Icons.fact_check_outlined,
                    color: AppColors.primary),
                title: const Text('Request regularization'),
                subtitle: const Text('Fix or mark your attendance for this day'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openRegularizationForm(c.date);
                },
              ),
            if (canLeave)
              ListTile(
                leading:
                    const Icon(Icons.event_busy_outlined, color: AppColors.info),
                title: const Text('Apply leave'),
                subtitle: const Text('Request leave for this day'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openLeaveForm(c.date);
                },
              ),
            if (!canRegularize && !canLeave)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  'No actions available for this day.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openRegularizationForm(DateTime date) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (_) => _RegularizationSheet(date: date),
    );
    if (ok == true) {
      ref.invalidate(_monthDataProvider(
          _keyFor(ref.read(_cycleStartDayProvider).valueOrNull ?? 1)));
      _snack('Regularization request submitted.');
    }
  }

  Future<void> _openLeaveForm(DateTime date) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (_) => _LeaveSheet(date: date),
    );
    if (ok == true) {
      ref.invalidate(_monthDataProvider(
          _keyFor(ref.read(_cycleStartDayProvider).valueOrNull ?? 1)));
      _snack('Leave request submitted.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _DayCellData {
  final DateTime date;
  final String iso;
  final String bucket;
  final AttendanceRecord? record;
  final String? holidayName;
  final bool hasReg;
  final String? regStatus; // PENDING | APPROVED | REJECTED (newest for the day)
  final bool leavePending; // a PENDING leave request covers this day
  const _DayCellData({
    required this.date,
    required this.iso,
    required this.bucket,
    required this.record,
    required this.holidayName,
    required this.hasReg,
    required this.regStatus,
    required this.leavePending,
  });
}

/// A short status note shown on the attendance day when a request is awaiting
/// approval: a pending regularization or a submitted leave request.
({String label, Color color})? _pendingNote(_DayCellData c) {
  if (c.regStatus == 'PENDING') {
    return (label: 'Pending approval', color: AppColors.warning);
  }
  if (c.leavePending) {
    return (label: 'Leave request submitted', color: AppColors.info);
  }
  return null;
}

String _attStatusLabel(String s) {
  switch (s) {
    case 'PRESENT':
      return 'Present';
    case 'HALF_DAY':
      return 'Half day';
    case 'ON_LEAVE':
      return 'On leave';
    default:
      return s;
  }
}

// ── Month switcher ───────────────────────────────────────────────────────────

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher(
      {required this.year,
      required this.month,
      required this.onPrev,
      required this.onNext});
  final int year;
  final int month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Attendance cycle',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const Spacer(),
        _NavBtn(icon: Icons.chevron_left_rounded, onTap: onPrev),
        SizedBox(
          width: 116,
          child: Text(
            DateFormat('MMMM yyyy').format(DateTime(year, month, 1)),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        _NavBtn(icon: Icons.chevron_right_rounded, onTap: onNext),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.hairline),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

// ── Day row ──────────────────────────────────────────────────────────────────

class _DayRow extends StatelessWidget {
  const _DayRow({required this.cell, required this.isToday, required this.onTap});
  final _DayCellData cell;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _bucketMeta(cell.bucket, cell.holidayName);
    final note = _pendingNote(cell);
    final rec = cell.record;
    final String sub;
    if (rec != null && (rec.checkIn != null || rec.checkOut != null)) {
      sub =
          '${_fmtTime(rec.checkIn)} → ${_fmtTime(rec.checkOut)}  ·  ${_fmtDuration(rec.workingHours)}';
    } else {
      sub = meta.type;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          shadow: AppShadows.soft,
          border: isToday
              ? Border.all(color: AppColors.primary, width: 1.4)
              : null,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: meta.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: meta.color.withOpacity(0.22)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('d').format(cell.date),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: meta.color,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      DateFormat('EEE').format(cell.date).toUpperCase(),
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: meta.color,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          DateFormat('EEEE, d MMM').format(cell.date),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: const Text(
                              'Today',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                        if (cell.hasReg) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.flag_rounded,
                              size: 12, color: AppColors.warning),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: note.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border:
                              Border.all(color: note.color.withOpacity(0.25)),
                        ),
                        child: Text(
                          note.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: note.color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: meta.label, color: meta.color),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('present', 'Present'),
      ('halfday', 'Half day'),
      ('absent', 'Absent'),
      ('leave', 'On leave'),
      ('holiday', 'Holiday'),
      ('nonworking', 'Non-working'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final it in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _bucketMeta(it.$1).color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                it.$2,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ── Regularization form sheet ────────────────────────────────────────────────

class _RegularizationSheet extends ConsumerStatefulWidget {
  const _RegularizationSheet({required this.date});
  final DateTime date;

  @override
  ConsumerState<_RegularizationSheet> createState() =>
      _RegularizationSheetState();
}

class _RegularizationSheetState extends ConsumerState<_RegularizationSheet> {
  String _status = 'PRESENT';
  TimeOfDay? _checkIn;
  TimeOfDay? _checkOut;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _statuses = ['PRESENT', 'HALF_DAY', 'ON_LEAVE'];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please add a reason.');
      return;
    }
    final empId = ref.read(authUserProvider)?.employeeId;
    if (empId == null) {
      setState(() => _error = 'Your account is not linked to an employee.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(attendanceRepositoryProvider).createRegularization(
            employeeId: empId,
            date: DateFormat('yyyy-MM-dd').format(widget.date),
            requestedStatus: _status,
            checkIn: _checkIn == null ? null : _fmt(_checkIn!),
            checkOut: _checkOut == null ? null : _fmt(_checkOut!),
            reason: _reason.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Regularize ${DateFormat('d MMM yyyy').format(widget.date)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Requested status',
                  prefixIcon: Icon(Icons.tune_rounded, size: 20),
                ),
                items: [
                  for (final s in _statuses)
                    DropdownMenuItem(value: s, child: Text(_attStatusLabel(s))),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'PRESENT'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'Check-in',
                      value: _checkIn,
                      onPick: (t) => setState(() => _checkIn = t),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeField(
                      label: 'Check-out',
                      value: _checkOut,
                      onPick: (t) => setState(() => _checkOut = t),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AppErrorPanel(message: _error!),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(Colors.white)),
                        )
                      : const Text('Submit request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField(
      {required this.label, required this.value, required this.onPick});
  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: value ?? const TimeOfDay(hour: 9, minute: 30),
        );
        if (t != null) onPick(t);
      },
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule_rounded, size: 20),
        ),
        child: Text(
          value == null ? 'Not set' : value!.format(context),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: value == null ? AppColors.muted : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

// ── Leave form sheet ─────────────────────────────────────────────────────────

class _LeaveSheet extends ConsumerStatefulWidget {
  const _LeaveSheet({required this.date});
  final DateTime date;

  @override
  ConsumerState<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends ConsumerState<_LeaveSheet> {
  String? _type;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_type == null) {
      setState(() => _error = 'Please choose a leave type.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please add a reason.');
      return;
    }
    final empId = ref.read(authUserProvider)?.employeeId;
    if (empId == null) {
      setState(() => _error = 'Your account is not linked to an employee.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = DateFormat('yyyy-MM-dd').format(widget.date);
      await ref.read(leaveRepositoryProvider).create(LeaveCreateRequest(
            employeeId: empId,
            leaveType: _type!,
            fromDate: d,
            toDate: d,
            reason: _reason.text.trim(),
          ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final types = ref.watch(_leaveTypesProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Apply leave · ${DateFormat('d MMM yyyy').format(widget.date)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 14),
              types.when(
                data: (list) => DropdownButtonFormField<String>(
                  value: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Leave type',
                    prefixIcon: Icon(Icons.category_outlined, size: 20),
                  ),
                  items: [
                    for (final t in list)
                      DropdownMenuItem(value: t.code, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => _type = v),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Text('Could not load leave types: $e',
                    style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AppErrorPanel(message: _error!),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(Colors.white)),
                        )
                      : const Text('Submit leave request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

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
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.25)),
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
                  'Tap any day to see its status, request a regularization, or apply for leave.',
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

String _fmtTime(String? iso) {
  if (iso == null) return '—';
  try {
    return DateFormat.jm().format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

String _fmtDuration(double? hours) {
  if (hours == null || hours == 0) return '0h 00m';
  final h = hours.floor();
  final m = ((hours - h) * 60).round();
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}
