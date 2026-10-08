import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/approvals.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../leaves/leave_models.dart';
import '../leaves/leave_repository.dart';
import '../resignation/resignation_models.dart';
import '../resignation/resignation_repository.dart';
import 'employee_detail_screen.dart';
import 'team_models.dart';
import 'team_repository.dart';

final _teamLeavesProvider =
    FutureProvider.autoDispose<List<LeaveRequest>>((ref) {
  return ref.watch(leaveRepositoryProvider).listForTeam();
});

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  int _tab = 0; // 0 = Members, 1 = Leaves, 2 = Attendance, 3 = Exits

  static const _tabLabels = ['Members', 'Leaves', 'Attendance', 'Exits'];

  @override
  Widget build(BuildContext context) {
    // The view switch lives inside every view's hero, so each tab keeps its
    // own scroll position, filters and search (IndexedStack keeps them alive).
    final tabs = ProHeroSegmented(
      labels: _tabLabels,
      selected: _tab,
      onChanged: (v) => setState(() => _tab = v),
    );
    return IndexedStack(
      index: _tab,
      children: [
        _MembersView(tabs: tabs),
        _LeavesView(tabs: tabs),
        _AttendanceView(tabs: tabs),
        _ExitsView(tabs: tabs),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared page chrome
// ─────────────────────────────────────────────────────────────────────

/// Tab-screen page: deep "My team" hero (with the view switch) that continues
/// the shell app bar, then the view's sections.
class _TeamPage extends StatelessWidget {
  const _TeamPage({
    required this.tabs,
    required this.kicker,
    required this.subtitle,
    required this.stats,
    required this.onRefresh,
    required this.children,
    this.overlap,
    this.extra = const [],
  });

  final Widget tabs;
  final String kicker;
  final String subtitle;
  final List<ProStat> stats;
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final Widget? overlap;

  /// Extra hero slots between the view switch and the stats.
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    return ProPage(
      topInset: MediaQuery.of(context).padding.top,
      clearNav: true,
      onRefresh: onRefresh,
      hero: ProHero(
        kicker: kicker,
        title: 'My team',
        subtitle: subtitle,
        overlap: overlap,
        children: [
          tabs,
          ...extra,
          ProHeroStats(stats: stats),
        ],
      ),
      children: children,
    );
  }
}

/// Status dots used on the deep hero.
const _dotIn = AppColors.live;
const _dotLeave = Color(0xFFF2B347);
const _dotAbsent = Color(0xFFE5484D);
const _dotOut = Color(0xFF7FC8D8);

/// "Punched In" → "Punched in" (labels come from the shared status tones).
String _sentence(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

String _today() => DateFormat('EEEE, d MMM').format(DateTime.now());

// ─────────────────────────────────────────────────────────────────────
// Members tab
// ─────────────────────────────────────────────────────────────────────

class _MembersView extends ConsumerStatefulWidget {
  const _MembersView({required this.tabs});
  final Widget tabs;

  @override
  ConsumerState<_MembersView> createState() => _MembersViewState();
}

class _MembersViewState extends ConsumerState<_MembersView> {
  String _filter = 'ALL';
  final _searchCtrl = TextEditingController();
  String _query = '';

  // (state key, label) — order shown in the filter row.
  static const _filters = [
    ('ALL', 'All'),
    ('PUNCHED_IN', 'Punched in'),
    ('PUNCHED_OUT', 'Punched out'),
    ('LEAVE', 'Leave'),
    ('ABSENT', 'Absent'),
    ('NOT_LOGGED_IN', 'Not in'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(TeamMember m) {
    if (_query.isEmpty) return true;
    bool has(String? s) => s != null && s.toLowerCase().contains(_query);
    return has(m.name) ||
        has(m.employeeCode) ||
        has(m.designation) ||
        has(m.department) ||
        has(m.branchLabel);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamMembersProvider);
    final members = async.valueOrNull;

    int countOf(String s) =>
        members == null ? 0 : members.where((m) => m.state == s).length;
    final counts = <String, int>{
      'ALL': members?.length ?? 0,
      'PUNCHED_IN': countOf('PUNCHED_IN'),
      'PUNCHED_OUT': countOf('PUNCHED_OUT'),
      'LEAVE': countOf('LEAVE'),
      'ABSENT': countOf('ABSENT'),
      'NOT_LOGGED_IN': countOf('NOT_LOGGED_IN'),
    };
    final working = counts['PUNCHED_IN']! + counts['PUNCHED_OUT']!;
    String val(int n) => members == null ? '—' : '$n';

    return _TeamPage(
      tabs: widget.tabs,
      kicker: _today(),
      subtitle: members == null
          ? "Today's attendance"
          : '$working of ${members.length} working today',
      onRefresh: () async => ref.invalidate(teamMembersProvider),
      extra: [
        if (members != null && members.isNotEmpty)
          ProStackBar(parts: [
            MapEntry(counts['PUNCHED_IN']!.toDouble(), _dotIn),
            MapEntry(counts['PUNCHED_OUT']!.toDouble(), _dotOut),
            MapEntry(counts['LEAVE']!.toDouble(), _dotLeave),
            MapEntry(counts['ABSENT']!.toDouble(), _dotAbsent),
            MapEntry(counts['NOT_LOGGED_IN']!.toDouble(),
                Colors.white.withValues(alpha: 0.22)),
          ]),
      ],
      stats: [
        ProStat(
          label: 'Present',
          value: val(working),
          sub: members == null ? null : '${counts['PUNCHED_OUT']} out',
          dot: _dotIn,
        ),
        ProStat(label: 'On leave', value: val(counts['LEAVE']!), dot: _dotLeave),
        ProStat(label: 'Absent', value: val(counts['ABSENT']!), dot: _dotAbsent),
        ProStat(
          label: 'Not in',
          value: val(counts['NOT_LOGGED_IN']!),
          dot: Colors.white54,
        ),
      ],
      // ── Search across the whole downline (name / code / role / branch) ──
      overlap: ProSearchField(
        raised: true,
        controller: _searchCtrl,
        hint: 'Search name, code, role or branch',
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      ),
      children: async.when(
        loading: () => const [
          AppLoadingBlock(height: 72),
          AppLoadingBlock(height: 220),
        ],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(teamMembersProvider),
          ),
        ],
        data: (members) {
          if (members.isEmpty) {
            return const [
              SizedBox(height: 8),
              AppEmptyState(
                icon: Icons.groups_2_rounded,
                message: 'No team members report to you yet.',
              ),
            ];
          }

          final filtered = (_filter == 'ALL'
                  ? members
                  : members.where((m) => m.state == _filter).toList())
              .where(_matchesQuery)
              .toList();
          final selected = _filters.indexWhere((f) => f.$1 == _filter);
          final listTitle = _query.isNotEmpty
              ? '${filtered.length} ${filtered.length == 1 ? 'member matches' : 'members match'} “${_searchCtrl.text.trim()}”'
              : '${_filter == 'ALL' ? 'All members' : _filters[selected].$2} · ${filtered.length}';

          return [
            ProChipBar(
              labels: [for (final f in _filters) f.$2],
              counts: [for (final f in _filters) counts[f.$1] ?? 0],
              selected: selected < 0 ? 0 : selected,
              onSelected: (i) => setState(() => _filter = _filters[i].$1),
              bleed: 0,
            ),
            ProSectionHeader(title: listTitle, small: true),
            if (filtered.isEmpty)
              AppEmptyState(
                icon: Icons.groups_2_rounded,
                message: _query.isNotEmpty
                    ? 'No members match your search.'
                    : 'No members in this status.',
              )
            else
              ProListGroup(
                dividerIndent: 66,
                children: [for (final m in filtered) _MemberRow(m: m)],
              ),
          ];
        },
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.m});
  final TeamMember m;

  ProPill _pill() {
    final label = _sentence(m.statusTone.label);
    switch (m.state) {
      case 'PUNCHED_IN':
        return ProPill.ok(label);
      case 'PUNCHED_OUT':
        return ProPill.info(label);
      case 'LEAVE':
        return ProPill.warn(label);
      case 'ABSENT':
        return ProPill.bad(label);
      default:
        return ProPill.neutral(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (m.employeeCode != null && m.employeeCode!.isNotEmpty) m.employeeCode!,
      if (m.designation != null && m.designation!.isNotEmpty) m.designation!,
      if (m.department != null && m.department!.isNotEmpty) m.department!,
    ].join(' · ');
    final times = <String>[
      if (m.checkInHm != null) 'In ${m.checkInHm}',
      if (m.checkOutHm != null) 'Out ${m.checkOutHm}',
    ].join(' · ');
    final third = times.isNotEmpty
        ? times
        : (m.branchLabel != null && m.branchLabel!.isNotEmpty
            ? m.branchLabel!
            : null);
    return ProListRow(
      leading: ProAvatar(name: m.name, dot: m.statusTone.color),
      title: m.name,
      subtitle: meta.isEmpty ? null : meta,
      meta: third,
      pill: _pill(),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmployeeDetailScreen(employeeId: m.id, name: m.name),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Approval tabs — shared pieces
// ─────────────────────────────────────────────────────────────────────

const _reviewFilters = [
  ('ALL', 'All'),
  ('PENDING', 'Pending'),
  ('APPROVED', 'Approved'),
  ('REJECTED', 'Rejected'),
];

/// Pending / approved / rejected hero tiles; each one toggles the matching
/// status filter (tap again to clear).
List<ProStat> _reviewStats({
  required bool loaded,
  required int pending,
  required int approved,
  required int rejected,
  required String filter,
  required ValueChanged<String> onFilter,
}) {
  ProStat stat(String key, String label, int n, Color dot) => ProStat(
        label: label,
        value: loaded ? '$n' : '—',
        dot: dot,
        selected: loaded && filter == key,
        onTap: loaded ? () => onFilter(filter == key ? 'ALL' : key) : null,
      );
  return [
    stat('PENDING', 'Pending', pending, _dotLeave),
    stat('APPROVED', 'Approved', approved, _dotIn),
    stat('REJECTED', 'Rejected', rejected, _dotAbsent),
  ];
}

String _reviewSubtitle(int? pending, String what) {
  if (pending == null) return what;
  return pending > 0 ? '$pending pending your review' : 'All caught up — nice work';
}

Widget _reviewChips({
  required String value,
  required Map<String, int> counts,
  required ValueChanged<String> onChanged,
}) {
  final selected = _reviewFilters.indexWhere((f) => f.$1 == value);
  return ProChipBar(
    labels: [for (final f in _reviewFilters) f.$2],
    counts: [for (final f in _reviewFilters) counts[f.$1] ?? 0],
    selected: selected < 0 ? 0 : selected,
    onSelected: (i) => onChanged(_reviewFilters[i].$1),
    bleed: 0,
  );
}

String _reviewListTitle(String filter, int n) {
  final label = _reviewFilters
      .firstWhere((f) => f.$1 == filter, orElse: () => _reviewFilters.first)
      .$2;
  return '${filter == 'ALL' ? 'All requests' : label} · $n';
}

// ─────────────────────────────────────────────────────────────────────
// Leaves tab (approve / reject)
// ─────────────────────────────────────────────────────────────────────

class _LeavesView extends ConsumerStatefulWidget {
  const _LeavesView({required this.tabs});
  final Widget tabs;

  @override
  ConsumerState<_LeavesView> createState() => _LeavesViewState();
}

class _LeavesViewState extends ConsumerState<_LeavesView> {
  String _filter = 'ALL';
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(LeaveRequest r) =>
      _query.isEmpty || (r.employeeName ?? '').toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    // Every leave from /api/leaves/team is a direct report's request, which the
    // backend authorises this user to review (HR/Admin via DATA_SCOPE_ALL, or the
    // report's direct manager). Managers — not just ADMIN/HR — must see the
    // approve/reject actions here, matching the web app and the backend rule.
    final canReview = user != null;
    final leaves = ref.watch(_teamLeavesProvider);
    // Approval-engine queue: chain steps can route leaves of NON-direct
    // reports to this user — merge them in so the reviewer sees everything
    // pending on them in one place.
    final chainQueue = ref.watch(leavesPendingMyApprovalProvider).maybeWhen(
          data: (rows) => rows,
          orElse: () => const <LeaveRequest>[],
        );

    List<LeaveRequest> merge(List<LeaveRequest> allRows) {
      // Cancelled leaves are not relevant to a reviewer — hide them.
      final rows = allRows.where((r) => r.status != 'CANCELLED').toList();
      for (final q in chainQueue) {
        if (!rows.any((r) => r.id == q.id)) rows.add(q);
      }
      return rows;
    }

    final loaded = leaves.valueOrNull;
    final rows = loaded == null ? null : merge(loaded);
    final pending = rows?.where((r) => r.status == 'PENDING').length ?? 0;
    final approved = rows?.where((r) => r.status == 'APPROVED').length ?? 0;
    final rejected = rows?.where((r) => r.status == 'REJECTED').length ?? 0;

    void onRefreshed() {
      ref.invalidate(_teamLeavesProvider);
      ref.invalidate(leavesPendingMyApprovalProvider);
    }

    return _TeamPage(
      tabs: widget.tabs,
      kicker: 'Leave requests',
      subtitle: _reviewSubtitle(rows == null ? null : pending, 'Leave requests'),
      onRefresh: () async => onRefreshed(),
      stats: _reviewStats(
        loaded: rows != null,
        pending: pending,
        approved: approved,
        rejected: rejected,
        filter: _filter,
        onFilter: (v) => setState(() => _filter = v),
      ),
      overlap: ProSearchField(
        raised: true,
        controller: _searchCtrl,
        hint: 'Search by employee name',
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      ),
      children: leaves.when(
        loading: () => const [AppLoadingBlock(height: 160)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(_teamLeavesProvider),
          ),
        ],
        data: (allRows) {
          final all = merge(allRows);
          final filtered = (_filter == 'ALL'
                  ? all
                  : all.where((r) => r.status == _filter).toList())
              .where(_matchesQuery)
              .toList();
          final anyReviewable =
              canReview && filtered.any((r) => r.status == 'PENDING');

          return [
            _reviewChips(
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
              counts: {
                'ALL': all.length,
                'PENDING': pending,
                'APPROVED': approved,
                'REJECTED': rejected,
              },
            ),
            ProSectionHeader(
              title: _reviewListTitle(_filter, filtered.length),
              small: true,
            ),
            if (filtered.isEmpty)
              AppEmptyState(
                icon: Icons.event_available_rounded,
                message: _query.isNotEmpty
                    ? 'No leave requests match your search.'
                    : 'Nothing here right now.',
              )
            else ...[
              if (anyReviewable) const ProSwipeHint(),
              for (final r in filtered)
                _TeamLeaveCard(
                  r: r,
                  canReview: canReview && r.status == 'PENDING',
                  reviewerEmployeeId: user?.employeeId,
                  onReviewed: onRefreshed,
                ),
            ],
          ];
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Attendance tab (regularization approve / reject)
// ─────────────────────────────────────────────────────────────────────

class _AttendanceView extends ConsumerStatefulWidget {
  const _AttendanceView({required this.tabs});
  final Widget tabs;

  @override
  ConsumerState<_AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends ConsumerState<_AttendanceView> {
  String _filter = 'ALL';
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(RegularizationRequest r) =>
      _query.isEmpty || (r.employeeName ?? '').toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final async = ref.watch(teamRegularizationsProvider);
    // Approval-engine queue: chain steps can route regularizations of
    // NON-direct reports to this user — merge them into the same list.
    final chainQueue =
        ref.watch(regularizationsPendingMyApprovalProvider).maybeWhen(
              data: (rows) => rows,
              orElse: () => const <RegularizationRequest>[],
            );

    List<RegularizationRequest> merge(List<RegularizationRequest> teamRows) {
      final rows = [...teamRows];
      for (final q in chainQueue) {
        if (!rows.any((r) => r.id == q.id)) rows.add(q);
      }
      return rows;
    }

    final loaded = async.valueOrNull;
    final rows = loaded == null ? null : merge(loaded);
    final pending = rows?.where((r) => r.status == 'PENDING').length ?? 0;
    final approved = rows?.where((r) => r.status == 'APPROVED').length ?? 0;
    final rejected = rows?.where((r) => r.status == 'REJECTED').length ?? 0;

    void onRefreshed() {
      ref.invalidate(teamRegularizationsProvider);
      ref.invalidate(regularizationsPendingMyApprovalProvider);
    }

    return _TeamPage(
      tabs: widget.tabs,
      kicker: 'Regularizations',
      subtitle:
          _reviewSubtitle(rows == null ? null : pending, 'Regularization requests'),
      onRefresh: () async => onRefreshed(),
      stats: _reviewStats(
        loaded: rows != null,
        pending: pending,
        approved: approved,
        rejected: rejected,
        filter: _filter,
        onFilter: (v) => setState(() => _filter = v),
      ),
      overlap: ProSearchField(
        raised: true,
        controller: _searchCtrl,
        hint: 'Search by employee name',
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      ),
      children: async.when(
        loading: () => const [AppLoadingBlock(height: 160)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(teamRegularizationsProvider),
          ),
        ],
        data: (teamRows) {
          final all = merge(teamRows);
          final filtered = (_filter == 'ALL'
                  ? all
                  : all.where((r) => r.status == _filter).toList())
              .where(_matchesQuery)
              .toList();
          // Pending first within the current filter.
          final sorted = [
            ...filtered.where((r) => r.isPending),
            ...filtered.where((r) => !r.isPending),
          ];

          return [
            _reviewChips(
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
              counts: {
                'ALL': all.length,
                'PENDING': pending,
                'APPROVED': approved,
                'REJECTED': rejected,
              },
            ),
            ProSectionHeader(
              title: _reviewListTitle(_filter, sorted.length),
              small: true,
            ),
            if (sorted.isEmpty)
              AppEmptyState(
                icon: Icons.fact_check_outlined,
                message: _query.isNotEmpty
                    ? 'No requests match your search.'
                    : 'Nothing here right now.',
              )
            else ...[
              if (sorted.any((r) => r.isPending)) const ProSwipeHint(),
              for (final r in sorted)
                _RegularizationCard(
                  r: r,
                  reviewerEmployeeId: user?.employeeId,
                  onReviewed: onRefreshed,
                ),
            ],
          ];
        },
      ),
    );
  }
}

class _RegularizationCard extends ConsumerStatefulWidget {
  const _RegularizationCard({
    required this.r,
    required this.reviewerEmployeeId,
    required this.onReviewed,
  });
  final RegularizationRequest r;
  final int? reviewerEmployeeId;
  final VoidCallback onReviewed;

  @override
  ConsumerState<_RegularizationCard> createState() =>
      _RegularizationCardState();
}

class _RegularizationCardState extends ConsumerState<_RegularizationCard> {
  bool _busy = false;

  Future<void> _review(String status) async {
    final comment = await _promptComment(status);
    if (comment == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(teamRepositoryProvider).reviewRegularization(
            widget.r.id,
            status: status,
            reviewerEmployeeId: widget.reviewerEmployeeId,
            comment: comment.isEmpty ? null : comment,
          );
      widget.onReviewed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptComment(String status) {
    final c = TextEditingController();
    final isApprove = status == 'APPROVED';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isApprove ? 'Approve regularization' : 'Reject regularization'),
        content: TextField(
          controller: c,
          maxLines: 2,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          decoration: const InputDecoration(hintText: 'Add a comment (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isApprove ? null : _destructiveStyle(),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(isApprove ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return _ApprovalCard(
      name: r.employeeName ?? 'Employee',
      line: [
        if (r.date != null) r.date!,
        if (r.requestedStatus != null) r.requestedStatus!,
      ].join(' · '),
      tone: r.statusTone,
      busy: _busy,
      actionable: r.isPending,
      onApprove: () => _review('APPROVED'),
      onReject: () => _review('REJECTED'),
      body: [
        if (r.timeSummary.isNotEmpty)
          _InfoStrip(icon: Icons.schedule_rounded, text: r.timeSummary),
        if (r.reason != null && r.reason!.isNotEmpty) _Reason(r.reason!),
        // Configured approval chain (Wave 4b engine); empty = default
        // direct-manager flow → renders nothing.
        if (r.isPending)
          ref.watch(regularizationApprovalStepsProvider(r.id)).maybeWhen(
                data: (s) => s.isEmpty
                    ? const SizedBox.shrink()
                    : ApprovalChainInline(steps: s),
                orElse: () => const SizedBox.shrink(),
              ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared approval card
// ─────────────────────────────────────────────────────────────────────

ButtonStyle _destructiveStyle() => FilledButton.styleFrom(
      backgroundColor: AppColors.dangerTint,
      foregroundColor: AppColors.danger,
    );

ProPill _tonePill(StatusTone tone) {
  if (tone.color == AppColors.success) return ProPill.ok(tone.label);
  if (tone.color == AppColors.danger) return ProPill.bad(tone.label);
  if (tone.color == AppColors.warning) return ProPill.warn(tone.label);
  if (tone.color == AppColors.info) return ProPill.info(tone.label);
  return ProPill.neutral(tone.label);
}

/// One approval request: avatar + name + status, detail lines, and (while
/// actionable) Reject / Approve buttons. Actionable cards can also be swiped
/// right to approve or left to reject — both run the same handlers.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.name,
    required this.line,
    required this.tone,
    required this.body,
    required this.actionable,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final String name;
  final String line;
  final StatusTone tone;
  final List<Widget> body;
  final bool actionable;
  final bool busy;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final card = GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProAvatar(name: name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (line.isNotEmpty)
                      Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _tonePill(tone),
            ],
          ),
          for (final b in body) ...[const SizedBox(height: 10), b],
          if (actionable) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onReject,
                    style: _destructiveStyle().copyWith(
                      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onApprove,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (!actionable) return card;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: ProSwipeDecision(
        onApprove: () async {
          if (!busy) await onApprove();
        },
        onReject: () async {
          if (!busy) await onReject();
        },
        child: card,
      ),
    );
  }
}

/// Tinted one-line detail (dates / times) inside an approval card.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
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

class _Reason extends StatelessWidget {
  const _Reason(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      '“$text”',
      style: const TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: AppColors.inkSoft,
      ),
    );
  }
}

class _TeamLeaveCard extends ConsumerStatefulWidget {
  const _TeamLeaveCard({
    required this.r,
    required this.canReview,
    required this.reviewerEmployeeId,
    required this.onReviewed,
  });
  final LeaveRequest r;
  final bool canReview;
  final int? reviewerEmployeeId;
  final VoidCallback onReviewed;

  @override
  ConsumerState<_TeamLeaveCard> createState() => _TeamLeaveCardState();
}

class _TeamLeaveCardState extends ConsumerState<_TeamLeaveCard> {
  bool _busy = false;

  Future<void> _review(String status) async {
    final comment = await _promptComment(status);
    if (comment == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(leaveRepositoryProvider).review(
            widget.r.id,
            status: status,
            reviewerEmployeeId: widget.reviewerEmployeeId,
            reviewComment: comment.isEmpty ? null : comment,
          );
      widget.onReviewed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptComment(String status) async {
    final c = TextEditingController();
    final isApprove = status == 'APPROVED';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isApprove ? 'Approve request' : 'Reject request'),
        content: TextField(
          controller: c,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          decoration: const InputDecoration(
            hintText: 'Add a comment (optional)',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isApprove ? null : _destructiveStyle(),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(isApprove ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return _ApprovalCard(
      name: r.employeeName ?? 'Employee',
      line: '${_humanLeaveType(r.leaveType)} · ${r.numberOfDays ?? "?"} day(s)',
      tone: StatusTone.forLeave(r.status),
      busy: _busy,
      actionable: widget.canReview,
      onApprove: () => _review('APPROVED'),
      onReject: () => _review('REJECTED'),
      body: [
        _InfoStrip(
          icon: Icons.calendar_today_rounded,
          text: '${r.fromDate}  →  ${r.toDate}',
        ),
        if (r.reason != null && r.reason!.isNotEmpty) _Reason(r.reason!),
        // Configured approval chain (Wave 4b engine); empty = default
        // direct-manager flow → renders nothing.
        if (r.status == 'PENDING')
          ref.watch(leaveApprovalStepsProvider(r.id)).maybeWhen(
                data: (s) => s.isEmpty
                    ? const SizedBox.shrink()
                    : ApprovalChainInline(steps: s),
                orElse: () => const SizedBox.shrink(),
              ),
      ],
    );
  }
}

// -------------------------------------------------------------------
// Exits tab - resignation approvals assigned to this manager
// -------------------------------------------------------------------

/// The manager's resignation inbox. The steps come from the configurable
/// resignation approval workflow (Reporting Manager level N), so this needs no
/// HR resignation permission - only the steps assigned to this user are listed.
class _ExitsView extends ConsumerStatefulWidget {
  const _ExitsView({required this.tabs});
  final Widget tabs;

  @override
  ConsumerState<_ExitsView> createState() => _ExitsViewState();
}

class _ExitsViewState extends ConsumerState<_ExitsView> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final approvals = ref.watch(myResignationApprovalsProvider);
    final rows = approvals.valueOrNull;
    final pending = rows?.where((r) => r.step.isPending).length ?? 0;
    final approved =
        rows?.where((r) => r.step.stepStatus == 'APPROVED').length ?? 0;
    final rejected =
        rows?.where((r) => r.step.stepStatus == 'REJECTED').length ?? 0;

    return _TeamPage(
      tabs: widget.tabs,
      kicker: 'Resignations',
      subtitle:
          _reviewSubtitle(rows == null ? null : pending, 'Resignation approvals'),
      onRefresh: () async => ref.invalidate(myResignationApprovalsProvider),
      stats: _reviewStats(
        loaded: rows != null,
        pending: pending,
        approved: approved,
        rejected: rejected,
        filter: _filter,
        onFilter: (v) => setState(() => _filter = v),
      ),
      children: approvals.when(
        loading: () => const [AppLoadingBlock(height: 160)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(myResignationApprovalsProvider),
          ),
        ],
        data: (rows) {
          final filtered = _filter == 'ALL'
              ? rows
              : rows.where((r) => r.step.stepStatus == _filter).toList();

          return [
            _reviewChips(
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
              counts: {
                'ALL': rows.length,
                'PENDING': pending,
                'APPROVED': approved,
                'REJECTED': rejected,
              },
            ),
            ProSectionHeader(
              title: _reviewListTitle(_filter, filtered.length),
              small: true,
            ),
            if (filtered.isEmpty)
              const AppEmptyState(
                icon: Icons.logout_rounded,
                message: 'No resignation approvals are assigned to you.',
              )
            else ...[
              if (filtered.any((a) => a.step.isPending)) const ProSwipeHint(),
              for (final a in filtered)
                _ResignationApprovalCard(
                  a: a,
                  onReviewed: () =>
                      ref.invalidate(myResignationApprovalsProvider),
                ),
            ],
          ];
        },
      ),
    );
  }
}

class _ResignationApprovalCard extends ConsumerStatefulWidget {
  const _ResignationApprovalCard({required this.a, required this.onReviewed});
  final ResignationApproval a;
  final VoidCallback onReviewed;

  @override
  ConsumerState<_ResignationApprovalCard> createState() =>
      _ResignationApprovalCardState();
}

class _ResignationApprovalCardState
    extends ConsumerState<_ResignationApprovalCard> {
  bool _busy = false;

  String _fmt(DateTime? d) => d == null ? '-' : DateFormat('d MMM y').format(d);

  Future<void> _act(bool approve) async {
    final remarks = await _promptRemarks(approve);
    if (remarks == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(resignationRepositoryProvider);
      final id = widget.a.resignation.id;
      if (approve) {
        await repo.approve(id, remarks: remarks);
      } else {
        await repo.reject(id, remarks: remarks);
      }
      widget.onReviewed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptRemarks(bool approve) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve resignation' : 'Reject resignation'),
        content: TextField(
          controller: c,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Add remarks (optional)',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: approve ? null : _destructiveStyle(),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.a.resignation;
    final step = widget.a.step;
    final name = r.employeeName ?? 'Employee';

    return _ApprovalCard(
      name: name,
      line: [
        if (r.employeeCode != null) r.employeeCode!,
        if (r.designation != null) r.designation!,
        step.levelName,
      ].join(' · '),
      tone: StatusTone.forLeave(step.stepStatus),
      busy: _busy,
      actionable: step.isPending,
      onApprove: () => _act(true),
      onReject: () => _act(false),
      body: [
        _InfoStrip(
          icon: Icons.event_busy_rounded,
          text:
              'Resigned ${_fmt(r.resignationDate)} · Last day ${_fmt(r.lastWorkingDay)}',
        ),
        if (r.reason != null && r.reason!.isNotEmpty) _Reason(r.reason!),
        if (!step.isPending &&
            step.remarks != null &&
            step.remarks!.isNotEmpty)
          Text(
            'Your remarks: ${step.remarks!}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.inkSoft,
              height: 1.4,
            ),
          ),
      ],
    );
  }
}

/// "SICK" → "Sick leave" — leave-type codes are DB-driven, so humanize
/// generically (same rule as the Leaves screen).
String _humanLeaveType(String t) {
  if (t.isEmpty) return t;
  final s = t.toLowerCase().replaceAll('_', ' ');
  return '${s[0].toUpperCase()}${s.substring(1)} leave';
}
