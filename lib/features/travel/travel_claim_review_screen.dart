import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download_saver.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'travel_approvals_screen.dart';
import 'travel_models.dart';
import 'travel_repository.dart';

/// Full claim detail for a manager/approver or finance user — header, expense
/// breakdown, the immutable approval timeline and a role-aware action bar
/// (approve / reject / send-back while pending at the caller's level; settle on
/// fully APPROVED claims for `TRAVEL_CLAIM_SETTLE` holders). Reachable from the
/// approval inbox, the settlement queue and claim push deep-links.
final travelClaimReviewProvider =
    FutureProvider.autoDispose.family<TravelClaim, int>((ref, id) {
  return ref.watch(travelRepositoryProvider).getClaim(id);
});

/// Limit-vs-claimed evaluation for the claim (owner/approver only). Surfaced as
/// an extra context section; failures are swallowed so the page still renders.
final travelClaimEvaluationProvider =
    FutureProvider.autoDispose.family<TravelPolicyEvaluation?, int>((ref, id) async {
  try {
    return await ref.watch(travelRepositoryProvider).evaluation(id);
  } catch (_) {
    return null;
  }
});

class TravelClaimReviewScreen extends ConsumerWidget {
  const TravelClaimReviewScreen({super.key, required this.claimId});
  final int claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(travelClaimReviewProvider(claimId));

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Review Claim'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: AppErrorPanel(
              message: e.toString(),
              onRetry: () =>
                  ref.invalidate(travelClaimReviewProvider(claimId)),
            ),
          ),
          data: (claim) => _ClaimBody(claim: claim),
        ),
        bottomNavigationBar: async.maybeWhen(
          data: (claim) => _ActionBar(claim: claim),
          orElse: () => null,
        ),
      ),
    );
  }
}

class _ClaimBody extends ConsumerWidget {
  const _ClaimBody({required this.claim});
  final TravelClaim claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = travelClaimTone(claim.status);
    final mq = MediaQuery.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, mq.padding.bottom + 24),
      children: [
        // ── Header ──────────────────────────────────────────────────────
        GlassCard(
          shadow: AppShadows.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      claim.title.isEmpty ? 'Travel claim' : claim.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(label: tone.label, color: tone.color),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 15, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      [claim.employeeName, claim.employeeCode]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (claim.claimCode != null)
                    Text(
                      claim.claimCode!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              if (claim.hasPolicyViolation) ...[
                const SizedBox(height: 12),
                _ViolationBanner(details: claim.violationDetails),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Amount summary ──────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _AmountTile(
                label: 'Claimed',
                value: travelMoney(claim.totalClaimedAmount),
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AmountTile(
                label: 'Approved',
                value: claim.totalApprovedAmount == null
                    ? '—'
                    : travelMoney(claim.totalApprovedAmount),
                color: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Meta ────────────────────────────────────────────────────────
        GlassCard(
          shadow: AppShadows.soft,
          child: Column(
            children: [
              _MetaRow(
                  label: 'Travel dates',
                  value:
                      '${travelDate(claim.fromDate)}  –  ${travelDate(claim.toDate)}'),
              if (claim.policyNameSnapshot != null)
                _MetaRow(label: 'Policy', value: claim.policyNameSnapshot!),
              if (claim.approvalLevels != null)
                _MetaRow(
                    label: 'Approval levels',
                    value: '${claim.approvalLevels}'),
              if (claim.submittedAt != null)
                _MetaRow(
                    label: 'Submitted',
                    value: travelDateTime(claim.submittedAt)),
              if (claim.purpose != null && claim.purpose!.trim().isNotEmpty)
                _MetaRow(label: 'Purpose', value: claim.purpose!),
              if (claim.submissionRemarks != null &&
                  claim.submissionRemarks!.trim().isNotEmpty)
                _MetaRow(
                    label: 'Submission note',
                    value: claim.submissionRemarks!),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Expenses ────────────────────────────────────────────────────
        const AppSectionHeader(title: 'Expenses'),
        const SizedBox(height: 8),
        if (claim.expenses.isEmpty)
          const AppEmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'No expense lines on this claim.',
          )
        else
          for (final e in claim.expenses)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ExpenseRow(expense: e),
            ),
        const SizedBox(height: 16),

        // ── Policy evaluation (limit vs claimed) ────────────────────────
        _EvaluationSection(claimId: claim.id),

        // ── Approval timeline ───────────────────────────────────────────
        if (claim.approvalSteps.isNotEmpty) ...[
          const AppSectionHeader(title: 'Approval timeline'),
          const SizedBox(height: 8),
          GlassCard(
            shadow: AppShadows.soft,
            child: Column(
              children: [
                for (int i = 0; i < claim.approvalSteps.length; i++)
                  _TimelineTile(
                    step: claim.approvalSteps[i],
                    isLast: i == claim.approvalSteps.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Claim-level bills ───────────────────────────────────────────
        if (claim.attachments.isNotEmpty) ...[
          const AppSectionHeader(title: 'Bills & attachments'),
          const SizedBox(height: 8),
          for (final a in claim.attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AttachmentRow(claimId: claim.id, attachment: a),
            ),
          const SizedBox(height: 16),
        ],

        // ── Settlement record ───────────────────────────────────────────
        if (claim.settlement != null) _SettlementCard(s: claim.settlement!),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Action bar — approve / reject / send-back / settle
// ════════════════════════════════════════════════════════════════════════════

class _ActionBar extends ConsumerStatefulWidget {
  const _ActionBar({required this.claim});
  final TravelClaim claim;

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _busy = false;

  TravelClaim get claim => widget.claim;

  /// The current PENDING step (the one awaiting a decision), if any.
  TravelClaimApprovalStep? get _currentStep {
    for (final s in claim.approvalSteps) {
      if (s.current && s.status == 'PENDING') return s;
    }
    for (final s in claim.approvalSteps) {
      if (s.status == 'PENDING') return s;
    }
    return null;
  }

  void _refresh() {
    ref.invalidate(travelClaimReviewProvider(claim.id));
    ref.invalidate(travelClaimEvaluationProvider(claim.id));
    ref.invalidate(travelInboxProvider);
    ref.invalidate(travelSettlementQueueProvider);
  }

  Future<void> _run(
    Future<void> Function() action,
    String success,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      _refresh();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final remarks = await _promptRemarks(
      context,
      title: 'Approve claim',
      hint: 'Add an optional note…',
      confirmLabel: 'Approve',
      confirmColor: AppColors.success,
      mandatory: false,
    );
    if (remarks == null) return; // cancelled
    await _run(
      () => ref
          .read(travelRepositoryProvider)
          .approve(claim.id, remarks: remarks.isEmpty ? null : remarks),
      'Claim approved',
    );
  }

  Future<void> _reject() async {
    final remarks = await _promptRemarks(
      context,
      title: 'Reject claim',
      hint: 'Reason for rejection (required)',
      confirmLabel: 'Reject',
      confirmColor: AppColors.danger,
      mandatory: true,
    );
    if (remarks == null || remarks.isEmpty) return;
    await _run(
      () => ref.read(travelRepositoryProvider).reject(claim.id, remarks: remarks),
      'Claim rejected',
    );
  }

  Future<void> _sendBack() async {
    final remarks = await _promptRemarks(
      context,
      title: 'Send back to employee',
      hint: 'What needs to change? (required)',
      confirmLabel: 'Send back',
      confirmColor: AppColors.warning,
      mandatory: true,
    );
    if (remarks == null || remarks.isEmpty) return;
    await _run(
      () =>
          ref.read(travelRepositoryProvider).sendBack(claim.id, remarks: remarks),
      'Claim sent back',
    );
  }

  Future<void> _settle() async {
    final result = await _promptSettlement(
      context,
      defaultAmount: claim.totalApprovedAmount ?? claim.totalClaimedAmount ?? 0,
    );
    if (result == null) return;
    await _run(
      () => ref.read(travelRepositoryProvider).settle(
            claim.id,
            settledAmount: result.amount,
            paymentMode: result.paymentMode,
            paymentReference: result.reference,
            remarks: result.remarks,
          ),
      'Claim settled',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final me = user?.employeeId;
    final step = _currentStep;
    final isCurrentApprover =
        step != null && me != null && step.approverEmployeeId == me;
    final canSettle = claim.status == 'APPROVED' &&
        (user?.hasPermission('TRAVEL_CLAIM_SETTLE') ?? false);

    // Nothing actionable → no bar (terminal states or not my turn).
    if (!isCurrentApprover && !canSettle) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: _busy
            ? const SizedBox(
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            : canSettle
                ? SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      onPressed: _settle,
                      icon: const Icon(
                          Icons.account_balance_wallet_rounded, size: 18),
                      label: const Text('Settle claim'),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: BorderSide(
                                color: AppColors.danger.withOpacity(0.5)),
                          ),
                          onPressed: _reject,
                          icon: const Icon(Icons.close_rounded, size: 17),
                          label: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.warning,
                            side: BorderSide(
                                color: AppColors.warning.withOpacity(0.5)),
                          ),
                          onPressed: _sendBack,
                          icon: const Icon(Icons.reply_rounded, size: 17),
                          label: const Text('Send back'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success),
                          onPressed: _approve,
                          icon: const Icon(Icons.check_rounded, size: 17),
                          label: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Dialogs
// ════════════════════════════════════════════════════════════════════════════

/// Returns the entered remarks, or null if cancelled. When [mandatory] is true
/// the confirm button stays disabled until some text is entered.
Future<String?> _promptRemarks(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  required Color confirmColor,
  required bool mandatory,
}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final canConfirm = !mandatory || ctrl.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(hintText: hint),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: confirmColor),
                onPressed: canConfirm
                    ? () => Navigator.pop(ctx, ctrl.text.trim())
                    : null,
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

class _SettlementResult {
  _SettlementResult({
    required this.amount,
    this.paymentMode,
    this.reference,
    this.remarks,
  });
  final double amount;
  final String? paymentMode;
  final String? reference;
  final String? remarks;
}

/// Collects the finance settlement details for an APPROVED claim.
Future<_SettlementResult?> _promptSettlement(
  BuildContext context, {
  required double defaultAmount,
}) {
  final amountCtrl = TextEditingController(
      text: defaultAmount > 0 ? defaultAmount.toStringAsFixed(0) : '');
  final refCtrl = TextEditingController();
  final remarksCtrl = TextEditingController();
  String mode = TravelEnums.paymentModes.first;

  return showDialog<_SettlementResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final amount = double.tryParse(amountCtrl.text.trim());
          final valid = amount != null && amount > 0;
          return AlertDialog(
            title: const Text('Settle claim',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Settled amount',
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: mode,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Payment mode'),
                    items: [
                      for (final m in TravelEnums.paymentModes)
                        DropdownMenuItem(
                            value: m, child: Text(TravelEnums.label(m))),
                    ],
                    onChanged: (v) => setLocal(() => mode = v ?? mode),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Payment reference (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                        labelText: 'Remarks (optional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(
                          ctx,
                          _SettlementResult(
                            amount: amount,
                            paymentMode: mode,
                            reference: refCtrl.text.trim().isEmpty
                                ? null
                                : refCtrl.text.trim(),
                            remarks: remarksCtrl.text.trim().isEmpty
                                ? null
                                : remarksCtrl.text.trim(),
                          ),
                        )
                    : null,
                child: const Text('Settle'),
              ),
            ],
          );
        },
      );
    },
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  Small presentational widgets
// ════════════════════════════════════════════════════════════════════════════

class _ViolationBanner extends StatelessWidget {
  const _ViolationBanner({this.details});
  final String? details;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_gmailerrorred_rounded,
              color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Policy violation',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5)),
                if (details != null && details!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(details!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                    height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final TravelClaimExpense expense;

  @override
  Widget build(BuildContext context) {
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
                  TravelEnums.label(expense.category),
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink),
                ),
              ),
              Text(
                travelMoney(expense.amount),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink),
              ),
            ],
          ),
          if (expense.description != null &&
              expense.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(expense.description!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.inkSoft, height: 1.3)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (expense.expenseDate != null)
                StatusPill(
                    label: travelDate(expense.expenseDate),
                    color: AppColors.muted),
              if (expense.approvedAmount != null)
                StatusPill(
                    label: 'Approved ${travelMoney(expense.approvedAmount)}',
                    color: AppColors.success),
              if (expense.exceedsLimit)
                StatusPill(
                    label: expense.limitAmount != null
                        ? 'Over limit ${travelMoney(expense.limitAmount)}'
                        : 'Over limit',
                    color: AppColors.danger,
                    icon: Icons.trending_up_rounded),
              if (expense.billRequired)
                StatusPill(
                  label: expense.hasBill ? 'Bill attached' : 'Bill missing',
                  color: expense.hasBill
                      ? AppColors.success
                      : AppColors.warning,
                  icon: expense.hasBill
                      ? Icons.attach_file_rounded
                      : Icons.warning_amber_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvaluationSection extends ConsumerWidget {
  const _EvaluationSection({required this.claimId});
  final int claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(travelClaimEvaluationProvider(claimId));
    final eval = async.asData?.value;
    if (eval == null || eval.categories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'Policy limits'),
        const SizedBox(height: 8),
        GlassCard(
          shadow: AppShadows.soft,
          child: Column(
            children: [
              for (final c in eval.categories)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(TravelEnums.label(c.category),
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSoft)),
                      ),
                      Text(
                        '${travelMoney(c.claimed)} / ${c.limit == null ? '—' : travelMoney(c.limit)}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c.exceeds
                                ? AppColors.danger
                                : AppColors.ink),
                      ),
                      if (c.billMissing) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.warning_amber_rounded,
                            size: 14, color: AppColors.warning),
                      ],
                    ],
                  ),
                ),
              if (eval.maxClaimAmount != null) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Total vs cap',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                    ),
                    Text(
                      '${travelMoney(eval.totalClaimed)} / ${travelMoney(eval.maxClaimAmount)}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: eval.hasViolation
                              ? AppColors.danger
                              : AppColors.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.step, required this.isLast});
  final TravelClaimApprovalStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tone = travelStepTone(step.status);
    final active = step.current && step.status == 'PENDING';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail + node
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: tone.color.withOpacity(0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: tone.color, width: active ? 2 : 1.2),
                ),
                alignment: Alignment.center,
                child: Icon(_stepIcon(step.status), size: 12, color: tone.color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.hairline,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Level ${step.levelOrder ?? '?'} · ${step.approverName ?? 'Approver'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: active ? AppColors.primary : AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(label: tone.label, color: tone.color),
                    ],
                  ),
                  if (step.actionAt != null) ...[
                    const SizedBox(height: 2),
                    Text(travelDateTime(step.actionAt),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.muted)),
                  ],
                  if (step.remarks != null && step.remarks!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('“${step.remarks!}”',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                            fontStyle: FontStyle.italic,
                            height: 1.3)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _stepIcon(String status) {
    switch (status) {
      case 'APPROVED':
        return Icons.check_rounded;
      case 'REJECTED':
        return Icons.close_rounded;
      case 'SENT_BACK':
        return Icons.reply_rounded;
      case 'PENDING':
        return Icons.hourglass_top_rounded;
      case 'SKIPPED':
        return Icons.remove_rounded;
      default:
        return Icons.circle_outlined;
    }
  }
}

class _AttachmentRow extends ConsumerStatefulWidget {
  const _AttachmentRow({required this.claimId, required this.attachment});
  final int claimId;
  final TravelAttachment attachment;

  @override
  ConsumerState<_AttachmentRow> createState() => _AttachmentRowState();
}

class _AttachmentRowState extends ConsumerState<_AttachmentRow> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(travelRepositoryProvider)
          .downloadClaimAttachment(widget.claimId, widget.attachment.id);
      final name = widget.attachment.fileName ??
          'bill_${widget.attachment.id}';
      final saved = await DownloadSaver.savePdf(name, bytes);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Saved to ${saved.locationLabel}'),
          action: saved.canOpen
              ? SnackBarAction(label: 'OPEN', onPressed: saved.open)
              : null,
        ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          const Icon(Icons.description_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.fileName ?? 'Attachment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.ink)),
                if (a.caption != null && a.caption!.isNotEmpty)
                  Text(a.caption!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _download,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded,
                    color: AppColors.primary, size: 20),
            tooltip: 'Download',
          ),
        ],
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({required this.s});
  final TravelSettlement s;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      shadow: AppShadows.soft,
      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_rounded, color: AppColors.primary, size: 18),
              SizedBox(width: 6),
              Text('Settlement',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          _MetaRow(label: 'Settled amount', value: travelMoney(s.settledAmount)),
          if (s.paymentMode != null)
            _MetaRow(
                label: 'Payment mode',
                value: TravelEnums.label(s.paymentMode)),
          if (s.paymentReference != null && s.paymentReference!.isNotEmpty)
            _MetaRow(label: 'Reference', value: s.paymentReference!),
          if (s.settledBy != null)
            _MetaRow(label: 'Settled by', value: s.settledBy!),
          if (s.settledAt != null)
            _MetaRow(label: 'Settled on', value: travelDateTime(s.settledAt)),
          if (s.remarks != null && s.remarks!.isNotEmpty)
            _MetaRow(label: 'Remarks', value: s.remarks!),
        ],
      ),
    );
  }
}
