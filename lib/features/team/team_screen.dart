import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../leaves/leave_models.dart';
import '../leaves/leave_repository.dart';
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
  int _tab = 0; // 0 = Members, 1 = Leaves, 2 = Attendance

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Column(
      children: [
        SizedBox(height: mq.padding.top + 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SegmentBar(
            value: _tab,
            labels: const ['Members', 'Leaves', 'Attendance'],
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const [
              _MembersView(),
              _LeavesView(),
              _AttendanceView(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Segmented control
// ─────────────────────────────────────────────────────────────────────

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.value,
    required this.labels,
    required this.onChanged,
  });
  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == i ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: value == i ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Members tab
// ─────────────────────────────────────────────────────────────────────

class _MembersView extends ConsumerStatefulWidget {
  const _MembersView();

  @override
  ConsumerState<_MembersView> createState() => _MembersViewState();
}

class _MembersViewState extends ConsumerState<_MembersView> {
  String _filter = 'ALL';

  // (state key, label) — order shown in the filter row.
  static const _filters = [
    ('ALL', 'All'),
    ('PUNCHED_IN', 'Punched In'),
    ('PUNCHED_OUT', 'Punched Out'),
    ('LEAVE', 'Leave'),
    ('ABSENT', 'Absent'),
    ('NOT_LOGGED_IN', 'Not In'),
  ];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamMembersProvider);
    final mq = MediaQuery.of(context);
    final pad = EdgeInsets.fromLTRB(
      16,
      4,
      16,
      mq.padding.bottom + AppChrome.bottomNavHeight + 16,
    );
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(teamMembersProvider),
      child: async.when(
        loading: () => const _CenterLoader(),
        error: (e, _) => _ErrorList(
          message: e.toString(),
          padding: pad,
          onRetry: () => ref.invalidate(teamMembersProvider),
        ),
        data: (members) {
          if (members.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pad,
              children: const [
                SizedBox(height: 40),
                AppEmptyState(
                  icon: Icons.groups_2_rounded,
                  message: 'No team members report to you yet.',
                ),
              ],
            );
          }

          int countOf(String s) => members.where((m) => m.state == s).length;
          final counts = <String, int>{
            'ALL': members.length,
            'PUNCHED_IN': countOf('PUNCHED_IN'),
            'PUNCHED_OUT': countOf('PUNCHED_OUT'),
            'LEAVE': countOf('LEAVE'),
            'ABSENT': countOf('ABSENT'),
            'NOT_LOGGED_IN': countOf('NOT_LOGGED_IN'),
          };
          final filtered = _filter == 'ALL'
              ? members
              : members.where((m) => m.state == _filter).toList();

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pad,
            children: [
              _MembersSummary(
                total: members.length,
                punchedIn: counts['PUNCHED_IN']!,
                punchedOut: counts['PUNCHED_OUT']!,
                leave: counts['LEAVE']!,
                absent: counts['ABSENT']!,
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (final it in _filters) ...[
                      _FilterChip(
                        label: it.$2,
                        count: counts[it.$1] ?? 0,
                        selected: _filter == it.$1,
                        onTap: () => setState(() => _filter = it.$1),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                const AppEmptyState(
                  icon: Icons.groups_2_rounded,
                  message: 'No members in this status.',
                )
              else
                for (final m in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MemberCard(m: m),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Today's-attendance hero card for the Members tab (mirrors _TeamSummary).
class _MembersSummary extends StatelessWidget {
  const _MembersSummary({
    required this.total,
    required this.punchedIn,
    required this.punchedOut,
    required this.leave,
    required this.absent,
  });
  final int total;
  final int punchedIn;
  final int punchedOut;
  final int leave;
  final int absent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.32),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$total member${total == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Today's attendance",
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Punched In',
                    value: punchedIn,
                    color: const Color(0xFF34D399),
                  ),
                ),
                _divider(),
                Expanded(
                  child: _MiniStat(
                    label: 'Punched Out',
                    value: punchedOut,
                    color: const Color(0xFF60A5FA),
                  ),
                ),
                _divider(),
                Expanded(
                  child: _MiniStat(
                    label: 'Leave',
                    value: leave,
                    color: const Color(0xFFFBBF24),
                  ),
                ),
                _divider(),
                Expanded(
                  child: _MiniStat(
                    label: 'Absent',
                    value: absent,
                    color: const Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 28, color: Colors.white.withOpacity(0.18));
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.m});
  final TeamMember m;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (m.employeeCode != null && m.employeeCode!.isNotEmpty) m.employeeCode!,
      if (m.designation != null && m.designation!.isNotEmpty) m.designation!,
      if (m.department != null && m.department!.isNotEmpty) m.department!,
    ].join(' · ');
    final tone = m.statusTone;
    final times = <String>[
      if (m.checkInHm != null) 'In ${m.checkInHm}',
      if (m.checkOutHm != null) 'Out ${m.checkOutHm}',
    ].join('   ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                EmployeeDetailScreen(employeeId: m.id, name: m.name),
          ),
        ),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          shadow: AppShadows.soft,
          child: Row(
            children: [
              UserAvatar(name: m.name, size: 42, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (times.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 12, color: AppColors.muted),
                          const SizedBox(width: 4),
                          Text(
                            times,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.inkSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ] else if (m.branchLabel != null &&
                        m.branchLabel!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 12, color: AppColors.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              m.branchLabel!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.inkSoft,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Leaves tab (approve / reject)
// ─────────────────────────────────────────────────────────────────────

class _LeavesView extends ConsumerStatefulWidget {
  const _LeavesView();

  @override
  ConsumerState<_LeavesView> createState() => _LeavesViewState();
}

class _LeavesViewState extends ConsumerState<_LeavesView> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    // Every leave from /api/leaves/team is a direct report's request, which the
    // backend authorises this user to review (HR/Admin via DATA_SCOPE_ALL, or the
    // report's direct manager). Managers — not just ADMIN/HR — must see the
    // approve/reject actions here, matching the web app and the backend rule.
    final canReview = user != null;
    final leaves = ref.watch(_teamLeavesProvider);
    final mq = MediaQuery.of(context);
    final pad = EdgeInsets.fromLTRB(
      16,
      4,
      16,
      mq.padding.bottom + AppChrome.bottomNavHeight + 16,
    );

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(_teamLeavesProvider),
      child: leaves.when(
        loading: () => const _CenterLoader(),
        error: (e, _) => _ErrorList(
          message: e.toString(),
          padding: pad,
          onRetry: () => ref.invalidate(_teamLeavesProvider),
        ),
        data: (allRows) {
          // Cancelled leaves are not relevant to a reviewer — hide them.
          final rows =
              allRows.where((r) => r.status != 'CANCELLED').toList();
          final pending = rows.where((r) => r.status == 'PENDING').length;
          final approved = rows.where((r) => r.status == 'APPROVED').length;
          final rejected = rows.where((r) => r.status == 'REJECTED').length;
          final filtered = _filter == 'ALL'
              ? rows
              : rows.where((r) => r.status == _filter).toList();

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pad,
            children: [
              _TeamSummary(
                total: rows.length,
                pending: pending,
                approved: approved,
                rejected: rejected,
              ),
              const SizedBox(height: 16),
              _FilterBar(
                value: _filter,
                onChanged: (v) => setState(() => _filter = v),
                counts: {
                  'ALL': rows.length,
                  'PENDING': pending,
                  'APPROVED': approved,
                  'REJECTED': rejected,
                },
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                const AppEmptyState(
                  icon: Icons.event_available_rounded,
                  message: 'Nothing here right now.',
                )
              else
                for (final r in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TeamLeaveCard(
                      r: r,
                      canReview: canReview && r.status == 'PENDING',
                      reviewerEmployeeId: user?.employeeId,
                      onReviewed: () => ref.invalidate(_teamLeavesProvider),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Attendance tab (regularization approve / reject)
// ─────────────────────────────────────────────────────────────────────

class _AttendanceView extends ConsumerStatefulWidget {
  const _AttendanceView();

  @override
  ConsumerState<_AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends ConsumerState<_AttendanceView> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final async = ref.watch(teamRegularizationsProvider);
    final mq = MediaQuery.of(context);
    final pad = EdgeInsets.fromLTRB(
      16,
      4,
      16,
      mq.padding.bottom + AppChrome.bottomNavHeight + 16,
    );

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(teamRegularizationsProvider),
      child: async.when(
        loading: () => const _CenterLoader(),
        error: (e, _) => _ErrorList(
          message: e.toString(),
          padding: pad,
          onRetry: () => ref.invalidate(teamRegularizationsProvider),
        ),
        data: (rows) {
          final pending = rows.where((r) => r.status == 'PENDING').length;
          final approved = rows.where((r) => r.status == 'APPROVED').length;
          final rejected = rows.where((r) => r.status == 'REJECTED').length;
          final filtered = _filter == 'ALL'
              ? rows
              : rows.where((r) => r.status == _filter).toList();
          // Pending first within the current filter.
          final sorted = [
            ...filtered.where((r) => r.isPending),
            ...filtered.where((r) => !r.isPending),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pad,
            children: [
              _TeamSummary(
                total: rows.length,
                pending: pending,
                approved: approved,
                rejected: rejected,
              ),
              const SizedBox(height: 16),
              _FilterBar(
                value: _filter,
                onChanged: (v) => setState(() => _filter = v),
                counts: {
                  'ALL': rows.length,
                  'PENDING': pending,
                  'APPROVED': approved,
                  'REJECTED': rejected,
                },
              ),
              const SizedBox(height: 14),
              if (sorted.isEmpty)
                const AppEmptyState(
                  icon: Icons.fact_check_outlined,
                  message: 'Nothing here right now.',
                )
              else
                for (final r in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RegularizationCard(
                      r: r,
                      reviewerEmployeeId: user?.employeeId,
                      onReviewed: () =>
                          ref.invalidate(teamRegularizationsProvider),
                    ),
                  ),
            ],
          );
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
          decoration: const InputDecoration(hintText: 'Add a comment (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isApprove ? AppColors.success : AppColors.danger,
            ),
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
    final tone = r.statusTone;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: r.employeeName ?? '?', size: 36, radius: 11),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.employeeName ?? 'Employee',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (r.date != null) r.date!,
                        if (r.requestedStatus != null) r.requestedStatus!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          if (r.timeSummary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    r.timeSummary,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (r.reason != null && r.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.format_quote_rounded,
                    size: 13, color: AppColors.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    r.reason!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkSoft,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.check_rounded,
                    label: 'Approve',
                    color: AppColors.success,
                    onTap: _busy ? null : () => _review('APPROVED'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.close_rounded,
                    label: 'Reject',
                    color: AppColors.danger,
                    outlined: true,
                    onTap: _busy ? null : () => _review('REJECTED'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────

class _CenterLoader extends StatelessWidget {
  const _CenterLoader();
  @override
  Widget build(BuildContext context) {
    // Wrapped so RefreshIndicator's pull-to-refresh still works while loading.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 140),
        Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ],
    );
  }
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({
    required this.message,
    required this.padding,
    required this.onRetry,
  });
  final String message;
  final EdgeInsets padding;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: [
        const SizedBox(height: 8),
        AppErrorPanel(message: message, onRetry: onRetry),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Leaves summary + filter + card (unchanged behaviour)
// ─────────────────────────────────────────────────────────────────────

class _TeamSummary extends StatelessWidget {
  const _TeamSummary({
    required this.total,
    required this.pending,
    required this.approved,
    required this.rejected,
  });
  final int total;
  final int pending;
  final int approved;
  final int rejected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.32),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$total request${total == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pending > 0
                  ? '$pending pending your review'
                  : 'All caught up — nice work',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Pending',
                    value: pending,
                    color: const Color(0xFFFBBF24),
                  ),
                ),
                Container(
                    width: 1, height: 28, color: Colors.white.withOpacity(0.18)),
                Expanded(
                  child: _MiniStat(
                    label: 'Approved',
                    value: approved,
                    color: const Color(0xFF34D399),
                  ),
                ),
                Container(
                    width: 1, height: 28, color: Colors.white.withOpacity(0.18)),
                Expanded(
                  child: _MiniStat(
                    label: 'Rejected',
                    value: rejected,
                    color: const Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Left-aligned so the first stat lines up under the card's title/subtitle
    // (which use CrossAxisAlignment.start) instead of sitting indented.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              value.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.onChanged,
    required this.counts,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, int> counts;

  static const _items = [
    ('ALL', 'All'),
    ('PENDING', 'Pending'),
    ('APPROVED', 'Approved'),
    ('REJECTED', 'Rejected'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (final it in _items) ...[
            _FilterChip(
              label: it.$2,
              count: counts[it.$1] ?? 0,
              selected: value == it.$1,
              onTap: () => onChanged(it.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withOpacity(0.18)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.muted,
                ),
              ),
            ),
          ],
        ),
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
            style: FilledButton.styleFrom(
              backgroundColor: isApprove ? AppColors.success : AppColors.danger,
            ),
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
    final tone = StatusTone.forLeave(r.status);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: r.employeeName ?? '?', size: 36, radius: 11),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.employeeName ?? 'Employee',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${r.leaveType} · ${r.numberOfDays ?? "?"} day(s)',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 13, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${r.fromDate}  →  ${r.toDate}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (r.reason != null && r.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.format_quote_rounded,
                    size: 13, color: AppColors.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    r.reason!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkSoft,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (widget.canReview) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.check_rounded,
                    label: 'Approve',
                    color: AppColors.success,
                    onTap: _busy ? null : () => _review('APPROVED'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.close_rounded,
                    label: 'Reject',
                    color: AppColors.danger,
                    outlined: true,
                    onTap: _busy ? null : () => _review('REJECTED'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outlined
                ? Colors.transparent
                : (disabled ? color.withOpacity(0.4) : color),
            border: outlined
                ? Border.all(color: color.withOpacity(0.5), width: 1.3)
                : null,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: outlined ? color : Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: outlined ? color : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
