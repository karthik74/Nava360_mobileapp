import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../leaves/leave_models.dart';
import '../leaves/leave_repository.dart';

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
  String _filter = 'ALL'; // ALL, PENDING, APPROVED, REJECTED

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canReview = user?.hasRole(const {'ADMIN', 'HR'}) ?? false;
    final leaves = ref.watch(_teamLeavesProvider);

    final mq = MediaQuery.of(context);
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white.withOpacity(0.85),
      onRefresh: () async => ref.invalidate(_teamLeavesProvider),
      child: leaves.when(
        data: (rows) {
          final pending = rows.where((r) => r.status == 'PENDING').length;
          final approved = rows.where((r) => r.status == 'APPROVED').length;
          final rejected = rows.where((r) => r.status == 'REJECTED').length;
          final filtered = _filter == 'ALL'
              ? rows
              : rows.where((r) => r.status == _filter).toList();

          return ListView(
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
              _TeamSummary(
                total: rows.length,
                pending: pending,
                approved: approved,
                rejected: rejected,
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const AppEmptyState(
                  icon: Icons.groups_2_rounded,
                  message: 'Nothing here right now.',
                )
              else
                Column(
                  children: [
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
                ),
            ],
          );
        },
        loading: () => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e.toString(),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ),
      ),
    );
  }
}

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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      child: const Text(
                        'TEAM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                      width: 1,
                      height: 28,
                      color: Colors.white.withOpacity(0.18),
                    ),
                    Expanded(
                      child: _MiniStat(
                        label: 'Approved',
                        value: approved,
                        color: const Color(0xFF34D399),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withOpacity(0.18),
                    ),
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
        ],
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
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
          color: selected ? AppColors.ink : Colors.white.withOpacity(0.55),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.ink : Colors.white.withOpacity(0.55),
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
                    : Colors.white.withOpacity(0.7),
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isApprove ? AppColors.success : AppColors.danger)
                    .withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isApprove ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 18,
                color: isApprove ? AppColors.success : AppColors.danger,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isApprove ? 'Approve request' : 'Reject request',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters;
  }

  Color _avatarColor(String? name) {
    final hash = (name ?? '?').hashCode.abs();
    const colors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF10B981),
      Color(0xFF3B82F6),
      Color(0xFFF59E0B),
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final tone = StatusTone.forLeave(r.status);
    final avatarColor = _avatarColor(r.employeeName);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      avatarColor,
                      avatarColor.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(r.employeeName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
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
              color: Colors.white.withOpacity(0.45),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: Colors.white.withOpacity(0.55)),
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
            boxShadow: outlined || disabled
                ? null
                : [
                    BoxShadow(
                      color: color.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
