import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download_saver.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'travel_approvals_screen.dart';
import 'travel_models.dart';
import 'travel_repository.dart';
import 'travel_status_ui.dart';

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

/// Approve or reject a claim straight from the approval inbox (swipe or the
/// row buttons) — the same remarks dialogs and repository calls as the review
/// action bar, then the inbox / queue / review caches refresh.
Future<void> travelQuickDecision(
  BuildContext context,
  WidgetRef ref,
  int claimId, {
  required bool approve,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(travelRepositoryProvider);
  final remarks = await _promptRemarks(
    context,
    title: approve ? 'Approve claim' : 'Reject claim',
    hint: approve ? 'Add an optional note…' : 'Reason for rejection (required)',
    confirmLabel: approve ? 'Approve' : 'Reject',
    confirmColor: approve ? AppColors.success : AppColors.danger,
    mandatory: !approve,
  );
  if (remarks == null) return; // cancelled
  if (!approve && remarks.isEmpty) return;
  try {
    if (approve) {
      await repo.approve(claimId, remarks: remarks.isEmpty ? null : remarks);
    } else {
      await repo.reject(claimId, remarks: remarks);
    }
    ref.invalidate(travelClaimReviewProvider(claimId));
    ref.invalidate(travelClaimEvaluationProvider(claimId));
    ref.invalidate(travelInboxProvider);
    ref.invalidate(travelSettlementQueueProvider);
    messenger.showSnackBar(
        SnackBar(content: Text(approve ? 'Claim approved' : 'Claim rejected')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(backgroundColor: AppColors.danger, content: Text('Failed: $e')),
    );
  }
}

class TravelClaimReviewScreen extends ConsumerWidget {
  const TravelClaimReviewScreen({super.key, required this.claimId});
  final int claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(travelClaimReviewProvider(claimId));

    return Scaffold(
      appBar: AppBar(title: const Text('Review claim')),
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
    );
  }
}

class _ClaimBody extends ConsumerWidget {
  const _ClaimBody({required this.claim});
  final TravelClaim claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = travelClaimTone(claim.status);
    final name = claim.employeeName ?? '';
    final pending = claimPendingStep(claim);
    final days = claim.fromDate != null && claim.toDate != null
        ? claim.toDate!.difference(claim.fromDate!).inDays + 1
        : null;

    return ProPage(
      onRefresh: () async {
        ref.invalidate(travelClaimReviewProvider(claim.id));
        ref.invalidate(travelClaimEvaluationProvider(claim.id));
      },
      hero: ProHero(
        overlap: ProKpiStrip(cells: [
          ProKpi(value: travelMoney(claim.totalClaimedAmount), label: 'Claimed'),
          ProKpi(
            value: claim.totalApprovedAmount == null
                ? '—'
                : travelMoney(claim.totalApprovedAmount),
            label: 'Approved',
            valueColor: claim.totalApprovedAmount == null ? null : AppColors.success,
          ),
          ProKpi(
            value: days == null ? '—' : '$days',
            label: days == 1 ? 'Day on trip' : 'Days on trip',
          ),
        ]),
        children: [
          ProHeroIdentity(
            name: claim.title.isEmpty ? 'Travel claim' : claim.title,
            initials: name.isEmpty ? null : ProAvatar.initialsOf(name),
            icon: Icons.receipt_long_rounded,
            role: [claim.employeeName, claim.employeeCode, claim.claimCode]
                    .any((e) => e != null && e.isNotEmpty)
                ? [claim.employeeName, claim.employeeCode, claim.claimCode]
                    .where((e) => e != null && e.isNotEmpty)
                    .join(' · ')
                : null,
            tags: [
              ProHeroTag(tone.label, tone: claimTagTone(claim.status)),
              if (claim.hasPolicyViolation)
                const ProHeroTag('Policy violation',
                    tone: ProTagTone.bad, icon: Icons.report_gmailerrorred_rounded),
              if (pending?.levelOrder != null && claim.approvalLevels != null)
                ProHeroTag('Level ${pending!.levelOrder} of ${claim.approvalLevels}'),
            ],
          ),
          ProLiveLine(
            text: claimLiveText(claim),
            color: claimLiveColor(claim.status),
          ),
        ],
      ),
      children: [
        if (claim.hasPolicyViolation)
          TravelNotice(
            icon: Icons.report_gmailerrorred_rounded,
            color: AppColors.danger,
            background: AppColors.dangerTint,
            title: 'Policy violation',
            body: claim.violationDetails,
          ),

        // ── Meta ────────────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Claim details'),
              const SizedBox(height: 4),
              ProKeyValue(rows: [
                MapEntry('Travel dates',
                    '${travelDate(claim.fromDate)} – ${travelDate(claim.toDate)}'),
                if (claim.policyNameSnapshot != null)
                  MapEntry('Policy', claim.policyNameSnapshot!),
                if (claim.approvalLevels != null)
                  MapEntry('Approval levels', '${claim.approvalLevels}'),
                if (claim.submittedAt != null)
                  MapEntry('Submitted', travelDateTime(claim.submittedAt)),
                if (claim.purpose != null && claim.purpose!.trim().isNotEmpty)
                  MapEntry('Purpose', claim.purpose!),
                if (claim.submissionRemarks != null &&
                    claim.submissionRemarks!.trim().isNotEmpty)
                  MapEntry('Submission note', claim.submissionRemarks!),
              ]),
            ],
          ),
        ),

        // ── Expenses ────────────────────────────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(
              title: 'Expenses',
              subtitle: '${claim.expenses.length} line(s)',
            ),
            const SizedBox(height: 10),
            if (claim.expenses.isEmpty)
              const ProEmpty(
                icon: Icons.receipt_long_outlined,
                title: 'No expense lines on this claim.',
              )
            else
              ProListGroup(
                children: [
                  for (final e in claim.expenses) _ExpenseRow(expense: e),
                ],
              ),
          ],
        ),

        // ── Policy evaluation (limit vs claimed) ────────────────────────
        _EvaluationSection(claimId: claim.id),

        // ── Approval timeline ───────────────────────────────────────────
        if (claim.approvalSteps.isNotEmpty)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Approval timeline'),
                const SizedBox(height: 14),
                TravelApprovalTimeline(
                  steps: claim.approvalSteps,
                  toneOf: travelStepTone,
                ),
              ],
            ),
          ),

        // ── Claim-level bills ───────────────────────────────────────────
        if (claim.attachments.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: 'Bills & attachments',
                subtitle: '${claim.attachments.length} file(s)',
              ),
              const SizedBox(height: 10),
              ProListGroup(
                children: [
                  for (final a in claim.attachments)
                    _AttachmentRow(claimId: claim.id, attachment: a),
                ],
              ),
            ],
          ),

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

    if (_busy) {
      return const ProBottomBar(children: [
        SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ]);
    }
    if (canSettle) {
      return ProBottomBar(children: [
        FilledButton.icon(
          onPressed: _settle,
          icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
          label: const Text('Settle claim'),
        ),
      ]);
    }
    const tight = EdgeInsets.symmetric(horizontal: 8, vertical: 12);
    return ProBottomBar(children: [
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.dangerTint,
          foregroundColor: AppColors.danger,
          padding: tight,
        ),
        onPressed: _reject,
        child: const Text('Reject', maxLines: 1),
      ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(padding: tight),
        onPressed: _sendBack,
        child: const Text('Send back', maxLines: 1),
      ),
      FilledButton(
        style: FilledButton.styleFrom(padding: tight),
        onPressed: _approve,
        child: const Text('Approve', maxLines: 1),
      ),
    ]);
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
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(hintText: hint),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: confirmColor == AppColors.danger
                    ? travelDangerFilled
                    : FilledButton.styleFrom(backgroundColor: confirmColor),
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
            title: const Text('Settle claim'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProField(
                    label: 'Settled amount',
                    required: true,
                    child: TextField(
                      controller: amountCtrl,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setLocal(() {}),
                      decoration: const InputDecoration(prefixText: '₹ '),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ProField(
                    label: 'Payment mode',
                    child: DropdownButtonFormField<String>(
                      value: mode,
                      isExpanded: true,
                      items: [
                        for (final m in TravelEnums.paymentModes)
                          DropdownMenuItem(
                              value: m, child: Text(TravelEnums.label(m))),
                      ],
                      onChanged: (v) => setLocal(() => mode = v ?? mode),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ProField(
                    label: 'Payment reference (optional)',
                    child: TextField(
                      controller: refCtrl,
                      decoration: const InputDecoration(
                          hintText: 'UTR, cheque or UPI reference'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ProField(
                    label: 'Remarks (optional)',
                    child: TextField(
                      controller: remarksCtrl,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: const [TitleCaseTextFormatter()],
                    ),
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

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final TravelClaimExpense expense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(
                icon: expenseCategoryIcon(expense.category),
                color: expense.exceedsLimit ? AppColors.danger : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TravelEnums.label(expense.category),
                      style: const TextStyle(
                          fontSize: 15,
                          height: 1.33,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.15,
                          color: AppColors.ink),
                    ),
                    if (expense.description != null &&
                        expense.description!.trim().isNotEmpty)
                      Text(expense.description!,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.inkSoft, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                travelMoney(expense.amount),
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (expense.expenseDate != null)
                  ProPill.neutral(travelDate(expense.expenseDate)),
                if (expense.approvedAmount != null)
                  ProPill.ok('Approved ${travelMoney(expense.approvedAmount)}'),
                if (expense.exceedsLimit)
                  ProPill.bad(expense.limitAmount != null
                      ? 'Over limit ${travelMoney(expense.limitAmount)}'
                      : 'Over limit'),
                if (expense.billRequired)
                  expense.hasBill
                      ? ProPill.ok('Bill attached')
                      : ProPill.warn('Bill missing'),
              ],
            ),
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

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Policy limits'),
          const SizedBox(height: 6),
          for (final c in eval.categories) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(expenseCategoryIcon(c.category),
                    size: 16, color: c.exceeds ? AppColors.danger : AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(TravelEnums.label(c.category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink)),
                ),
                if (c.billMissing) ...[
                  ProPill.warn('Bill missing'),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${travelMoney(c.claimed)} / ${c.limit == null ? '—' : travelMoney(c.limit)}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.exceeds ? AppColors.danger : AppColors.inkSoft,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            if (c.limit != null && c.limit! > 0) ...[
              const SizedBox(height: 7),
              ProBar(
                value: (c.claimed ?? 0) / c.limit!,
                color: c.exceeds ? AppColors.danger : AppColors.primary,
                height: 4,
              ),
            ],
          ],
          if (eval.maxClaimAmount != null) ...[
            const Divider(height: 24, color: AppColors.hairlineSoft),
            Row(
              children: [
                const Expanded(
                  child: Text('Total vs cap',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                ),
                Text(
                  '${travelMoney(eval.totalClaimed)} / ${travelMoney(eval.maxClaimAmount)}',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: eval.hasViolation ? AppColors.danger : AppColors.success,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
    return ProListRow(
      leading: ProIconWell(icon: Icons.description_rounded, color: AppColors.primary),
      title: a.fileName ?? 'Attachment',
      subtitle: (a.caption != null && a.caption!.isNotEmpty) ? a.caption : null,
      chevron: false,
      trailing: IconButton(
        onPressed: _busy ? null : _download,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.download_rounded, color: AppColors.primary, size: 20),
        tooltip: 'Download',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(title: 'Settlement', trailing: ProPill.ok('Settled')),
          const SizedBox(height: 4),
          ProKeyValue(rows: [
            MapEntry('Settled amount', travelMoney(s.settledAmount)),
            if (s.paymentMode != null)
              MapEntry('Payment mode', TravelEnums.label(s.paymentMode)),
            if (s.paymentReference != null && s.paymentReference!.isNotEmpty)
              MapEntry('Reference', s.paymentReference!),
            if (s.settledBy != null) MapEntry('Settled by', s.settledBy!),
            if (s.settledAt != null) MapEntry('Settled on', travelDateTime(s.settledAt)),
            if (s.remarks != null && s.remarks!.isNotEmpty) MapEntry('Remarks', s.remarks!),
          ]),
        ],
      ),
    );
  }
}
