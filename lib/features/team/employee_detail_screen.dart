import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../assets/assets_models.dart';
import '../assets/assets_repository.dart';
import '../attendance/attendance_models.dart';
import '../attendance/attendance_repository.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_repository.dart';
import '../chat/chat_thread_screen.dart';
import '../leaves/leave_models.dart';
import '../leaves/leave_repository.dart';
import '../performance/performance_tab.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import 'employee_detail_repository.dart';
import 'team_tracking_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Providers (one per data domain, keyed by employeeId)
// ─────────────────────────────────────────────────────────────────────────────

final _profileProvider =
    FutureProvider.autoDispose.family<EmployeeDetail, int>((ref, id) {
  return ref.watch(employeeDetailRepositoryProvider).getById(id);
});

/// Attendance records for the current calendar month (used for today's status
/// and the monthly present/absent/leave counts).
final _attendanceProvider =
    FutureProvider.autoDispose.family<List<AttendanceRecord>, int>((ref, id) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, 1);
  return ref.watch(attendanceRepositoryProvider).listForEmployee(
        id,
        from: _ymd(from),
        to: _ymd(now),
        size: 100,
      );
});

/// Record change history (Timeline tab). Only fetched for users who may see
/// the full profile (the endpoint needs EMPLOYEE_VIEW).
final _changeLogProvider =
    FutureProvider.autoDispose.family<List<EmployeeChangeLog>, int>((ref, id) {
  return ref.watch(employeeDetailRepositoryProvider).timeline(id);
});

final _tasksProvider =
    FutureProvider.autoDispose.family<List<Task>, int>((ref, id) {
  return ref.watch(taskRepositoryProvider).listForEmployee(id);
});

class _LeaveBundle {
  const _LeaveBundle(this.balance, this.requests);
  final EmployeeLeaveBalances? balance;
  final List<LeaveRequest> requests;
}

final _leaveProvider =
    FutureProvider.autoDispose.family<_LeaveBundle, int>((ref, id) async {
  final repo = ref.watch(leaveRepositoryProvider);
  EmployeeLeaveBalances? bal;
  try {
    bal = await repo.getBalance(id);
  } catch (_) {
    bal = null; // balance is best-effort; requests still render
  }
  final reqs = await repo.listForEmployee(id);
  return _LeaveBundle(bal, reqs);
});

class _LocationBundle {
  const _LocationBundle(this.pings, this.live, this.statusEvents);
  final List<TrackPing> pings;
  final LiveLocation? live;

  /// On/off transition history (newest first); first entry = current status.
  final List<LocationStatusEvent> statusEvents;

  LocationStatusEvent? get currentStatus =>
      statusEvents.isNotEmpty ? statusEvents.first : null;

  /// Current on/off state, preferring the status-history feed (what the web
  /// uses) and falling back to the live snapshot.
  String? get currentState => currentStatus?.state ?? live?.state;
}

final _locationProvider =
    FutureProvider.autoDispose.family<_LocationBundle, int>((ref, id) async {
  final repo = ref.watch(teamTrackingRepositoryProvider);
  final now = DateTime.now();
  final pings = await repo.memberDay(id, now);
  LiveLocation? live;
  try {
    live = await repo.getLive(id);
  } catch (_) {
    live = null; // live snapshot is optional
  }
  List<LocationStatusEvent> events = const [];
  try {
    events = await repo.statusHistory(
      id,
      from: now.subtract(const Duration(days: 30)),
      to: now,
    );
  } catch (_) {
    events = const []; // status history needs LOCATION_PING_VIEW; best-effort
  }
  return _LocationBundle(pings, live, events);
});

final _documentsProvider =
    FutureProvider.autoDispose.family<List<EmployeeDocument>, int>((ref, id) {
  return ref.watch(employeeDetailRepositoryProvider).documents(id);
});

final _assetsProvider =
    FutureProvider.autoDispose.family<List<AssetAssignment>, int>((ref, id) {
  return ref.watch(assetsRepositoryProvider).listForEmployee(id);
});

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({
    super.key,
    required this.employeeId,
    required this.name,
  });

  final int employeeId;
  final String name;

  static const _tabs = <(String, IconData)>[
    ('Overview', Icons.person_rounded),
    ('Attendance', Icons.fact_check_rounded),
    ('Location', Icons.place_rounded),
    ('Tasks', Icons.checklist_rounded),
    ('Leave', Icons.beach_access_rounded),
    ('Documents', Icons.folder_rounded),
    ('Assets', Icons.devices_other_rounded),
    ('Performance', Icons.insights_rounded),
    ('Timeline', Icons.timeline_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final canViewSensitive = (user?.hasRole(const {'ADMIN', 'HR'}) ?? false) ||
        (user?.hasPermission('EMPLOYEE_VIEW') ?? false);

    final tabBar = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      tabs: [for (final t in _tabs) Tab(height: 46, text: t.$1)],
    );

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Team member'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(_profileProvider(employeeId));
                ref.invalidate(_attendanceProvider(employeeId));
                ref.invalidate(_tasksProvider(employeeId));
                ref.invalidate(_leaveProvider(employeeId));
                ref.invalidate(_locationProvider(employeeId));
                ref.invalidate(_documentsProvider(employeeId));
                ref.invalidate(_assetsProvider(employeeId));
              },
            ),
          ],
        ),
        // The deep profile hero scrolls away; the section tabs stay pinned.
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProfileHeader(employeeId: employeeId, fallbackName: name),
              ),
            ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarHeader(tabBar),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _OverviewTab(
                employeeId: employeeId,
                canViewSensitive: canViewSensitive,
              ),
              _AttendanceTab(employeeId: employeeId),
              _LocationTab(employeeId: employeeId, name: name),
              _TasksTab(employeeId: employeeId, name: name),
              _LeaveTab(employeeId: employeeId),
              _DocumentsTab(
                employeeId: employeeId,
                canViewSensitive: canViewSensitive,
              ),
              _AssetsTab(employeeId: employeeId),
              _PerformanceTab(employeeId: employeeId),
              _TimelineTab(
                employeeId: employeeId,
                canViewChanges: canViewSensitive,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned section tab strip on the canvas colour.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: AppColors.bg, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeader oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile hero
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({required this.employeeId, required this.fallbackName});
  final int employeeId;
  final String fallbackName;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  bool _undoBusy = false;
  bool _chatBusy = false;

  Future<void> _call(String? number) async {
    final cleaned = number?.replaceAll(RegExp(r'[^0-9+#*]'), '') ?? '';
    if (cleaned.isEmpty) return;
    try {
      // Launched directly: canLaunchUrl reports false for tel: on Android
      // unless the DIAL intent is declared, even when a dialler exists.
      if (await launchUrl(Uri(scheme: 'tel', path: cleaned),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Could not open the dialler.')));
  }

  /// Open (or create) the direct chat with this employee.
  Future<void> _message() async {
    if (_chatBusy) return;
    setState(() => _chatBusy = true);
    try {
      final dm = await ref
          .read(chatRepositoryProvider)
          .getOrCreateDirect(widget.employeeId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatThreadScreen(conversation: dm)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open chat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _chatBusy = false);
    }
  }

  /// Same flow as the Attendance tab's "Undo check-out" card.
  Future<void> _undoCheckOut(AttendanceRecord? today) async {
    if (_undoBusy) return;
    final confirmed = await _confirmUndoCheckOut(context, today);
    if (!confirmed || !mounted) return;
    setState(() => _undoBusy = true);
    await _reopenCheckOut(
      context,
      ref,
      employeeId: widget.employeeId,
      onChanged: () => ref.invalidate(_attendanceProvider(widget.employeeId)),
    );
    if (mounted) setState(() => _undoBusy = false);
  }

  void _openTab(int index) => DefaultTabController.of(context).animateTo(index);

  @override
  Widget build(BuildContext context) {
    final employeeId = widget.employeeId;
    final async = ref.watch(_profileProvider(employeeId));
    final emp = async.asData?.value;
    final attAsync = ref.watch(_attendanceProvider(employeeId));
    final records = attAsync.asData?.value;
    final tasks = ref.watch(_tasksProvider(employeeId)).asData?.value;
    final canOverride =
        ref.watch(authUserProvider)?.hasPermission('ATTENDANCE_OVERRIDE') ??
            false;

    final name = emp?.fullName ?? widget.fallbackName;
    final role = emp == null
        ? null
        : [
            if ((emp.designation ?? '').isNotEmpty) emp.designation!,
            if ((emp.department ?? '').isNotEmpty) emp.department!,
            if ((emp.branchLabel ?? '').isNotEmpty) emp.branchLabel!,
          ].join(' · ');
    final joined = _parseYmd(emp?.joiningDate);
    final tags = <ProHeroTag>[
      if ((emp?.employeeCode ?? '').isNotEmpty)
        ProHeroTag(emp!.employeeCode!, icon: Icons.badge_rounded),
      if (emp != null)
        ProHeroTag(
          emp.active ? 'Active' : 'Inactive',
          tone: emp.active ? ProTagTone.ok : ProTagTone.neutral,
        ),
      if (joined != null)
        ProHeroTag('Since ${_months[joined.month - 1]} ${joined.year}'),
    ];

    // ── Today's status (live line) ──
    AttendanceRecord? today;
    final ymd = _ymd(DateTime.now());
    for (final r in records ?? const <AttendanceRecord>[]) {
      if (r.date == ymd) {
        today = r;
        break;
      }
    }
    final String liveText;
    final Color liveColor;
    if (records == null) {
      liveText = attAsync.hasError
          ? "Today's attendance couldn't be loaded"
          : "Loading today's attendance…";
      liveColor = Colors.white54;
    } else if (today != null && today.checkIn != null && today.checkOut == null) {
      liveText = 'Checked in at ${_fmtTime(today.checkIn)} · on the clock';
      liveColor = AppColors.live;
    } else if (today != null && today.checkIn != null) {
      final hrs = _fmtHours(today.workingHours);
      liveText = 'Checked in ${_fmtTime(today.checkIn)} · out '
          '${_fmtTime(today.checkOut)}${hrs == '—' ? '' : ' · $hrs'}';
      liveColor = const Color(0xFF7FC8D8);
    } else if (today != null) {
      final tone = StatusTone.forAttendance(today.status);
      liveText = 'Today: ${tone.label}';
      liveColor = today.status == 'ABSENT'
          ? const Color(0xFFE5484D)
          : const Color(0xFFF2B347);
    } else {
      liveText = 'No check-in today yet';
      liveColor = Colors.white54;
    }

    // ── KPIs from data the tabs already load ──
    final present = records?.where((r) => r.status == 'PRESENT').length ?? 0;
    final totalHours = records?.fold<double>(
            0, (sum, r) => sum + (r.workingHours ?? 0)) ??
        0;
    final done = tasks?.where((t) => t.status == 'DONE').length ?? 0;
    final month = _months[DateTime.now().month - 1];

    final checkedOut =
        today != null && today.checkIn != null && today.checkOut != null;
    final phone = emp?.phone;
    final hasPhone = (phone ?? '').replaceAll(RegExp(r'[^0-9+#*]'), '').isNotEmpty;

    final photo = _photoUrl(emp?.profileImageUrl);
    // Avatar ring follows today's state; grey while unknown / not checked in.
    final ring = liveColor == Colors.white54 ? Colors.white24 : liveColor;

    final kpis = ProKpiStrip(
      cells: [
        ProKpi(
          value: records == null ? '—' : '$present/${records.length}',
          label: 'Days present · $month',
          progress: records == null || records.isEmpty
              ? null
              : present / records.length,
          color: AppColors.success,
          onTap: () => _openTab(1),
        ),
        ProKpi(
          value: records == null ? '—' : _fmtHours(totalHours),
          label: 'Hours · $month',
          onTap: () => _openTab(1),
        ),
        ProKpi(
          value: tasks == null ? '—' : '$done/${tasks.length}',
          label: 'Tasks done',
          progress:
              tasks == null || tasks.isEmpty ? null : done / tasks.length,
          onTap: () => _openTab(3),
        ),
      ],
    );

    return ProHero(
      overlap: kpis,
      children: [
        if (photo == null)
          ProHeroIdentity(
            name: name,
            role: (role ?? '').isEmpty ? null : role,
            initials: ProAvatar.initialsOf(name),
            ringColor: ring,
            tags: tags,
          )
        else
          _PhotoIdentity(
            name: name,
            role: (role ?? '').isEmpty ? null : role,
            photoUrl: photo,
            ringColor: ring,
            tags: tags,
          ),
        ProLiveLine(text: liveText, color: liveColor),
        ProHeroActions(
          actions: [
            ProAction(
              icon: Icons.call_rounded,
              label: 'Call',
              primary: true,
              onTap: hasPhone ? () => _call(phone) : null,
            ),
            if (Branding.current.featureEnabled('FEATURE_CHAT'))
              ProAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Message',
                onTap: _chatBusy ? null : _message,
              ),
            ProAction(
              icon: Icons.my_location_rounded,
              label: 'Locate',
              onTap: () => _openTab(2),
            ),
            if (canOverride)
              ProAction(
                icon: Icons.undo_rounded,
                label: 'Undo out',
                onTap: _undoBusy || !checkedOut
                    ? null
                    : () => _undoCheckOut(today),
              ),
          ],
        ),
      ],
    );
  }
}

/// [ProHeroIdentity] layout with the employee's profile photo (initials show
/// while it loads or if it fails).
class _PhotoIdentity extends StatelessWidget {
  const _PhotoIdentity({
    required this.name,
    required this.photoUrl,
    required this.ringColor,
    required this.tags,
    this.role,
  });

  final String name;
  final String? role;
  final String photoUrl;
  final Color ringColor;
  final List<ProHeroTag> tags;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      ProAvatar.initialsOf(name),
      style: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: AppColors.deep,
      ),
    );
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: AppColors.deep, spreadRadius: 3),
              BoxShadow(color: ringColor, spreadRadius: 5),
            ],
          ),
          alignment: Alignment.center,
          child: Image.network(
            photoUrl,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Center(child: initials),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : Center(child: initials),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.55,
                  color: Colors.white,
                ),
              ),
              if (role != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    role!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Colors.white70,
                    ),
                  ),
                ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Wrap(spacing: 6, runSpacing: 6, children: tags),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Overview
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.employeeId, required this.canViewSensitive});
  final int employeeId;
  final bool canViewSensitive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_profileProvider(employeeId));
    return _TabScaffold(
      onRefresh: () async => ref.invalidate(_profileProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(height: 200),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_profileProvider(employeeId)),
        ),
        data: (e) => Column(
          children: [
            _SectionCard(
              title: 'Employee details',
              icon: Icons.person_outline_rounded,
              children: [
                _InfoRow(Icons.badge_outlined, 'Employee code', e.employeeCode),
                _InfoRow(Icons.work_outline_rounded,
                    Branding.current.term('designation'), e.designation),
                _InfoRow(Icons.apartment_rounded,
                    Branding.current.term('department'), e.department),
                _InfoRow(Icons.location_city_rounded,
                    Branding.current.term('branch'), e.branchLabel),
                _InfoRow(Icons.supervisor_account_rounded, 'Reporting manager',
                    e.reportingManagerName),
                _InfoRow(Icons.category_rounded, 'Employee type', e.employeeType),
                _InfoRow(
                  Icons.verified_user_rounded,
                  'Status',
                  e.active ? 'Active' : 'Inactive',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Contact',
              icon: Icons.contact_phone_outlined,
              children: [
                _InfoRow(Icons.phone_rounded, 'Mobile', e.phone),
                _InfoRow(Icons.email_rounded, 'Email', e.email),
                _InfoRow(Icons.event_available_rounded, 'Joining date',
                    _prettyDate(e.joiningDate)),
                _InfoRow(Icons.cake_rounded, 'Date of birth',
                    _prettyDate(e.dateOfBirth)),
                _InfoRow(Icons.place_outlined, 'Address', e.address),
              ],
            ),
            // Bank & statutory section removed (2026-07-04): account/PF/UAN/ESI
            // details stay web-only and are not shown in the mobile team view.
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Attendance
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceTab extends ConsumerWidget {
  const _AttendanceTab({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_attendanceProvider(employeeId));
    return _TabScaffold(
      onRefresh: () async => ref.invalidate(_attendanceProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(height: 200),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_attendanceProvider(employeeId)),
        ),
        data: (records) {
          final today = _ymd(DateTime.now());
          AttendanceRecord? todayRec;
          for (final r in records) {
            if (r.date == today) {
              todayRec = r;
              break;
            }
          }
          final present =
              records.where((r) => r.status == 'PRESENT').length;
          final halfDay =
              records.where((r) => r.status == 'HALF_DAY').length;
          final absent = records.where((r) => r.status == 'ABSENT').length;
          final leave = records.where((r) => r.status == 'ON_LEAVE').length;
          final tone = StatusTone.forAttendance(todayRec?.status ?? 'ABSENT');

          return Column(
            children: [
              _SectionCard(
                title: "Today",
                icon: Icons.today_rounded,
                trailing: todayRec == null
                    ? ProPill.neutral('No record')
                    : _tonePill(tone),
                children: [
                  _InfoRow(Icons.login_rounded, 'Check-in',
                      _fmtTime(todayRec?.checkIn)),
                  _InfoRow(Icons.logout_rounded, 'Check-out',
                      _fmtTime(todayRec?.checkOut)),
                  _InfoRow(Icons.timelapse_rounded, 'Working hours',
                      _fmtHours(todayRec?.workingHours)),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'This month',
                icon: Icons.calendar_month_rounded,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MonthStat(
                          label: 'Present',
                          value: present,
                          color: AppColors.success,
                        ),
                      ),
                      Expanded(
                        child: _MonthStat(
                          label: 'Absent',
                          value: absent,
                          color: AppColors.danger,
                        ),
                      ),
                      Expanded(
                        child: _MonthStat(
                          label: 'On leave',
                          value: leave,
                          color: AppColors.info,
                        ),
                      ),
                      Expanded(
                        child: _MonthStat(
                          label: 'Half days',
                          value: halfDay,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Manager / HR: set one day's status by hand (e.g. mark Absent).
              if (ref.watch(authUserProvider)?.hasPermission('ATTENDANCE_OVERRIDE') ?? false) ...[
                _MarkAttendanceCard(
                  employeeId: employeeId,
                  records: records,
                  onChanged: () => ref.invalidate(_attendanceProvider(employeeId)),
                ),
                const SizedBox(height: 12),
                // Manager / HR: the employee checked out by mistake — put them
                // back on the clock so they can check out again later.
                _UndoCheckOutCard(
                  employeeId: employeeId,
                  records: records,
                  onChanged: () => ref.invalidate(_attendanceProvider(employeeId)),
                ),
              ],
              const SizedBox(height: 4),
              // The attendance API does not expose a per-day "late mark" flag,
              // so late marks can't be derived reliably here.
              // TODO: surface late marks once a backend late-mark field exists.
              const _NoteCard(
                text:
                    'Late marks aren\'t tracked by the attendance API yet, so they\'re not shown.',
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "Mark attendance": pick a day (today or earlier), Absent or Half day, an
/// optional note, and save — the manager's decision replaces whatever the
/// punches produced for that day. Marking Absent also withdraws approved
/// leave / regularization on that date, which the server reports back in its
/// message. Marking a day Present is deliberately NOT offered: that goes
/// through the regularization request/approval flow.
class _MarkAttendanceCard extends ConsumerStatefulWidget {
  const _MarkAttendanceCard({
    required this.employeeId,
    required this.records,
    required this.onChanged,
  });
  final int employeeId;
  final List<AttendanceRecord> records;
  final VoidCallback onChanged;

  @override
  ConsumerState<_MarkAttendanceCard> createState() => _MarkAttendanceCardState();
}

class _MarkAttendanceCardState extends ConsumerState<_MarkAttendanceCard> {
  DateTime _date = DateTime.now();
  String _status = 'ABSENT';
  final _notes = TextEditingController();
  bool _busy = false;

  // No "Present" here on purpose: a missed punch is fixed through the
  // regularization request/approval flow, not by a manager's override.
  static const _options = [
    ('ABSENT', 'Absent', Icons.person_off_rounded),
    ('HALF_DAY', 'Half day', Icons.hourglass_bottom_rounded),
  ];

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String? get _currentStatus {
    final ymd = _ymd(_date);
    for (final r in widget.records) {
      if (r.date == ymd) return r.status;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 92)),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    final label = _options.firstWhere((o) => o.$1 == _status).$2;
    final day = DateFormat('EEE, d MMM yyyy').format(_date);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark $label?'),
        content: Text(
          _status == 'ABSENT'
              ? 'This will record $day as Absent. Any approved leave or '
                  'regularization on that day will be withdrawn.'
              : 'This will record $day as $label, replacing whatever the '
                  'punches produced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _status == 'ABSENT' ? _destructive() : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Mark $label'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final message =
          await ref.read(attendanceRepositoryProvider).overrideAttendance(
                employeeId: widget.employeeId,
                date: _ymd(_date),
                status: _status,
                notes: _notes.text,
              );
      if (!mounted) return;
      _notes.clear();
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update attendance: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentStatus;
    final currentTone =
        current == null ? null : StatusTone.forAttendance(current);
    return _SectionCard(
      title: 'Mark attendance',
      icon: Icons.edit_calendar_rounded,
      trailing: currentTone == null
          ? ProPill.neutral('No record')
          : _tonePill(currentTone),
      children: [
        const SizedBox(height: 4),
        ProField(
          label: 'Day',
          child: InkWell(
            onTap: _busy ? null : _pickDate,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: InputDecorator(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.event_rounded, size: 20),
                suffixIcon: Icon(Icons.expand_more_rounded, size: 20),
              ),
              child: Text(
                DateFormat('EEE, d MMM yyyy').format(_date),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ProField(
          label: 'Mark as',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _options)
                ChoiceChip(
                  avatar: Icon(o.$3,
                      size: 16,
                      color: _status == o.$1 ? Colors.white : AppColors.muted),
                  label: Text(o.$2),
                  selected: _status == o.$1,
                  labelStyle: TextStyle(
                    fontWeight:
                        _status == o.$1 ? FontWeight.w600 : FontWeight.w500,
                    color: _status == o.$1 ? Colors.white : AppColors.inkSoft,
                  ),
                  onSelected:
                      _busy ? null : (_) => setState(() => _status = o.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ProField(
          label: 'Note (optional)',
          child: TextField(
            controller: _notes,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Did not report to branch',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            style: _status == 'ABSENT' ? _destructive() : null,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_busy
                ? 'Saving…'
                : 'Mark ${_options.firstWhere((o) => o.$1 == _status).$2}'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'A missed punch is fixed through a regularization request, so '
          'Present is not offered here.',
          style: AppText.caption,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// "Undo check-out": the employee checked out by mistake. Clears today's
/// check-out (the check-in is kept) so they are checked in again and can check
/// out properly later. Enabled only while today's record is actually checked
/// out; the server applies the same scope rule as Mark attendance.
class _UndoCheckOutCard extends ConsumerStatefulWidget {
  const _UndoCheckOutCard({
    required this.employeeId,
    required this.records,
    required this.onChanged,
  });
  final int employeeId;
  final List<AttendanceRecord> records;
  final VoidCallback onChanged;

  @override
  ConsumerState<_UndoCheckOutCard> createState() => _UndoCheckOutCardState();
}

class _UndoCheckOutCardState extends ConsumerState<_UndoCheckOutCard> {
  bool _busy = false;

  AttendanceRecord? get _today {
    final ymd = _ymd(DateTime.now());
    for (final r in widget.records) {
      if (r.date == ymd) return r;
    }
    return null;
  }

  String _hhmm(String? iso) => _hhmmA(iso);

  Future<void> _undo() async {
    final today = _today;
    final confirmed = await _confirmUndoCheckOut(context, today);
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await _reopenCheckOut(
        context,
        ref,
        employeeId: widget.employeeId,
        onChanged: widget.onChanged,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final checkedOut = today != null && today.checkIn != null && today.checkOut != null;
    final String state;
    if (today == null || today.checkIn == null) {
      state = 'No check-in today';
    } else if (today.checkOut == null) {
      state = 'Checked in at ${_hhmm(today.checkIn)} — still on the clock';
    } else {
      state = 'Checked in ${_hhmm(today.checkIn)} · checked out ${_hhmm(today.checkOut)}';
    }
    return _SectionCard(
      title: 'Undo check-out',
      icon: Icons.history_toggle_off_rounded,
      trailing: checkedOut ? ProPill.info('Checked out') : null,
      children: [
        const SizedBox(height: 4),
        Text(
          state,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'For an employee who checked out by mistake: clears today\'s '
          'check-out so they can check out again later.',
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy || !checkedOut ? null : _undo,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.undo_rounded, size: 18),
            label: Text(_busy ? 'Undoing…' : 'Undo check-out'),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

String _hhmmA(String? iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso);
  return dt == null ? iso : DateFormat('h:mm a').format(dt);
}

/// "Undo today's check-out?" confirmation, shared by the Attendance tab card
/// and the hero action. Returns true when the manager confirms.
Future<bool> _confirmUndoCheckOut(
    BuildContext context, AttendanceRecord? today) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Undo today's check-out?"),
      content: Text(
        'The check-out at ${_hhmmA(today?.checkOut)} will be cleared and the '
        'employee will be checked in again (check-in ${_hhmmA(today?.checkIn)} '
        'is kept), so they can check out properly later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Undo check-out'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Clears today's check-out for [employeeId] and reports the server message.
Future<void> _reopenCheckOut(
  BuildContext context,
  WidgetRef ref, {
  required int employeeId,
  required VoidCallback onChanged,
}) async {
  try {
    final message = await ref
        .read(attendanceRepositoryProvider)
        .reopenCheckOut(employeeId: employeeId);
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not undo the check-out: $e')),
    );
  }
}

ButtonStyle _destructive() => FilledButton.styleFrom(
      backgroundColor: AppColors.dangerTint,
      foregroundColor: AppColors.danger,
    );


// ─────────────────────────────────────────────────────────────────────────────
// 3. Location
// ─────────────────────────────────────────────────────────────────────────────

class _LocationTab extends ConsumerStatefulWidget {
  const _LocationTab({required this.employeeId, required this.name});
  final int employeeId;
  final String name;

  @override
  ConsumerState<_LocationTab> createState() => _LocationTabState();
}

class _LocationTabState extends ConsumerState<_LocationTab> {
  bool _locating = false;
  Timer? _pollTimer;

  /// Latest live snapshot from the HR live endpoints (preferred over the
  /// background team snapshot once the user has requested a live fix).
  LiveLocation? _live;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool _routeBusy = false;

  /// "Route map": open today's trail straight in Google Maps as directions
  /// (origin → up to 8 waypoints → destination), instead of an in-app screen.
  /// Google's directions URL accepts only a handful of waypoints, so a day's
  /// trail is thinned evenly first.
  Future<void> _openTodaysRouteInMaps() async {
    if (_routeBusy) return;
    setState(() => _routeBusy = true);
    try {
      final pings = await ref
          .read(teamTrackingRepositoryProvider)
          .memberDay(widget.employeeId, DateTime.now());
      if (!mounted) return;
      if (pings.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pings.isEmpty
                ? 'No location pings for ${widget.name} today yet.'
                : 'Only one ping so far today — not enough for a route.'),
          ),
        );
        return;
      }
      final pts = _thin(pings, 10); // origin + ≤8 waypoints + destination
      final origin = pts.first;
      final dest = pts.last;
      final waypoints = pts
          .sublist(1, pts.length - 1)
          .map((p) => '${p.latitude},${p.longitude}')
          .join('|');
      final url = StringBuffer('https://www.google.com/maps/dir/?api=1')
        ..write('&origin=${origin.latitude},${origin.longitude}')
        ..write('&destination=${dest.latitude},${dest.longitude}')
        ..write('&travelmode=driving');
      if (waypoints.isNotEmpty) url.write('&waypoints=$waypoints');
      final ok = await launchUrl(Uri.parse(url.toString()),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not load today's route: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _routeBusy = false);
    }
  }

  /// Evenly picks [max] points from [pts], always keeping the first and last.
  static List<TrackPing> _thin(List<TrackPing> pts, int max) {
    if (pts.length <= max) return pts;
    final step = (pts.length - 1) / (max - 1);
    return List.generate(max, (i) => pts[(i * step).round()]);
  }

  /// Open the given coordinates in Google Maps (external app/browser).
  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Ask the employee's app for its current position and auto-update the latest
  /// position as it answers. Mirrors the web "Live location" button:
  /// POST .../live-request then poll .../live until responded / not pending /
  /// ~32s cap.
  Future<void> _requestLive() async {
    final repo = ref.read(teamTrackingRepositoryProvider);
    setState(() => _locating = true);
    LiveLocation initial;
    try {
      initial = await repo.requestLiveDirect(widget.employeeId);
    } catch (_) {
      if (mounted) {
        setState(() => _locating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not request live location')),
        );
      }
      return;
    }
    if (mounted) setState(() => _live = initial);
    // The backend already has a final answer (the app responded, or the wait
    // window is closed) — show it without polling.
    if (initial.responded || !initial.pending) {
      _finishLive(initial);
      return;
    }
    // Otherwise poll until the app answers, pending clears, or a ~32s cap.
    final startedAt = DateTime.now();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (t) async {
      try {
        final l = await repo.getLiveDirect(widget.employeeId);
        if (mounted) setState(() => _live = l);
        if (l.responded ||
            !l.pending ||
            DateTime.now().difference(startedAt) >
                const Duration(seconds: 32)) {
          t.cancel();
          _finishLive(l);
        }
      } catch (_) {
        // transient network error — keep polling
      }
    });
  }

  /// Surface the final live-location outcome — the backend's human-readable
  /// message — and refresh the route pings so a fresh fix shows on the map too.
  void _finishLive(LiveLocation l) {
    if (!mounted) return;
    setState(() => _locating = false);
    ref.invalidate(_locationProvider(widget.employeeId));
    final hasCoords = l.latitude != null && l.longitude != null;
    final msg = l.message.trim().isNotEmpty
        ? l.message.trim()
        : (hasCoords ? 'Live location updated' : 'No live location available');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final employeeId = widget.employeeId;
    final async = ref.watch(_locationProvider(employeeId));
    return _TabScaffold(
      onRefresh: () async => ref.invalidate(_locationProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(height: 200),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_locationProvider(employeeId)),
        ),
        data: (b) {
          final pings = b.pings;
          final last = pings.isNotEmpty ? pings.last : null;
          final distanceKm = _routeDistanceKm(pings);
          final visits =
              pings.where((p) => (p.referenceTitle ?? '').isNotEmpty).length;
          final currentState = b.currentState;
          final locTone = _locationStateTone(currentState);

          // Prefer a freshly-requested live fix over the background snapshot
          // and the last route ping, so the latest position auto-updates.
          final live = _live ?? b.live;
          final lat = live?.latitude ?? last?.latitude;
          final lng = live?.longitude ?? last?.longitude;
          final updatedAt = live?.respondedAt ?? last?.recordedAt;
          final reason = (live?.reason ?? '').trim();
          final hasCoords = lat != null && lng != null;

          return Column(
            children: [
              // Prominent current ON / OFF status (from the on/off history feed).
              _LocationStatusBanner(
                state: currentState,
                changedAt: b.currentStatus?.occurredAt,
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Current location',
                icon: Icons.my_location_rounded,
                trailing: _tonePill(locTone),
                children: [
                  _InfoRow(
                    Icons.place_rounded,
                    'Latest position',
                    hasCoords
                        ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                        : null,
                    onTap: hasCoords ? () => _openInMaps(lat, lng) : null,
                  ),
                  _InfoRow(Icons.update_rounded, 'Last updated',
                      updatedAt == null ? null : _fmtDateTime(updatedAt)),
                  if (reason.isNotEmpty)
                    _InfoRow(
                        Icons.info_outline_rounded, 'Reason', reason),
                  // Final result of a "Get Live Location" request.
                  if (_live != null) _LiveResultNote(live: _live!),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _locating ? null : _requestLive,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.gps_fixed_rounded, size: 18),
                  label: Text(_locating ? 'Locating…' : 'Get live location'),
                ),
              ),
              const SizedBox(height: 12),
              _StatStrip(cells: [
                _StatCell(
                  label: 'Distance today',
                  value: distanceKm == null
                      ? '—'
                      : '${distanceKm.toStringAsFixed(1)} km',
                  color: AppColors.primary,
                ),
                _StatCell(
                  label: 'Field visits',
                  value: '$visits',
                  color: AppColors.accent,
                ),
              ]),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    ProIconWell(icon: Icons.map_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "Today's route on the map",
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _routeBusy ? null : _openTodaysRouteInMaps,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: _routeBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.navigation_rounded, size: 16),
                      label: Text(_routeBusy ? 'Opening…' : 'Route map'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A prominent ON / OFF banner for the employee's current location-tracking
/// status, derived from the on/off history feed. ON is green, any off-state is
/// red, and an unknown/no-data state is muted.
/// Tinted note showing the outcome message of a live-location request
/// (e.g. "No response from the app — the employee may be offline…").
class _LiveResultNote extends StatelessWidget {
  const _LiveResultNote({required this.live});
  final LiveLocation live;

  @override
  Widget build(BuildContext context) {
    final hasCoords = live.latitude != null && live.longitude != null;
    final color = hasCoords
        ? AppColors.success
        : (live.pending ? AppColors.info : AppColors.warning);
    final text = live.message.trim().isNotEmpty
        ? live.message.trim()
        : (hasCoords ? 'Live location updated' : 'No live location available');
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasCoords
                ? Icons.check_circle_rounded
                : (live.pending
                    ? Icons.hourglass_top_rounded
                    : Icons.info_outline_rounded),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationStatusBanner extends StatelessWidget {
  const _LocationStatusBanner({required this.state, this.changedAt});
  final String? state;
  final DateTime? changedAt;

  @override
  Widget build(BuildContext context) {
    final on = state == 'ON';
    final unknown = state == null || state == 'UNKNOWN';
    final color = on
        ? AppColors.success
        : unknown
            ? AppColors.muted
            : AppColors.danger;
    final badgeText = on ? 'ON' : (unknown ? '—' : 'OFF');
    final tone = _locationStateTone(state);
    final subtitle = changedAt != null
        ? 'Since ${_fmtDateTime(changedAt!)}'
        : tone.label;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ProIconWell(
            icon: on ? Icons.location_on_rounded : Icons.location_off_rounded,
            color: color,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location status',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                const SizedBox(height: 1),
                Text(
                  tone.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
                if (changedAt != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // ON / OFF pill with a status dot (pulses while tracking).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (on)
                  ProPulseDot(color: color, size: 7)
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 6),
                Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: 0.4,
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

// ─────────────────────────────────────────────────────────────────────────────
// 4. Tasks
// ─────────────────────────────────────────────────────────────────────────────

class _TasksTab extends ConsumerWidget {
  const _TasksTab({required this.employeeId, required this.name});
  final int employeeId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_tasksProvider(employeeId));
    return _TabScaffold(
      onRefresh: () async => ref.invalidate(_tasksProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(height: 200),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_tasksProvider(employeeId)),
        ),
        data: (tasks) {
          final pending = tasks.where((t) => t.status == 'TODO').length;
          final inProgress =
              tasks.where((t) => t.status == 'IN_PROGRESS').length;
          final completed = tasks.where((t) => t.status == 'DONE').length;
          final overdue = tasks.where(_isOverdue).length;

          return Column(
            children: [
              _StatStrip(cells: [
                _StatCell(
                  label: 'Pending',
                  value: '$pending',
                  color: AppColors.faint,
                ),
                _StatCell(
                  label: 'In progress',
                  value: '$inProgress',
                  color: AppColors.info,
                ),
                _StatCell(
                  label: 'Completed',
                  value: '$completed',
                  color: AppColors.success,
                ),
                _StatCell(
                  label: 'Overdue',
                  value: '$overdue',
                  color: AppColors.danger,
                ),
              ]),
              const SizedBox(height: 16),
              if (tasks.isEmpty)
                const AppEmptyState(
                  icon: Icons.checklist_rounded,
                  message: 'No tasks assigned to this employee.',
                )
              else ...[
                const ProSectionHeader(title: 'Recent tasks'),
                const SizedBox(height: 10),
                ProListGroup(
                  children: [for (final t in tasks.take(5)) _TaskCard(t: t)],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _AllTasksScreen(
                          employeeId: employeeId,
                          name: name,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.list_alt_rounded, size: 18),
                    label: Text('View all ${tasks.length} tasks'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.t});
  final Task t;

  @override
  Widget build(BuildContext context) {
    final tone = _taskTone(t.status);
    final overdue = _isOverdue(t);
    final due = t.dueDate == null
        ? (t.taskCode ?? 'No due date')
        : 'Due ${_fmtDate(t.dueDate!)}';
    return ProListRow(
      leading: ProIconWell(
        icon: overdue ? Icons.event_busy_rounded : Icons.event_rounded,
        color: overdue ? AppColors.danger : tone.color,
      ),
      title: t.title,
      titleMaxLines: 2,
      subtitle: overdue ? 'Overdue · $due' : due,
      pill: _tonePill(tone),
    );
  }
}

class _AllTasksScreen extends ConsumerWidget {
  const _AllTasksScreen({required this.employeeId, required this.name});
  final int employeeId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_tasksProvider(employeeId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text('$name · Tasks')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(_tasksProvider(employeeId)),
          ),
        ),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: AppEmptyState(
                icon: Icons.checklist_rounded,
                message: 'No tasks assigned to this employee.',
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 14, 16, MediaQuery.of(context).padding.bottom + 24),
            children: [
              ProSectionHeader(
                title: 'All tasks · ${tasks.length}',
                small: true,
              ),
              const SizedBox(height: 8),
              ProListGroup(
                children: [for (final t in tasks) _TaskCard(t: t)],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Leave
// ─────────────────────────────────────────────────────────────────────────────

class _LeaveTab extends ConsumerWidget {
  const _LeaveTab({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leaveProvider(employeeId));
    return _TabScaffold(
      onRefresh: () async => ref.invalidate(_leaveProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(height: 200),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_leaveProvider(employeeId)),
        ),
        data: (b) {
          final reqs = b.requests;
          final pending = reqs.where((r) => r.status == 'PENDING').length;
          final approved = reqs.where((r) => r.status == 'APPROVED').length;
          final rejected = reqs.where((r) => r.status == 'REJECTED').length;
          final today = _ymd(DateTime.now());
          final upcoming = reqs
              .where((r) => r.status == 'APPROVED' && r.fromDate.compareTo(today) >= 0)
              .toList()
            ..sort((a, b) => a.fromDate.compareTo(b.fromDate));

          return Column(
            children: [
              _StatStrip(cells: [
                _StatCell(
                  label: 'Pending',
                  value: '$pending',
                  color: AppColors.warning,
                ),
                _StatCell(
                  label: 'Approved',
                  value: '$approved',
                  color: AppColors.success,
                ),
                _StatCell(
                  label: 'Rejected',
                  value: '$rejected',
                  color: AppColors.danger,
                ),
                _StatCell(
                  label: 'Upcoming',
                  value: '${upcoming.length}',
                  color: AppColors.info,
                ),
              ]),
              const SizedBox(height: 16),
              const ProSectionHeader(title: 'Leave balance'),
              const SizedBox(height: 10),
              if (b.balance == null || b.balance!.balances.isEmpty)
                const GlassCard(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: _MutedLine('No balance configured.'),
                  ),
                )
              else
                ProListGroup(
                  children: [
                    for (final bal in b.balance!.balances)
                      _BalanceRow(bal: bal),
                  ],
                ),
              const SizedBox(height: 16),
              if (upcoming.isNotEmpty) ...[
                const ProSectionHeader(title: 'Upcoming leave'),
                const SizedBox(height: 10),
                ProListGroup(
                  children: [
                    for (final r in upcoming.take(3)) _LeaveCard(r: r),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              const ProSectionHeader(title: 'Recent requests'),
              const SizedBox(height: 10),
              if (reqs.isEmpty)
                const AppEmptyState(
                  icon: Icons.beach_access_rounded,
                  message: 'No leave requests on record.',
                )
              else
                ProListGroup(
                  children: [for (final r in reqs.take(8)) _LeaveCard(r: r)],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.bal});
  final LeaveBalance bal;

  @override
  Widget build(BuildContext context) {
    final allowance = bal.allowanceDays ?? 0;
    final balance = bal.balanceDays ?? (allowance - bal.usedDays);
    final ratio = allowance <= 0 ? 0.0 : (bal.usedDays / allowance).clamp(0.0, 1.0);
    return ProProgressRow(
      icon: Icons.beach_access_rounded,
      label: bal.leaveTypeLabel,
      value: '$balance / $allowance left',
      progress: ratio.toDouble(),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({required this.r});
  final LeaveRequest r;

  @override
  Widget build(BuildContext context) {
    final tone = StatusTone.forLeave(r.status);
    return ProListRow(
      leading: ProIconWell(icon: Icons.beach_access_rounded, color: tone.color),
      title: '${r.leaveType} · ${r.numberOfDays ?? '?'} day(s)',
      subtitle: '${r.fromDate}  →  ${r.toDate}',
      pill: _tonePill(tone),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Documents (role-gated)
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentsTab extends ConsumerWidget {
  const _DocumentsTab({required this.employeeId, required this.canViewSensitive});
  final int employeeId;
  final bool canViewSensitive;

  static const _expected = <(String, String, IconData)>[
    ('AADHAAR', 'Aadhaar', Icons.badge_rounded),
    ('PAN', 'PAN card', Icons.credit_card_rounded),
    ('BANK', 'Bank details / passbook', Icons.account_balance_rounded),
    ('APPOINTMENT', 'Appointment letter', Icons.description_rounded),
    ('ID', 'ID proof', Icons.perm_identity_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canViewSensitive) {
      return const _TabScaffold(
        child: AppEmptyState(
          icon: Icons.lock_rounded,
          message:
              'Documents are visible to HR / Admin only. You don\'t have access to this employee\'s documents.',
        ),
      );
    }
    final async = ref.watch(_documentsProvider(employeeId));
    return _TabScaffold(
      onRefresh: () async => ref.invalidate(_documentsProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(height: 200),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_documentsProvider(employeeId)),
        ),
        data: (docs) {
          bool has(String key) => docs.any(
              (d) => d.docType.toUpperCase().contains(key));
          // Documents that don't fall into one of the expected buckets.
          final extras = docs.where((d) {
            final up = d.docType.toUpperCase();
            return !_expected.any((e) => up.contains(e.$1));
          }).toList();

          final have = _expected.where((e) => has(e.$1)).length;
          return Column(
            children: [
              ProSectionHeader(
                title: 'Required documents',
                trailing: ProPill.neutral('$have of ${_expected.length}'),
              ),
              const SizedBox(height: 10),
              ProListGroup(
                children: [
                  for (final e in _expected)
                    _DocStatusRow(
                      icon: e.$3,
                      label: e.$2,
                      available: has(e.$1),
                    ),
                ],
              ),
              if (extras.isNotEmpty) ...[
                const SizedBox(height: 16),
                const ProSectionHeader(title: 'Other documents'),
                const SizedBox(height: 10),
                ProListGroup(
                  children: [
                    for (final d in extras)
                      _DocStatusRow(
                        icon: Icons.insert_drive_file_rounded,
                        label: d.docTypeLabel ?? d.label ?? d.docType,
                        available: true,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              const ProNote(
                'Only HR, Admin and people with employee-view access can see '
                'these documents.',
                icon: Icons.lock_outline_rounded,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DocStatusRow extends StatelessWidget {
  const _DocStatusRow({
    required this.icon,
    required this.label,
    required this.available,
  });
  final IconData icon;
  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    return ProListRow(
      leading: ProIconWell(
        icon: icon,
        color: available ? AppColors.primary : null,
      ),
      title: label,
      pill: available ? ProPill.ok('Available') : ProPill.neutral('Missing'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Assets
// ─────────────────────────────────────────────────────────────────────────────

class _AssetsTab extends ConsumerWidget {
  const _AssetsTab({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_assetsProvider(employeeId));
    return _TabScaffold(
      onRefresh: () async => ref.invalidate(_assetsProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(height: 200),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(_assetsProvider(employeeId)),
        ),
        data: (assets) {
          if (assets.isEmpty) {
            return const AppEmptyState(
              icon: Icons.devices_other_rounded,
              message: 'No assets are assigned to this employee.',
            );
          }
          return Column(
            children: [
              ProSectionHeader(
                title: 'Assigned assets · ${assets.length}',
                small: true,
              ),
              const SizedBox(height: 8),
              ProListGroup(
                children: [for (final a in assets) _AssetCard(a: a)],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.a});
  final AssetAssignment a;

  @override
  Widget build(BuildContext context) {
    final tone = _assetTone(a.status);
    final sub = <String>[
      if (a.assetTag.isNotEmpty) a.assetTag,
      if ((a.serialNumber ?? '').isNotEmpty) 'SN ${a.serialNumber}',
      if ((a.imeiNumber ?? '').isNotEmpty) 'IMEI ${a.imeiNumber}',
    ].join(' · ');
    return ProListRow(
      leading: ProIconWell(
        icon: _assetIcon(a.assetName),
        color: AppColors.primary,
      ),
      title: a.assetName,
      subtitle: sub.isEmpty ? null : sub,
      pill: _tonePill(tone),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. Performance (FO scorecard — delegates to the shared performance tab body)
// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceTab extends StatelessWidget {
  const _PerformanceTab({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context) {
    // `nested`: lives under the pinned tab strip of the NestedScrollView.
    return PerformanceTabBody(employeeId: employeeId, nested: true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. Timeline (composed client-side from the other domains)
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineEvent {
  const _TimelineEvent(this.time, this.icon, this.color, this.title, this.subtitle);
  final DateTime time;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
}

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab({required this.employeeId, required this.canViewChanges});
  final int employeeId;

  /// Whether the caller may load the record change history (EMPLOYEE_VIEW).
  final bool canViewChanges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Record changes come from the backend change log; the activity feed below
    // is still composed client-side from the other domains.
    final changes = canViewChanges
        ? ref.watch(_changeLogProvider(employeeId))
        : const AsyncValue<List<EmployeeChangeLog>>.data(<EmployeeChangeLog>[]);
    final att = ref.watch(_attendanceProvider(employeeId));
    final tasks = ref.watch(_tasksProvider(employeeId));
    final leave = ref.watch(_leaveProvider(employeeId));
    final assets = ref.watch(_assetsProvider(employeeId));
    final loc = ref.watch(_locationProvider(employeeId));

    final anyLoading = att.isLoading ||
        tasks.isLoading ||
        leave.isLoading ||
        assets.isLoading ||
        loc.isLoading;

    final events = <_TimelineEvent>[];

    for (final r in att.asData?.value ?? const <AttendanceRecord>[]) {
      final ci = _parseIso(r.checkIn);
      if (ci != null) {
        events.add(_TimelineEvent(ci, Icons.login_rounded, AppColors.success,
            'Checked in', r.date));
      }
      final co = _parseIso(r.checkOut);
      if (co != null) {
        events.add(_TimelineEvent(co, Icons.logout_rounded, AppColors.warning,
            'Checked out', r.date));
      }
    }
    for (final t in tasks.asData?.value ?? const <Task>[]) {
      if (t.status == 'DONE' && t.completedAt != null) {
        events.add(_TimelineEvent(t.completedAt!, Icons.task_alt_rounded,
            AppColors.success, 'Task completed', t.title));
      } else if (t.createdAt != null) {
        events.add(_TimelineEvent(t.createdAt!, Icons.assignment_rounded,
            AppColors.info, 'Task assigned', t.title));
      }
    }
    for (final r in leave.asData?.value.requests ?? const <LeaveRequest>[]) {
      final d = _parseYmd(r.fromDate);
      if (d != null) {
        events.add(_TimelineEvent(d, Icons.beach_access_rounded, AppColors.info,
            'Leave applied', '${r.leaveType} · ${r.fromDate} → ${r.toDate}'));
      }
    }
    for (final a in assets.asData?.value ?? const <AssetAssignment>[]) {
      if (a.assignedDate != null) {
        events.add(_TimelineEvent(a.assignedDate!, Icons.devices_other_rounded,
            AppColors.primary, 'Asset assigned', a.assetName));
      }
    }
    final pings = loc.asData?.value.pings ?? const <TrackPing>[];
    if (pings.isNotEmpty) {
      final last = pings.last;
      events.add(_TimelineEvent(last.recordedAt, Icons.place_rounded,
          AppColors.accent, 'Location update',
          last.referenceTitle ?? 'GPS position recorded'));
    }

    events.sort((a, b) => b.time.compareTo(a.time));
    final top = events.take(40).toList();

    final activity = top.isEmpty
        ? (anyLoading
            ? const AppLoadingBlock(height: 200)
            : const AppEmptyState(
                icon: Icons.timeline_rounded,
                message: 'No recent activity to show.',
              ))
        : GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  _TimelineRow(e: top[i], isLast: i == top.length - 1),
              ],
            ),
          );

    return _TabScaffold(
      onRefresh: () async {
        if (canViewChanges) ref.invalidate(_changeLogProvider(employeeId));
        ref.invalidate(_attendanceProvider(employeeId));
        ref.invalidate(_tasksProvider(employeeId));
        ref.invalidate(_leaveProvider(employeeId));
        ref.invalidate(_assetsProvider(employeeId));
        ref.invalidate(_locationProvider(employeeId));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canViewChanges) ...[
            _ChangeHistoryCard(changes: changes),
            const SizedBox(height: 16),
            const ProSectionHeader(title: 'Activity'),
            const SizedBox(height: 10),
          ],
          activity,
        ],
      ),
    );
  }
}

/// "Record changes": every create/update of the employee record — what
/// changed (old → new), who did it and when. Newest first.
class _ChangeHistoryCard extends StatelessWidget {
  const _ChangeHistoryCard({required this.changes});
  final AsyncValue<List<EmployeeChangeLog>> changes;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Record changes',
      icon: Icons.history_rounded,
      children: [
        changes.when(
          loading: () => const AppLoadingBlock(height: 90),
          error: (e, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Could not load change history.',
              style: TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'No changes recorded yet. Edits made from now on will appear here.',
                  style: AppText.caption.copyWith(fontSize: 13),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < list.length; i++)
                  _ChangeLogRow(entry: list[i], isLast: i == list.length - 1),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChangeLogRow extends StatelessWidget {
  const _ChangeLogRow({required this.entry, required this.isLast});
  final EmployeeChangeLog entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = entry.isCreated ? AppColors.success : AppColors.primary;
    final n = entry.changes.length;
    final summary = entry.isCreated
        ? 'created this record'
        : 'updated $n field${n == 1 ? '' : 's'}';
    final at = entry.createdAt;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  entry.isCreated ? Icons.person_add_alt_1_rounded : Icons.edit_rounded,
                  size: 13,
                  color: color,
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: AppColors.hairline)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6, bottom: isLast ? 4 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
                      children: [
                        TextSpan(
                          text: entry.actorName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: ' $summary',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    at == null ? '—' : _fmtDateTime(at),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (entry.changes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final c in entry.changes)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.label,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: c.oldValue ?? '—',
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                        const TextSpan(
                                          text: '  →  ',
                                          style: TextStyle(color: AppColors.muted),
                                        ),
                                        TextSpan(
                                          text: c.newValue ?? '—',
                                          style: const TextStyle(
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.e, required this.isLast});
  final _TimelineEvent e;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: e.color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(e.icon, size: 16, color: e.color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppColors.hairline),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        _fmtDateTime(e.time),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    e.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared building blocks
// ─────────────────────────────────────────────────────────────────────────────

//// Scrollable, pull-to-refresh container used by every tab. Injects the
/// pinned tab strip's overlap so the first card never hides under it.
class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.child, this.onRefresh});
  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final list = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, mq.padding.bottom + 24),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white,
      onRefresh: onRefresh!,
      child: list,
    );
  }
}

/// White section card: title row (optional trailing pill) then rows. Hairline
/// dividers are drawn between consecutive [_InfoRow]s.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });
  final String title;
  final List<Widget> children;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(title: title, trailing: trailing),
          const SizedBox(height: 6),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && children[i] is _InfoRow && children[i - 1] is _InfoRow)
              const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Key / value row (Pro key-value look) with a faint leading icon.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value, {this.onTap});
  final IconData icon;
  final String label;
  final String? value;

  /// When set, the row becomes tappable (e.g. open the position in Google Maps)
  /// and the value renders as a link with an "open" affordance.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = (value == null || value!.trim().isEmpty) ? '—' : value!.trim();
    final tappable = onTap != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: AppColors.faint),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: tappable ? AppColors.primary : AppColors.ink,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.open_in_new_rounded,
                  size: 15, color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
    if (!tappable) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

/// A compact single-number stat (count + label) used inside a section card,
/// e.g. the "This month" attendance summary. Self-contained — no floating
/// header, so it can never visually collide with the card above it.
class _MonthStat extends StatelessWidget {
  const _MonthStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _StatCell(label: label, value: '$value', color: color);
  }
}

/// Dot + number + label cell used by [_MonthStat] and [_StatStrip].
class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// White strip of evenly spaced stat cells with hairline separators.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.cells});
  final List<_StatCell> cells;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: VerticalDivider(
                      width: 1, thickness: 1, color: AppColors.hairlineSoft),
                ),
              Expanded(child: cells[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _MutedLine extends StatelessWidget {
  const _MutedLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: AppText.caption.copyWith(fontSize: 13.5)),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => ProNote(text);
}

/// Status tone → Pro pill tint.
ProPill _tonePill(StatusTone tone) {
  if (tone.color == AppColors.success) return ProPill.ok(tone.label);
  if (tone.color == AppColors.danger) return ProPill.bad(tone.label);
  if (tone.color == AppColors.warning) return ProPill.warn(tone.label);
  if (tone.color == AppColors.info || tone.color == AppColors.accent) {
    return ProPill.info(tone.label);
  }
  return ProPill.neutral(tone.label);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _fmtDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${d.day} ${_months[d.month - 1]}, $h:$m $ap';
}

/// 'yyyy-MM-dd' → '12 May 2024'.
String? _prettyDate(String? ymd) {
  final d = _parseYmd(ymd);
  return d == null ? ymd : _fmtDate(d);
}

DateTime? _parseYmd(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

DateTime? _parseIso(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

/// ISO datetime → 'HH:mm AM/PM'.
String _fmtTime(String? iso) {
  final d = _parseIso(iso);
  if (d == null) return '—';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $ap';
}

String _fmtHours(double? hours) {
  if (hours == null || hours <= 0) return '—';
  final h = hours.floor();
  final m = ((hours - h) * 60).round();
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String? _photoUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http')) return raw;
  final base = ApiClient.instance.raw.options.baseUrl;
  if (base.isEmpty) return null;
  final sep = base.endsWith('/') || raw.startsWith('/') ? '' : '/';
  return '$base$sep$raw';
}

bool _isOverdue(Task t) {
  if (t.dueDate == null) return false;
  if (t.status == 'DONE' || t.status == 'CANCELLED') return false;
  final today = DateTime.now();
  final d = t.dueDate!;
  return DateTime(d.year, d.month, d.day)
      .isBefore(DateTime(today.year, today.month, today.day));
}

/// Distance travelled along [pings], matching the backend travel-distance
/// report (`EmployeeDayStatsService.summariseTrail`) so the "Distance today"
/// chip and the web report agree:
///  * hops under 15 m are stationary GPS drift, not travel;
///  * fixes that fail the route map's quality gate are skipped — (0,0) or
///    out-of-range coordinates, an error radius over 250 m, or an implied
///    speed over 150 km/h against the last good fix (measured on the distance
///    the two error radii cannot explain). One stray fix hundreds of km away
///    used to count as travel there and back.
/// The thresholds mirror the backend defaults (Settings → Field Visits).
/// VERIFIED km only — the backend's fold rules (EmployeeDayStatsService):
/// the accuracy/speed gate, a cumulative accuracy-aware jitter floor, and a hop
/// of 10 minutes or more is a tracking gap whose straight line is NOT counted.
double? _routeDistanceKm(List<TrackPing> pings) {
  if (pings.length < 2) return null;
  const minSegmentMeters = 15.0;
  const maxFloorMeters = 100.0;
  const maxAccuracyMeters = 250.0;
  const maxKmph = 150.0;
  const gapSeconds = 600;
  var meters = 0.0;
  TrackPing? prev;
  TrackPing? anchor;
  final sorted = [...pings]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  for (final p in sorted) {
    if (p.latitude == 0.0 && p.longitude == 0.0) continue;
    if (p.latitude.abs() > 90 || p.longitude.abs() > 180) continue;
    final acc = p.accuracyMeters ?? 0.0;
    if (acc > maxAccuracyMeters) continue;
    if (prev != null) {
      final m = _haversineMeters(
        prev.latitude,
        prev.longitude,
        p.latitude,
        p.longitude,
      );
      final dt = p.recordedAt.difference(prev.recordedAt).inSeconds;
      final unexplained = m - (prev.accuracyMeters ?? 0.0) - acc;
      final kmph = dt > 0 && unexplained > 0 ? (unexplained / dt) * 3.6 : 0.0;
      if (kmph > maxKmph || (dt <= 0 && unexplained > 0)) continue;
      if (dt >= gapSeconds) {
        anchor = p; // a gap: the chord is an estimate, not verified distance
      } else {
        final a = anchor ?? prev;
        final fromAnchor = _haversineMeters(a.latitude, a.longitude, p.latitude, p.longitude);
        final better = (a.accuracyMeters == null || acc == 0)
            ? minSegmentMeters
            : (a.accuracyMeters! < acc ? a.accuracyMeters! : acc);
        final floor = better.clamp(minSegmentMeters, maxFloorMeters);
        if (fromAnchor >= floor) {
          meters += fromAnchor;
          anchor = p;
        }
      }
    } else {
      anchor = p;
    }
    prev = p;
  }
  return meters / 1000.0;
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180.0;

StatusTone _locationStateTone(String? state) {
  switch (state) {
    case 'ON':
      return const StatusTone(AppColors.success, 'Tracking on');
    case 'LOCATION_OFF':
      return const StatusTone(AppColors.danger, 'Location off');
    case 'PERMISSION_OFF':
      return const StatusTone(AppColors.warning, 'Permission off');
    case 'NOT_TRACKING':
      return const StatusTone(AppColors.muted, 'Not tracking');
    default:
      return const StatusTone(AppColors.muted, 'Unknown');
  }
}

StatusTone _taskTone(String s) {
  switch (s) {
    case 'DONE':
      return const StatusTone(AppColors.success, 'Done');
    case 'IN_PROGRESS':
      return const StatusTone(AppColors.info, 'In progress');
    case 'IN_REVIEW':
      return const StatusTone(AppColors.warning, 'In review');
    case 'CANCELLED':
      return const StatusTone(AppColors.muted, 'Cancelled');
    case 'REJECTED':
      return const StatusTone(AppColors.danger, 'Rejected');
    default:
      return const StatusTone(AppColors.muted, 'To do');
  }
}

StatusTone _assetTone(String s) {
  switch (s) {
    case 'ACTIVE':
      return const StatusTone(AppColors.success, 'Assigned');
    case 'RETURNED':
      return const StatusTone(AppColors.muted, 'Returned');
    default:
      return StatusTone(AppColors.info, s);
  }
}

IconData _assetIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('laptop') || n.contains('macbook')) return Icons.laptop_mac_rounded;
  if (n.contains('sim')) return Icons.sim_card_rounded;
  if (n.contains('phone') || n.contains('mobile') || n.contains('iphone')) {
    return Icons.smartphone_rounded;
  }
  if (n.contains('tablet') || n.contains('ipad')) return Icons.tablet_mac_rounded;
  if (n.contains('id') || n.contains('card')) return Icons.badge_rounded;
  if (n.contains('monitor') || n.contains('display')) {
    return Icons.desktop_windows_rounded;
  }
  if (n.contains('printer')) return Icons.print_rounded;
  if (n.contains('vehicle') || n.contains('bike') || n.contains('car')) {
    return Icons.directions_car_rounded;
  }
  return Icons.devices_other_rounded;
}
