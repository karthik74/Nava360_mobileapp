import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../assets/assets_models.dart';
import '../assets/assets_repository.dart';
import '../attendance/attendance_models.dart';
import '../attendance/attendance_repository.dart';
import '../auth/auth_controller.dart';
import '../leaves/leave_models.dart';
import '../leaves/leave_repository.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import 'employee_detail_repository.dart';
import 'team_member_tracking_screen.dart';
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
    ('Timeline', Icons.timeline_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final canViewSensitive = (user?.hasRole(const {'ADMIN', 'HR'}) ?? false) ||
        (user?.hasPermission('EMPLOYEE_VIEW') ?? false);

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text(name),
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
        body: Column(
          children: [
            // Fixed, always-visible profile card.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _ProfileHeader(employeeId: employeeId, fallbackName: name),
            ),
            // Tab strip.
            Container(
              color: AppColors.surface,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                tabs: [
                  for (final t in _tabs)
                    Tab(
                      height: 44,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(t.$2, size: 15),
                          const SizedBox(width: 6),
                          Text(t.$1),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
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
                  _TimelineTab(employeeId: employeeId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixed profile header
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.employeeId, required this.fallbackName});
  final int employeeId;
  final String fallbackName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_profileProvider(employeeId));
    final emp = async.asData?.value;
    final name = emp?.fullName ?? fallbackName;
    final meta = emp == null
        ? null
        : [
            if ((emp.designation ?? '').isNotEmpty) emp.designation!,
            if ((emp.department ?? '').isNotEmpty) emp.department!,
          ].join(' · ');

    return GlassCard(
      shadow: AppShadows.card,
      child: Row(
        children: [
          UserAvatar(
            name: name,
            size: 54,
            radius: 16,
            imageUrl: _photoUrl(emp?.profileImageUrl),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                if (meta != null && meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if ((emp?.employeeCode ?? '').isNotEmpty)
                      StatusPill(
                        label: emp!.employeeCode!,
                        color: AppColors.primary,
                        icon: Icons.badge_rounded,
                      ),
                    if (emp != null)
                      StatusPill(
                        label: emp.active ? 'Active' : 'Inactive',
                        color: emp.active ? AppColors.success : AppColors.muted,
                      ),
                  ],
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
                _InfoRow(Icons.work_outline_rounded, 'Designation', e.designation),
                _InfoRow(Icons.apartment_rounded, 'Department', e.department),
                _InfoRow(Icons.location_city_rounded, 'Branch', e.branchLabel),
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
            if (canViewSensitive) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Bank & statutory',
                icon: Icons.account_balance_rounded,
                children: [
                  _InfoRow(Icons.account_balance_rounded, 'Bank', e.bankName),
                  _InfoRow(Icons.numbers_rounded, 'Account no.',
                      e.bankAccountNumber),
                  _InfoRow(Icons.code_rounded, 'IFSC', e.bankIfsc),
                  _InfoRow(Icons.savings_rounded, 'PF account', e.pfAccountNumber),
                  _InfoRow(Icons.confirmation_number_rounded, 'UAN', e.uanNumber),
                  _InfoRow(Icons.health_and_safety_rounded, 'ESI', e.esiNumber),
                ],
              ),
            ],
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
                trailing: StatusPill(
                  label: todayRec == null ? 'No record' : tone.label,
                  color: todayRec == null ? AppColors.muted : tone.color,
                ),
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
    final name = widget.name;
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
                trailing: StatusPill(label: locTone.label, color: locTone.color),
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
                  label: Text(_locating ? 'Locating…' : 'Get Live Location'),
                ),
              ),
              const SizedBox(height: 12),
              _statGrid([
                StatTileV2(
                  label: 'Distance today',
                  value: distanceKm == null
                      ? '—'
                      : '${distanceKm.toStringAsFixed(1)} km',
                  icon: Icons.route_rounded,
                  color: AppColors.primary,
                ),
                StatTileV2(
                  label: 'Field visits',
                  value: '$visits',
                  icon: Icons.store_mall_directory_rounded,
                  color: AppColors.accent,
                ),
              ]),
              const SizedBox(height: 12),
              GlassCard(
                shadow: AppShadows.soft,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.map_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "Today's route on the map",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeamMemberTrackingScreen(
                            employeeId: employeeId,
                            name: name,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.navigation_rounded, size: 16),
                      label: const Text('Route map'),
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
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
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
                fontSize: 12,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
                height: 1.3,
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
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              on ? Icons.location_on_rounded : Icons.location_off_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location status',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tone.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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
                      fontSize: 11.5,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Big ON / OFF pill with a status dot.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.6,
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
              _statGrid([
                StatTileV2(
                  label: 'Pending',
                  value: '$pending',
                  icon: Icons.radio_button_unchecked_rounded,
                  color: AppColors.muted,
                ),
                StatTileV2(
                  label: 'In progress',
                  value: '$inProgress',
                  icon: Icons.timelapse_rounded,
                  color: AppColors.info,
                ),
                StatTileV2(
                  label: 'Completed',
                  value: '$completed',
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                ),
                StatTileV2(
                  label: 'Overdue',
                  value: '$overdue',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                ),
              ]),
              const SizedBox(height: 14),
              if (tasks.isEmpty)
                const AppEmptyState(
                  icon: Icons.checklist_rounded,
                  message: 'No tasks assigned to this employee.',
                )
              else ...[
                const AppSectionHeader(title: 'Recent tasks'),
                const SizedBox(height: 10),
                for (final t in tasks.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TaskCard(t: t),
                  ),
                const SizedBox(height: 4),
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
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      overdue
                          ? Icons.event_busy_rounded
                          : Icons.event_rounded,
                      size: 12,
                      color: overdue ? AppColors.danger : AppColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      t.dueDate == null
                          ? (t.taskCode ?? 'No due date')
                          : 'Due ${_fmtDate(t.dueDate!)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: overdue ? AppColors.danger : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(label: tone.label, color: tone.color),
        ],
      ),
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
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _TaskCard(t: tasks[i]),
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
              _statGrid([
                StatTileV2(
                  label: 'Pending',
                  value: '$pending',
                  icon: Icons.hourglass_bottom_rounded,
                  color: AppColors.warning,
                ),
                StatTileV2(
                  label: 'Approved',
                  value: '$approved',
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                ),
                StatTileV2(
                  label: 'Rejected',
                  value: '$rejected',
                  icon: Icons.cancel_rounded,
                  color: AppColors.danger,
                ),
                StatTileV2(
                  label: 'Upcoming',
                  value: '${upcoming.length}',
                  icon: Icons.event_rounded,
                  color: AppColors.info,
                ),
              ]),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Leave balance',
                icon: Icons.account_balance_wallet_rounded,
                children: [
                  if (b.balance == null || b.balance!.balances.isEmpty)
                    const _MutedLine('No balance configured.')
                  else
                    for (final bal in b.balance!.balances)
                      _BalanceRow(bal: bal),
                ],
              ),
              const SizedBox(height: 12),
              if (upcoming.isNotEmpty) ...[
                const AppSectionHeader(title: 'Upcoming leave'),
                const SizedBox(height: 10),
                for (final r in upcoming.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LeaveCard(r: r),
                  ),
                const SizedBox(height: 2),
              ],
              const AppSectionHeader(title: 'Recent requests'),
              const SizedBox(height: 10),
              if (reqs.isEmpty)
                const AppEmptyState(
                  icon: Icons.beach_access_rounded,
                  message: 'No leave requests on record.',
                )
              else
                for (final r in reqs.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LeaveCard(r: r),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bal.leaveTypeLabel,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                '$balance / $allowance left',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.hairline,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({required this.r});
  final LeaveRequest r;

  @override
  Widget build(BuildContext context) {
    final tone = StatusTone.forLeave(r.status);
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.leaveType} · ${r.numberOfDays ?? '?'} day(s)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 12, color: AppColors.muted),
              const SizedBox(width: 5),
              Text(
                '${r.fromDate}  →  ${r.toDate}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ],
      ),
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

          return Column(
            children: [
              _SectionCard(
                title: 'Required documents',
                icon: Icons.fact_check_rounded,
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
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Other documents',
                  icon: Icons.folder_open_rounded,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          StatusPill(
            label: available ? 'Available' : 'Missing',
            color: available ? AppColors.success : AppColors.muted,
            icon: available
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
          ),
        ],
      ),
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
              for (final a in assets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AssetCard(a: a),
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
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.18)),
            ),
            alignment: Alignment.center,
            child: Icon(_assetIcon(a.assetName),
                color: AppColors.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.assetName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(label: tone.label, color: tone.color),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. Timeline (composed client-side from the other domains)
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
  const _TimelineTab({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reuse the per-domain providers and merge their data into one feed.
    // TODO: replace with a dedicated backend activity-feed endpoint when available.
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

    return _TabScaffold(
      onRefresh: () async {
        ref.invalidate(_attendanceProvider(employeeId));
        ref.invalidate(_tasksProvider(employeeId));
        ref.invalidate(_leaveProvider(employeeId));
        ref.invalidate(_assetsProvider(employeeId));
        ref.invalidate(_locationProvider(employeeId));
      },
      child: top.isEmpty
          ? (anyLoading
              ? const AppLoadingBlock(height: 200)
              : const AppEmptyState(
                  icon: Icons.timeline_rounded,
                  message: 'No recent activity to show.',
                ))
          : GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
              shadow: AppShadows.soft,
              child: Column(
                children: [
                  for (var i = 0; i < top.length; i++)
                    _TimelineRow(e: top[i], isLast: i == top.length - 1),
                ],
              ),
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
                  color: e.color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: e.color.withOpacity(0.28)),
                ),
                child: Icon(e.icon, size: 15, color: e.color),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        _fmtDateTime(e.time),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
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
                      fontSize: 11.5,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
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

/// Scrollable, pull-to-refresh container used by every tab.
class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.child, this.onRefresh});
  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 14, 16, mq.padding.bottom + 24),
      children: [child],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh!,
      child: list,
    );
  }
}

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
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 12),
          ...children,
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.muted),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                color: tappable ? AppColors.primary : AppColors.ink,
                fontWeight: FontWeight.w700,
                decoration: tappable ? TextDecoration.underline : null,
              ),
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new_rounded,
                size: 14, color: AppColors.primary),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _MutedLine extends StatelessWidget {
  const _MutedLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          color: AppColors.muted,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      color: AppColors.surfaceAlt,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2-per-row grid of stat tiles.
Widget _statGrid(List<Widget> tiles) {
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += 2) {
    final a = tiles[i];
    final b = (i + 1 < tiles.length) ? tiles[i + 1] : null;
    rows.add(Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // IntrinsicHeight gives the Row a bounded cross-axis so that
      // CrossAxisAlignment.stretch produces equal-height tiles instead of an
      // unbounded constraint that collapses a child to zero size (which throws
      // "Cannot hit test a render box with no size" and swallows taps).
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b ?? const SizedBox.shrink()),
          ],
        ),
      ),
    ));
  }
  return Column(children: rows);
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

double? _routeDistanceKm(List<TrackPing> pings) {
  if (pings.length < 2) return null;
  var meters = 0.0;
  for (var i = 1; i < pings.length; i++) {
    meters += _haversineMeters(
      pings[i - 1].latitude,
      pings[i - 1].longitude,
      pings[i].latitude,
      pings[i].longitude,
    );
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
