import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/approvals.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

/// Leave-type options for an employee, built the same way the web does:
/// active policies only, filtered to the employee's gender. Types that need
/// extra inputs the mobile form doesn't collect (restricted-holiday picker,
/// comp-off worked date) are excluded.
final _leaveTypeOptionsProvider = FutureProvider.autoDispose
    .family<List<({String code, String label})>, int>((ref, employeeId) async {
  final policies =
      await ref.watch(leaveRepositoryProvider).listLeaveTypes(activeOnly: true);
  String? gender;
  try {
    final emp = await ref.watch(apiClientProvider).get<Map<String, dynamic>>(
          '/api/employees/$employeeId',
          parse: (d) => d as Map<String, dynamic>,
        );
    gender = emp['gender'] as String?;
  } catch (_) {/* gender unknown → show gender-neutral types only */}

  const needsExtraInput = {'RESTRICTED_HOLIDAY', 'COMPENSATORY'};
  return policies
      .where((p) => p.active)
      .where((p) =>
          p.allowedGender == 'ANY' ||
          (gender != null && p.allowedGender == gender))
      .where((p) => !needsExtraInput.contains(p.code))
      .map((p) => (code: p.code, label: p.label))
      .toList();
});

IconData _leaveTypeIcon(String code) {
  switch (code.toUpperCase()) {
    case 'CASUAL':
      return Icons.coffee_rounded;
    case 'SICK':
      return Icons.medical_services_rounded;
    case 'EARNED':
      return Icons.beach_access_rounded;
    case 'MATERNITY':
      return Icons.child_friendly_rounded;
    case 'PATERNITY':
      return Icons.family_restroom_rounded;
    case 'UNPAID':
      return Icons.savings_rounded;
    case 'RESTRICTED_HOLIDAY':
      return Icons.celebration_rounded;
    case 'COMPENSATORY':
      return Icons.sync_alt_rounded;
    default:
      return Icons.event_note_rounded;
  }
}

final _myLeavesProvider = FutureProvider.autoDispose<List<LeaveRequest>>((ref) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref.watch(leaveRepositoryProvider).listForEmployee(user!.employeeId!);
});

final _myBalanceProvider =
    FutureProvider.autoDispose<EmployeeLeaveBalances?>((ref) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value(null);
  return ref.watch(leaveRepositoryProvider).getBalance(user!.employeeId!);
});

/// Hero dot colours / list icon colours for balance categories (by position).
const _balanceDots = <Color>[
  Color(0xFF8CC63F),
  Color(0xFF6FB8F0),
  Color(0xFFF2B347),
  Color(0xFFA78BFA),
  Color(0xFFEF8A8A),
];

Color _balanceInk(int i) {
  switch (i % 5) {
    case 0:
      return AppColors.success;
    case 1:
      return AppColors.info;
    case 2:
      return AppColors.warning;
    case 3:
      return AppColors.pink;
    default:
      return AppColors.danger;
  }
}

String _balanceText(LeaveBalance b) =>
    b.balanceDays == null ? '∞' : fmtLeaveDays(b.balanceDays);

String _allowanceText(LeaveBalance b) =>
    b.allowanceDays == null ? '∞' : '${b.allowanceDays}';

/// Status pill for a leave request (same labels as before).
Widget _leavePill(String status) {
  final tone = StatusTone.forLeave(status);
  switch (status) {
    case 'APPROVED':
      return ProPill.ok(tone.label);
    case 'REJECTED':
      return ProPill.bad(tone.label);
    case 'CANCELLED':
      return ProPill.neutral(tone.label);
    default:
      return ProPill.warn(tone.label);
  }
}

class LeavesScreen extends ConsumerWidget {
  const LeavesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(_myBalanceProvider);
    final leaves = ref.watch(_myLeavesProvider);
    final pendingMyApproval = ref.watch(leavesPendingMyApprovalProvider);

    final balances = balance.valueOrNull?.balances ?? const <LeaveBalance>[];
    final finite = balances
        .where((b) => b.allowanceDays != null && b.balanceDays != null)
        .toList();
    final totalLeft = finite.fold<double>(0, (a, b) => a + b.balanceDays!);
    final totalAllowance =
        finite.fold<double>(0, (a, b) => a + b.allowanceDays!);
    final totalUsed = finite.fold<double>(0, (a, b) => a + b.usedDays);

    final myRows = leaves.valueOrNull;
    final pendingCount = myRows?.where((r) => r.status == 'PENDING').length;
    final approvedCount = myRows?.where((r) => r.status == 'APPROVED').length;
    final approvalRows = pendingMyApproval.valueOrNull;

    final String subtitle;
    if (finite.isNotEmpty) {
      subtitle =
          '${fmtLeaveDays(totalLeft)} of ${fmtLeaveDays(totalAllowance)} days left';
    } else {
      subtitle = 'Balances, requests & approvals';
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProPage(
        topInset: MediaQuery.of(context).padding.top,
        clearNav: true,
        gap: 22,
        onRefresh: () async {
          ref.invalidate(_myBalanceProvider);
          ref.invalidate(_myLeavesProvider);
          ref.invalidate(leavesPendingMyApprovalProvider);
        },
        hero: ProHero(
          title: 'Leaves',
          subtitle: subtitle,
          actions: [
            ProHeroIconButton(
              icon: Icons.add_rounded,
              tooltip: 'Apply for leave',
              onTap: () => _openRequest(context, ref),
            ),
          ],
          overlap: ProKpiStrip(
            cells: [
              ProKpi(
                value: pendingCount?.toString() ?? '—',
                label: 'My requests pending',
              ),
              ProKpi(
                value: approvalRows?.length.toString() ?? '—',
                label: 'Waiting for my approval',
                valueColor: (approvalRows?.isNotEmpty ?? false)
                    ? AppColors.warning
                    : null,
              ),
              ProKpi(
                value: approvedCount?.toString() ?? '—',
                label: 'Approved',
              ),
            ],
          ),
          children: [
            balance.when(
              data: (b) => (b == null || b.balances.isEmpty)
                  ? const _HeroLine(
                      icon: Icons.beach_access_rounded,
                      text: 'No balance configured yet.',
                    )
                  : ProHeroStats(
                      stats: [
                        for (var i = 0; i < b.balances.length && i < 3; i++)
                          ProStat(
                            label: b.balances[i].leaveTypeLabel,
                            value: _balanceText(b.balances[i]),
                            sub:
                                '${fmtLeaveDays(b.balances[i].usedDays)} used of ${_allowanceText(b.balances[i])}',
                            dot: _balanceDots[i % _balanceDots.length],
                          ),
                      ],
                    ),
              loading: () => const _HeroLine(
                icon: Icons.hourglass_empty_rounded,
                text: 'Loading your balance…',
              ),
              error: (_, __) => const _HeroLine(
                icon: Icons.error_outline_rounded,
                text: 'Could not load your balance.',
              ),
            ),
            if (finite.isNotEmpty && totalAllowance > 0)
              _HeroUsageBar(used: totalUsed, left: totalLeft),
          ],
        ),
        children: [
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () => _openRequest(context, ref),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Apply for leave'),
            ),
          ),
          // Approval-engine queue: leaves waiting on ME as a configured
          // chain approver (chain approvers aren't necessarily managers, so
          // it lives on the employee-facing screen — hidden when empty,
          // exactly like the web's PendingApprovalsPanel).
          ...pendingMyApproval.maybeWhen(
            data: (rows) => rows.isEmpty
                ? const <Widget>[]
                : [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ProSectionHeader(
                          title: 'Pending my approval · ${rows.length}',
                          subtitle: 'Leave requests waiting on you',
                        ),
                        const SizedBox(height: 8),
                        const ProSwipeHint(),
                        const SizedBox(height: 10),
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _ApprovalQueueTile(r: rows[i]),
                        ],
                      ],
                    ),
                  ],
            orElse: () => const <Widget>[],
          ),
          // Every category (the hero shows the first three).
          ...balance.when(
            data: (b) => (b == null || b.balances.length <= 3)
                ? const <Widget>[]
                : [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ProSectionHeader(
                          title: 'Leave balance',
                          subtitle: 'Days available for each category',
                        ),
                        const SizedBox(height: 10),
                        ProListGroup(
                          children: [
                            for (var i = 0; i < b.balances.length; i++)
                              _BalanceRow(b: b.balances[i], index: i),
                          ],
                        ),
                      ],
                    ),
                  ],
            loading: () => const <Widget>[],
            error: (e, _) => [
              AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(_myBalanceProvider),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: myRows == null || myRows.isEmpty
                    ? 'My requests'
                    : 'My requests · ${myRows.length}',
                subtitle: 'Track the status of your leaves',
              ),
              const SizedBox(height: 10),
              leaves.when(
                data: (rows) {
                  if (rows.isEmpty) {
                    return const ProEmpty(
                      icon: Icons.event_note_rounded,
                      title: 'No leave requests yet',
                      message: 'Tap the button above to create one.',
                    );
                  }
                  return ProListGroup(
                    children: [for (final r in rows) _LeaveTile(r: r)],
                  );
                },
                loading: () => const AppLoadingBlock(height: 130),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(_myLeavesProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRequest(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authUserProvider);
    if (user?.employeeId == null) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestSheet(employeeId: user!.employeeId!),
    );
    if (result == true) {
      ref.invalidate(_myLeavesProvider);
      ref.invalidate(_myBalanceProvider);
    }
  }
}

/// One-line message on the deep hero (empty / loading / error balance).
class _HeroLine extends StatelessWidget {
  const _HeroLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xE0FFFFFF)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Used vs left across the limited categories.
class _HeroUsageBar extends StatelessWidget {
  const _HeroUsageBar({required this.used, required this.left});
  final double used;
  final double left;

  @override
  Widget build(BuildContext context) {
    const usedColor = Color(0xFFF2B347);
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: Colors.white.withOpacity(0.72),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProStackBar(
          parts: [
            MapEntry(used, usedColor),
            MapEntry(left, AppColors.live),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: usedColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('${fmtLeaveDays(used)} used', style: style),
            const Spacer(),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: AppColors.live, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('${fmtLeaveDays(left)} left', style: style),
          ],
        ),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.b, required this.index});
  final LeaveBalance b;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ProListRow(
      leading: ProIconWell(
        icon: _leaveTypeIcon(b.leaveTypeCode),
        color: _balanceInk(index),
      ),
      title: b.leaveTypeLabel,
      subtitle: '${fmtLeaveDays(b.usedDays)} used · ${_allowanceText(b)} total',
      value: '${_balanceText(b)} days',
    );
  }
}

/// "CASUAL" → "Casual leave" — open leave-type codes are DB-driven now, so
/// unknown codes humanize generically instead of mapping through an enum.
String _humanLeaveType(String t) {
  if (t.isEmpty) return t;
  final s = t.toLowerCase().replaceAll('_', ' ');
  return '${s[0].toUpperCase()}${s.substring(1)} leave';
}

/// One leave waiting on the signed-in user as a configured chain approver —
/// requester, dates, live chain, and Approve / Reject actions (buttons or swipe).
class _ApprovalQueueTile extends ConsumerStatefulWidget {
  const _ApprovalQueueTile({required this.r});
  final LeaveRequest r;

  @override
  ConsumerState<_ApprovalQueueTile> createState() => _ApprovalQueueTileState();
}

class _ApprovalQueueTileState extends ConsumerState<_ApprovalQueueTile> {
  bool _busy = false;

  Future<void> _review(String status) async {
    final user = ref.read(authUserProvider);
    setState(() => _busy = true);
    try {
      await ref.read(leaveRepositoryProvider).review(
            widget.r.id,
            status: status,
            reviewerEmployeeId: user?.employeeId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'APPROVED'
            ? 'Leave approved.'
            : 'Leave rejected.'),
      ));
      ref.invalidate(leavesPendingMyApprovalProvider);
      ref.invalidate(_myLeavesProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final name = r.employeeName ?? 'Employee #${r.employeeId}';
    final steps = ref.watch(leaveApprovalStepsProvider(r.id));
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
                        height: 1.33,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '${_humanLeaveType(r.leaveType)} · ${r.daysLabel} · ${r.fromDate} → ${r.toDate}',
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
              ProPill.warn('Awaiting you'),
            ],
          ),
          if (r.reason != null && r.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '“${r.reason!.trim()}”',
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.inkSoft,
              ),
            ),
          ],
          steps.maybeWhen(
            data: (s) => s.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ApprovalChainInline(steps: s),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.dangerTint,
                    foregroundColor: AppColors.danger,
                  ),
                  onPressed: _busy ? null : () => _review('REJECTED'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _review('APPROVED'),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: ProSwipeDecision(
        onApprove: _busy ? null : () => _review('APPROVED'),
        onReject: _busy ? null : () => _review('REJECTED'),
        child: card,
      ),
    );
  }
}

class _LeaveTile extends ConsumerStatefulWidget {
  const _LeaveTile({required this.r});
  final LeaveRequest r;

  @override
  ConsumerState<_LeaveTile> createState() => _LeaveTileState();
}

class _LeaveTileState extends ConsumerState<_LeaveTile> {
  bool _busy = false;

  /// Withdraw an own request that nobody has acted on yet. This list is always
  /// the signed-in employee's own leaves, so ownership needs no extra check —
  /// only the PENDING gate, matching the web's Cancel button.
  Future<void> _withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: const Text(
          'Your leave request will be cancelled and removed from your '
          'approver\'s queue. You can apply again if you change your mind.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerTint,
              foregroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(leaveRepositoryProvider).cancel(widget.r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave request withdrawn.')),
      );
      // The days go back to the balance, and the request leaves any approver's
      // queue, so refresh all three views of it.
      ref.invalidate(_myLeavesProvider);
      ref.invalidate(_myBalanceProvider);
      ref.invalidate(leavesPendingMyApprovalProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final tone = StatusTone.forLeave(r.status);
    // Show the configured approval chain on in-flight requests (empty = the
    // default direct-manager flow → nothing rendered).
    final steps = r.status == 'PENDING'
        ? ref.watch(leaveApprovalStepsProvider(r.id))
        : null;
    final hasReason = r.reason != null && r.reason!.isNotEmpty;
    final isPending = r.status == 'PENDING';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProListRow(
          leading: ProIconWell(
            icon: _leaveTypeIcon(r.leaveType),
            color: tone.color,
          ),
          title: _humanType(r.leaveType),
          subtitle: '${r.daysLabel} · ${r.fromDate} → ${r.toDate}',
          pill: _leavePill(r.status),
        ),
        if (hasReason || steps != null || isPending)
          Padding(
            padding: const EdgeInsets.fromLTRB(58, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasReason)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(Icons.format_quote_rounded,
                            size: 15, color: AppColors.faint),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          r.reason!,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (steps != null)
                  steps.maybeWhen(
                    data: (s) => s.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: ApprovalChainInline(steps: s),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                // Only an untouched request can be withdrawn. Once it is approved or
                // rejected the decision is the approver's to undo, not the employee's.
                if (isPending) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: _busy ? null : _withdraw,
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.undo_rounded, size: 16),
                    label: Text(_busy ? 'Withdrawing…' : 'Withdraw request'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _humanType(String t) => _humanLeaveType(t);
}

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.employeeId});
  final int employeeId;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  String _type = '';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  /// FIRST_HALF | SECOND_HALF for a half-day; null = full day. Only meaningful
  /// (and only shown) when From and To are the same day.
  String? _half;
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _err;

  bool get _singleDay => DateUtils.isSameDay(_from, _to);

  Future<void> _pick({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
      }
      if (!DateUtils.isSameDay(_from, _to)) _half = null;
    });
  }

  Future<void> _submit() async {
    if (_type.isEmpty) {
      setState(() => _err = 'Please select a leave type.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _err = 'Please enter a reason.');
      return;
    }
    setState(() {
      _submitting = true;
      _err = null;
    });
    try {
      await ref.read(leaveRepositoryProvider).create(LeaveCreateRequest(
            employeeId: widget.employeeId,
            leaveType: _type,
            fromDate: DateFormat('yyyy-MM-dd').format(_from),
            toDate: DateFormat('yyyy-MM-dd').format(_to),
            reason: _reason.text.trim(),
            halfDaySession: _singleDay ? _half : null,
          ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, d MMM y');
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.92,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC6D3D6),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Request leave',
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Pick a category and dates that work for you.',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProField(
                        label: 'Leave type',
                        required: true,
                        child: ref
                            .watch(_leaveTypeOptionsProvider(widget.employeeId))
                            .when(
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    height: 20,
                                    width: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              ),
                              error: (e, _) => Text(
                                'Could not load leave types: $e',
                                style: const TextStyle(
                                    color: AppColors.danger, fontSize: 12.5),
                              ),
                              data: (opts) {
                                if (opts.isEmpty) {
                                  return const Text(
                                    'No leave types are available for your account.',
                                    style: TextStyle(
                                        color: AppColors.muted, fontSize: 13),
                                  );
                                }
                                // Default to the first allowed type once options arrive.
                                if (!opts.any((o) => o.code == _type)) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted &&
                                        !opts.any((o) => o.code == _type)) {
                                      setState(() => _type = opts.first.code);
                                    }
                                  });
                                }
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final o in opts)
                                      _TypeChip(
                                        label: o.label,
                                        icon: _leaveTypeIcon(o.code),
                                        selected: _type == o.code,
                                        onTap: () =>
                                            setState(() => _type = o.code),
                                      ),
                                  ],
                                );
                              },
                            ),
                      ),
                      const SizedBox(height: 18),
                      ProField(
                        label: 'Dates',
                        required: true,
                        child: Row(
                          children: [
                            Expanded(
                              child: _DateField(
                                label: 'From',
                                value: df.format(_from),
                                onTap: () => _pick(isFrom: true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DateField(
                                label: 'To',
                                value: df.format(_to),
                                onTap: () => _pick(isFrom: false),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_singleDay) ...[
                        const SizedBox(height: 18),
                        ProField(
                          label: 'Duration',
                          helper: _half != null
                              ? 'A half-day leave counts 0.5 day against your balance.'
                              : null,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _TypeChip(
                                label: 'Full day',
                                icon: Icons.today_rounded,
                                selected: _half == null,
                                onTap: () => setState(() => _half = null),
                              ),
                              _TypeChip(
                                label: 'First half',
                                icon: Icons.wb_twilight_rounded,
                                selected: _half == 'FIRST_HALF',
                                onTap: () =>
                                    setState(() => _half = 'FIRST_HALF'),
                              ),
                              _TypeChip(
                                label: 'Second half',
                                icon: Icons.nights_stay_rounded,
                                selected: _half == 'SECOND_HALF',
                                onTap: () =>
                                    setState(() => _half = 'SECOND_HALF'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ProField(
                        label: 'Reason',
                        required: true,
                        child: TextField(
                          controller: _reason,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'Why are you taking these days?',
                          ),
                        ),
                      ),
                      if (_err != null) ...[
                        const SizedBox(height: 12),
                        ProNote(_err!, tone: ProNoteTone.bad),
                      ],
                    ],
                  ),
                ),
              ),
              ProBottomBar(
                children: [
                  OutlinedButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Submit request'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable chip (ink when selected) for leave type / duration.
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          side: BorderSide(
            color: selected ? AppColors.ink : const Color(0xFFDBE3E5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected ? Colors.white : AppColors.inkSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.inkSoft,
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: Color(0xFFD9E2E4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
