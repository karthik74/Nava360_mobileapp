import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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
  final Set<String> approvedLeaves; // dates with an APPROVED leave request
  const _MonthData(this.cycle, this.recordsByDate, this.holidays,
      this.nonworking, this.regs, this.pendingLeaves, this.approvedLeaves);
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
    return _MonthData(
        cycle, const {}, const {}, const [], const {}, const {}, const {});
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
  final leaveDates = await ref
      .watch(leaveRepositoryProvider)
      .myLeaveDates(user.employeeId!, from: from, to: to);
  return _MonthData(
    cycle,
    {for (final r in records) r.date: r},
    holidays,
    nonworking,
    regs,
    leaveDates.pending,
    leaveDates.approved,
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
    final data = dataAsync.valueOrNull;
    final summary = data == null ? null : _summarize(data);

    final List<Widget> body = dataAsync.when(
      data: (d) => _buildContent(context, d, summary ?? _summarize(d)),
      loading: () => const [AppLoadingBlock(height: 260)],
      error: (e, _) => [
        AppErrorPanel(
          message: e.toString(),
          onRetry: () => _refresh(startDay),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProPage(
        topInset: MediaQuery.of(context).padding.top,
        // The shell hides its tab bar on /attendance.
        clearNav: false,
        gap: 22,
        onRefresh: () async => _refresh(startDay),
        hero: ProHero(
          title: 'Attendance & hours',
          subtitle:
              'Tap any day to see its status, request a regularization, or apply for leave.',
          children: [
            _TodayPanel(
              record: summary?.todayRecord,
              known: summary?.todayInCycle ?? false,
            ),
            _HeroMonthSwitcher(
              year: _year,
              month: _month,
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              summary: summary == null
                  ? null
                  : '${summary.worked} days worked · ${_fmtDuration(summary.totalHours)}',
            ),
            if (summary != null)
              ProHeroStats(
                stats: [
                  ProStat(
                    label: 'Worked days',
                    value: summary.worked.toString(),
                    sub: 'this cycle',
                    dot: AppColors.live,
                  ),
                  ProStat(
                    label: 'Hours',
                    value: _fmtDuration(summary.totalHours),
                    sub: 'this cycle',
                  ),
                  ProStat(
                    label: 'Absent',
                    value: summary.counts['absent'].toString(),
                    sub: summary.counts['leave'] == 0
                        ? 'days'
                        : '${summary.counts['leave']} on leave',
                    dot: const Color(0xFFE5484D),
                  ),
                ],
              ),
          ],
        ),
        children: body,
      ),
    );
  }

  /// Classifies every day of the cycle exactly as before (same buckets, same
  /// hidden future days) so the hero, the calendar and the list agree.
  _CycleSummary _summarize(_MonthData data) {
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
      final leaveApproved = data.approvedLeaves.contains(iso);
      // Past/today days always show. Future days are normally hidden, but a future
      // day with a pending/approved leave (leaves are usually future-dated) or
      // pending regularization must still appear so it shows on its exact day.
      if (isFuture && !(leavePending || leaveApproved || regStatus == 'PENDING')) {
        continue;
      }
      final holidayName = data.holidays[iso];
      final rec = data.recordsByDate[iso];
      var bucket = _deriveBucket(date, rec, holidayName, data.nonworking);
      // An approved leave never writes an ON_LEAVE attendance row, so the day would
      // otherwise fall through to Absent (or Upcoming, if future). Show it as On
      // Leave — but keep a real Present/Half-day/Holiday/Non-working status intact.
      if (leaveApproved && (bucket == 'absent' || bucket == 'future')) {
        bucket = 'leave';
      }
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
    final todayIso = fmt.format(todayStart);
    return _CycleSummary(
      cellsByIso: {for (final c in cells) c.iso: c},
      sorted: sorted,
      counts: counts,
      totalHours: totalHours,
      worked: worked,
      todayInCycle: data.cycle.any((d) => fmt.format(d) == todayIso),
      todayRecord: data.recordsByDate[todayIso],
    );
  }

  List<Widget> _buildContent(
      BuildContext context, _MonthData data, _CycleSummary s) {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    return [
      _CalendarCard(
        data: data,
        summary: s,
        isToday: isToday,
        onTapDay: _openDayActions,
      ),
      if (s.sorted.isEmpty)
        const ProEmpty(
          icon: Icons.calendar_month_rounded,
          title: 'No attendance days in this cycle yet.',
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(
              title: 'Days this cycle · ${s.sorted.length}',
              small: true,
            ),
            const SizedBox(height: 8),
            ProListGroup(
              dividerIndent: 64,
              children: [
                for (final c in s.sorted)
                  _DayRow(
                    cell: c,
                    isToday: isToday(c.date),
                    onTap: () => _openDayActions(c),
                  ),
              ],
            ),
          ],
        ),
    ];
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
    final rec = c.record;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEEE, d MMMM yyyy').format(c.date),
                      style: _sheetTitleStyle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _bucketPill(c.bucket, meta.label),
                  ),
                ],
              ),
              if (c.bucket == 'holiday' && c.holidayName != null) ...[
                const SizedBox(height: 2),
                Text(c.holidayName!, style: AppText.caption),
              ],
              if (rec != null &&
                  (rec.checkIn != null || rec.checkOut != null)) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                        child: _InfoCell(
                            label: 'Check-in', value: _fmtTime(rec.checkIn))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _InfoCell(
                            label: 'Check-out', value: _fmtTime(rec.checkOut))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _InfoCell(
                            label: 'Worked',
                            value: _fmtDuration(rec.workingHours))),
                  ],
                ),
              ],
              if (regPending) ...[
                const SizedBox(height: 12),
                const ProNote('Regularization pending approval',
                    tone: ProNoteTone.warn,
                    icon: Icons.hourglass_top_rounded),
              ] else if (c.hasReg) ...[
                const SizedBox(height: 12),
                ProNote(
                  'Regularization ${(c.regStatus ?? '').toLowerCase()}',
                  icon: Icons.flag_outlined,
                ),
              ],
              if (c.leavePending) ...[
                const SizedBox(height: 12),
                const ProNote('Leave request submitted',
                    tone: ProNoteTone.info, icon: Icons.event_note_rounded),
              ],
              const SizedBox(height: 16),
              if (canRegularize || canLeave)
                ProListGroup(
                  children: [
                    if (canRegularize)
                      ProListRow(
                        leading: ProIconWell(
                            icon: Icons.fact_check_outlined,
                            color: AppColors.primary),
                        title: 'Request regularization',
                        subtitle: 'Fix or mark your attendance for this day',
                        onTap: () {
                          Navigator.pop(ctx);
                          _openRegularizationForm(c.date);
                        },
                      ),
                    if (canLeave)
                      ProListRow(
                        leading: const ProIconWell(
                            icon: Icons.event_busy_outlined,
                            color: AppColors.info),
                        title: 'Apply leave',
                        subtitle: 'Request leave for this day',
                        onTap: () {
                          Navigator.pop(ctx);
                          _openLeaveForm(c.date);
                        },
                      ),
                  ],
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'No actions available for this day.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13.5),
                  ),
                ),
            ],
          ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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

/// Everything the screen shows for one cycle, computed once per build.
class _CycleSummary {
  final Map<String, _DayCellData> cellsByIso; // visible days only
  final List<_DayCellData> sorted; // newest first
  final Map<String, int> counts;
  final double totalHours;
  final int worked;
  final bool todayInCycle;
  final AttendanceRecord? todayRecord;
  const _CycleSummary({
    required this.cellsByIso,
    required this.sorted,
    required this.counts,
    required this.totalHours,
    required this.worked,
    required this.todayInCycle,
    required this.todayRecord,
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

// ── Status styling ───────────────────────────────────────────────────────────

const _holidayTint = Color(0xFFF0EBF7);
const _warnInk = Color(0xFF9A5B00);

/// (foreground, background) for a day bucket — calendar cells and pills.
({Color fg, Color bg}) _bucketTone(String b) {
  switch (b) {
    case 'present':
      return (fg: AppColors.success, bg: AppColors.successTint);
    case 'halfday':
      return (fg: _warnInk, bg: AppColors.warningTint);
    case 'absent':
      return (fg: AppColors.danger, bg: AppColors.dangerTint);
    case 'leave':
      return (fg: AppColors.info, bg: AppColors.infoTint);
    case 'holiday':
      return (fg: AppColors.pink, bg: _holidayTint);
    case 'nonworking':
      return (fg: AppColors.faint, bg: Colors.transparent);
    case 'future':
      return (fg: const Color(0xFF43585D), bg: AppColors.surfaceAlt);
    default:
      return (fg: AppColors.muted, bg: AppColors.neutralTint);
  }
}

Widget _bucketPill(String bucket, String label) {
  final t = _bucketTone(bucket);
  return ProPill(
    label,
    color: t.fg,
    background: t.bg == Colors.transparent ? AppColors.neutralTint : t.bg,
  );
}

const _sheetTitleStyle = TextStyle(
  fontSize: 19,
  height: 1.3,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.4,
  color: AppColors.ink,
);

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFC6D3D6),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}

/// Small grey value cell (check-in / check-out / worked).
class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero: today + month switcher ─────────────────────────────────────────────

/// Live clock with today's check-in state (from the loaded cycle). Owns its
/// own one-second ticker so the rest of the screen doesn't rebuild.
class _TodayPanel extends StatefulWidget {
  const _TodayPanel({required this.record, required this.known});

  /// Today's attendance row, when the cycle on screen contains today.
  final AttendanceRecord? record;

  /// False while loading or when another cycle is on screen.
  final bool known;

  @override
  State<_TodayPanel> createState() => _TodayPanelState();
}

class _TodayPanelState extends State<_TodayPanel> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _liveWorked(AttendanceRecord r) {
    final inTime = DateTime.tryParse(r.checkIn ?? '');
    if (inTime == null) return '—';
    final d = _now.difference(inTime.toLocal());
    if (d.isNegative) return '0h 00m';
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.known ? widget.record : null;
    final checkedIn = r?.checkIn != null;
    final checkedOut = r?.checkOut != null;
    final onClock = checkedIn && !checkedOut;

    final String status;
    final Color dot;
    if (checkedOut) {
      status = 'Done for today';
      dot = const Color(0xFF9FB3B8);
    } else if (checkedIn) {
      status = 'On the clock';
      dot = AppColors.live;
    } else {
      status = 'Not checked in';
      dot = const Color(0xFFF2B347);
    }

    final worked = r == null
        ? '—'
        : onClock
            ? _liveWorked(r)
            : checkedIn
                ? _fmtDuration(r.workingHours)
                : '—';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today · ${DateFormat('EEE, d MMM').format(_now)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
              if (widget.known)
                Container(
                  height: 26,
                  padding: const EdgeInsets.only(left: 4, right: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onClock)
                        ProPulseDot(color: dot, size: 7)
                      else
                        SizedBox(
                          width: 17,
                          height: 17,
                          child: Center(
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                  color: dot, shape: BoxShape.circle),
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              DateFormat('h:mm:ss a').format(_now),
              style: const TextStyle(
                fontSize: 34,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.known)
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                        child: _HeroMini(
                            label: 'Check-in', value: _fmtTime(r?.checkIn))),
                    VerticalDivider(
                        width: 1, color: Colors.white.withOpacity(0.1)),
                    Expanded(
                        child: _HeroMini(
                            label: 'Check-out', value: _fmtTime(r?.checkOut))),
                    VerticalDivider(
                        width: 1, color: Colors.white.withOpacity(0.1)),
                    Expanded(child: _HeroMini(label: 'Worked', value: worked)),
                  ],
                ),
              ),
            )
          else
            const Text(
              'Switch to the current cycle to see today\'s check-in.',
              style: TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
          if (widget.known && !checkedOut) ...[
            const SizedBox(height: 10),
            // Check-in / check-out (with location capture) lives on Home.
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => context.go('/home'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        checkedIn ? 'Go to check-out' : 'Go to check-in',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMini extends StatelessWidget {
  const _HeroMini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.66),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMonthSwitcher extends StatelessWidget {
  const _HeroMonthSwitcher({
    required this.year,
    required this.month,
    required this.onPrev,
    required this.onNext,
    this.summary,
  });
  final int year;
  final int month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          _HeroNavBtn(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous month',
            onTap: onPrev,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(DateTime(year, month, 1)),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
                if (summary != null)
                  Text(
                    summary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.66),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          _HeroNavBtn(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next month',
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _HeroNavBtn extends StatelessWidget {
  const _HeroNavBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ── Calendar ─────────────────────────────────────────────────────────────────

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.data,
    required this.summary,
    required this.isToday,
    required this.onTapDay,
  });
  final _MonthData data;
  final _CycleSummary summary;
  final bool Function(DateTime) isToday;
  final ValueChanged<_DayCellData> onTapDay;

  @override
  Widget build(BuildContext context) {
    final cycle = data.cycle;
    final fmt = DateFormat('yyyy-MM-dd');
    final String title;
    if (cycle.isEmpty) {
      title = 'Calendar';
    } else if (cycle.first.month == cycle.last.month &&
        cycle.first.year == cycle.last.year) {
      title = DateFormat('MMMM yyyy').format(cycle.first);
    } else {
      title =
          '${DateFormat('d MMM').format(cycle.first)} – ${DateFormat('d MMM').format(cycle.last)}';
    }

    // Monday-first grid; leading blanks before the first cycle day.
    final slots = <DateTime?>[
      if (cycle.isNotEmpty)
        for (var i = 0; i < cycle.first.weekday - 1; i++) null,
      ...cycle,
    ];
    while (slots.length % 7 != 0) {
      slots.add(null);
    }

    Widget cellFor(DateTime? d) {
      if (d == null) return const SizedBox(height: 40);
      final iso = fmt.format(d);
      final cell = summary.cellsByIso[iso];
      // Hidden (future) days still show their kind, but aren't tappable.
      final bucket = cell?.bucket ??
          _deriveBucket(d, data.recordsByDate[iso], data.holidays[iso],
              data.nonworking);
      return _CalCell(
        date: d,
        bucket: bucket,
        holidayName: cell?.holidayName ?? data.holidays[iso],
        today: isToday(d),
        marker: cell == null ? null : _pendingNote(cell)?.color,
        onTap: cell == null ? null : () => onTapDay(cell),
      );
    }

    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: title,
            trailing: const Text(
              'Tap a day for details',
              style: TextStyle(fontSize: 12.5, color: AppColors.faint),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    weekdays[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < slots.length; r += 7) ...[
            if (r > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: cellFor(slots[r + i])),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
          const SizedBox(height: 12),
          const _Legend(),
        ],
      ),
    );
  }
}

class _CalCell extends StatelessWidget {
  const _CalCell({
    required this.date,
    required this.bucket,
    required this.holidayName,
    required this.today,
    required this.marker,
    required this.onTap,
  });
  final DateTime date;
  final String bucket;
  final String? holidayName;
  final bool today;
  final Color? marker;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = _bucketTone(bucket);
    final meta = _bucketMeta(bucket, holidayName);
    return Semantics(
      button: onTap != null,
      label: '${DateFormat('EEEE, d MMMM').format(date)}, ${meta.label}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: tone.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: today
              ? BorderSide(color: AppColors.primary, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: today && bucket == 'nonworking'
                          ? AppColors.primary
                          : tone.fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (marker != null)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: marker,
                        shape: BoxShape.circle,
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    Text(
                      DateFormat('EEE').format(cell.date),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: isToday ? AppColors.primary : AppColors.muted,
                      ),
                    ),
                    Text(
                      DateFormat('d').format(cell.date),
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: isToday ? AppColors.primary : AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
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
                        Flexible(
                          child: Text(
                            DateFormat('EEEE, d MMM').format(cell.date),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.33,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.15,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 6),
                          ProPill('Today',
                              color: AppColors.primary,
                              background: AppColors.primary.withOpacity(0.1)),
                        ],
                        if (cell.hasReg) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.flag_rounded,
                              size: 13, color: AppColors.warning),
                        ],
                      ],
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      ProPill(note.label, color: note.color, dot: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _bucketPill(cell.bucket, meta.label),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Color(0xFFB3C0C3)),
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
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: it.$1 == 'nonworking'
                      ? const Color(0xFFD8E5E8)
                      : _bucketMeta(it.$1).color.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                it.$2,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
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
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + mq.padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 14),
              Text(
                'Regularize ${DateFormat('d MMM yyyy').format(widget.date)}',
                style: _sheetTitleStyle,
              ),
              const SizedBox(height: 16),
              ProField(
                label: 'Requested status',
                child: DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.tune_rounded, size: 20),
                  ),
                  items: [
                    for (final s in _statuses)
                      DropdownMenuItem(value: s, child: Text(_attStatusLabel(s))),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'PRESENT'),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ProField(
                      label: 'Check-in',
                      child: _TimeField(
                        value: _checkIn,
                        onPick: (t) => setState(() => _checkIn = t),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ProField(
                      label: 'Check-out',
                      child: _TimeField(
                        value: _checkOut,
                        onPick: (t) => setState(() => _checkOut = t),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ProField(
                label: 'Reason',
                required: true,
                child: TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [TitleCaseTextFormatter()],
                  decoration: const InputDecoration(
                    hintText: 'What should be corrected?',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                ProNote(_error!, tone: ProNoteTone.bad),
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
  const _TimeField({required this.value, required this.onPick});
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
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.schedule_rounded, size: 20),
        ),
        child: Text(
          value == null ? 'Not set' : value!.format(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: value == null ? AppColors.muted : AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
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
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + mq.padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 14),
              Text(
                'Apply leave · ${DateFormat('d MMM yyyy').format(widget.date)}',
                style: _sheetTitleStyle,
              ),
              const SizedBox(height: 16),
              ProField(
                label: 'Leave type',
                required: true,
                child: types.when(
                  data: (list) => DropdownButtonFormField<String>(
                    value: _type,
                    isExpanded: true,
                    hint: const Text('Choose a leave type'),
                    decoration: const InputDecoration(
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
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12.5)),
                ),
              ),
              const SizedBox(height: 14),
              ProField(
                label: 'Reason',
                required: true,
                child: TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [TitleCaseTextFormatter()],
                  decoration: const InputDecoration(
                    hintText: 'Why do you need this day off?',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                ProNote(_error!, tone: ProNoteTone.bad),
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
