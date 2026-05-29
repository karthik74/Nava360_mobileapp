import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';
import 'location_tracker.dart';

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

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _busy = false;
  String? _statusMsg;
  bool _statusIsError = false;
  AttendanceRecord? _latestTodayRecord;
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

  Future<({double lat, double lng})?> _getCoords() async {
    bool services = await Geolocator.isLocationServiceEnabled();
    if (!services) {
      _show('Turn on Location to punch in/out.', error: true);
      return null;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      _show('Location permission denied. Enable it in settings.', error: true);
      return null;
    }
    if (perm == LocationPermission.denied) {
      _show('Location permission required.', error: true);
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  }

  Future<void> _punch({required bool isIn}) async {
    final user = ref.read(authUserProvider);
    final empId = user?.employeeId;
    if (empId == null) {
      _show('Your account is not linked to an employee.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _statusMsg = 'Reading your location…';
      _statusIsError = false;
    });
    final coords = await _getCoords();
    if (coords == null) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _statusMsg = isIn ? 'Checking in…' : 'Checking out…');
    final repo = ref.read(attendanceRepositoryProvider);
    final tracker = ref.read(locationTrackerProvider.notifier);
    try {
      final rec = isIn
          ? await repo.checkIn(empId,
              latitude: coords.lat, longitude: coords.lng)
          : await repo.checkOut(empId,
              latitude: coords.lat, longitude: coords.lng);
      if (mounted) {
        setState(() => _latestTodayRecord = rec);
      }
      // Start/stop the adaptive location tracker around the punch.
      if (isIn) {
        await tracker.start(empId);
      } else {
        await tracker.stop();
      }
      _show(isIn
          ? 'Checked in at ${_fmtTime(rec.checkIn)}'
          : 'Checked out at ${_fmtTime(rec.checkOut)}');
      ref.invalidate(_todayRecordsProvider);
    } catch (e) {
      _show(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String msg, {bool error = false}) {
    setState(() {
      _statusMsg = msg;
      _statusIsError = error;
    });
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

  DateTime? _parseLocalTime(String? iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fmtTimer(Duration? duration) {
    if (duration == null || duration.isNegative) {
      return '00:00:00';
    }
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Duration? _workDuration(AttendanceRecord? record) {
    if (record?.checkIn == null) return null;

    final checkIn = _parseLocalTime(record!.checkIn);
    if (checkIn == null) return null;

    final checkOut = _parseLocalTime(record.checkOut);
    if (checkOut != null) {
      final duration = checkOut.difference(checkIn);
      if (!duration.isNegative) return duration;
    }

    if (record.checkOut != null && record.workingHours != null) {
      return Duration(seconds: (record.workingHours! * 3600).round());
    }

    return _now.difference(checkIn);
  }

  AttendanceRecord? _visibleTodayRecord(
    AttendanceRecord? serverRecord,
    String today,
  ) {
    final localRecord =
        _latestTodayRecord?.date == today ? _latestTodayRecord : null;

    if (localRecord == null) return serverRecord;
    if (serverRecord == null) return localRecord;

    final localHasCheckOut = localRecord.checkOut != null;
    final serverHasCheckOut = serverRecord.checkOut != null;
    if (localHasCheckOut && !serverHasCheckOut) return localRecord;

    final localHasCheckIn = localRecord.checkIn != null;
    final serverHasCheckIn = serverRecord.checkIn != null;
    if (localHasCheckIn && !serverHasCheckIn) return localRecord;

    return serverRecord;
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(_todayRecordsProvider);
    final today = DateFormat('yyyy-MM-dd').format(_now);

    AttendanceRecord? serverTodayRec;
    int presentCount = 0;
    double totalHours = 0;
    records.whenData((list) {
      for (final r in list) {
        if (r.date == today) serverTodayRec = r;
        if (r.status == 'PRESENT') presentCount++;
        if (r.workingHours != null) totalHours += r.workingHours!;
      }
    });

    final todayRec = _visibleTodayRecord(serverTodayRec, today);
    final hasCheckedIn = todayRec?.checkIn != null;
    final hasCheckedOut = todayRec?.checkOut != null;
    final timerText = _fmtTimer(_workDuration(todayRec));

    final mq = MediaQuery.of(context);
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white.withOpacity(0.85),
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
          _HeroPunchCard(
            now: _now,
            todayRec: todayRec,
            hasCheckedIn: hasCheckedIn,
            hasCheckedOut: hasCheckedOut,
            busy: _busy,
            onPunch: _punch,
            timeFmt: _fmtTime,
            timerText: timerText,
          ),
          if (_statusMsg != null) ...[
            const SizedBox(height: 10),
            _StatusBanner(message: _statusMsg!, isError: _statusIsError),
          ],
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'This month',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                DateFormat('MMMM yyyy').format(_now),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
    );
  }
}

class _HeroPunchCard extends StatelessWidget {
  const _HeroPunchCard({
    required this.now,
    required this.todayRec,
    required this.hasCheckedIn,
    required this.hasCheckedOut,
    required this.busy,
    required this.onPunch,
    required this.timeFmt,
    required this.timerText,
  });

  final DateTime now;
  final AttendanceRecord? todayRec;
  final bool hasCheckedIn;
  final bool hasCheckedOut;
  final bool busy;
  final void Function({required bool isIn}) onPunch;
  final String Function(String?) timeFmt;
  final String timerText;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, d MMMM').format(now);
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
    final timerCaption = hasCheckedOut
        ? 'Shift complete - $timerText worked'
        : hasCheckedIn
            ? 'Checked in at ${timeFmt(todayRec?.checkIn)}'
            : 'Punch in to start the timer';

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
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
                    Colors.white.withOpacity(0.14),
                    Colors.transparent,
                    Colors.black.withOpacity(0.05),
                  ],
                  stops: const [0, 0.56, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: badgeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            badgeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  timerText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.0,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timerCaption,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TimeBlock(
                          icon: Icons.login_rounded,
                          label: 'Check-in',
                          value: timeFmt(todayRec?.checkIn),
                          active: hasCheckedIn,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white.withOpacity(0.18),
                      ),
                      Expanded(
                        child: _TimeBlock(
                          icon: Icons.logout_rounded,
                          label: 'Check-out',
                          value: timeFmt(todayRec?.checkOut),
                          active: hasCheckedOut,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _PunchButton(
                  hasCheckedIn: hasCheckedIn,
                  hasCheckedOut: hasCheckedOut,
                  busy: busy,
                  onPunch: onPunch,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Colors.white.withOpacity(active ? 1 : 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _PunchButton extends StatelessWidget {
  const _PunchButton({
    required this.hasCheckedIn,
    required this.hasCheckedOut,
    required this.busy,
    required this.onPunch,
  });

  final bool hasCheckedIn;
  final bool hasCheckedOut;
  final bool busy;
  final void Function({required bool isIn}) onPunch;

  @override
  Widget build(BuildContext context) {
    if (hasCheckedOut) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            SizedBox(width: 7),
            Text(
              "You're done for today",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final isCheckOut = hasCheckedIn;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: busy ? null : () => onPunch(isIn: !isCheckOut),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isCheckOut
                            ? Icons.logout_rounded
                            : Icons.fingerprint_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        isCheckOut ? 'Check out' : 'Check in',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
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
