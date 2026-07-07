import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'travel_attachments.dart';
import 'travel_models.dart';
import 'travel_repository.dart';
import 'travel_status_ui.dart';

final travelClaimProvider =
    FutureProvider.autoDispose.family<TravelClaim, int>((ref, id) {
  return ref.watch(travelRepositoryProvider).getClaim(id);
});

/// Limit-vs-claimed evaluation (policy-warning display). Optional — some claims
/// have no resolvable policy, so failures are surfaced softly, not as an error.
final travelClaimEvalProvider =
    FutureProvider.autoDispose.family<TravelPolicyEvaluation?, int>((ref, id) async {
  try {
    return await ref.watch(travelRepositoryProvider).evaluation(id);
  } catch (_) {
    return null;
  }
});

class TravelClaimDetailScreen extends ConsumerWidget {
  const TravelClaimDetailScreen({super.key, required this.claimId});
  final int claimId;

  String _fmt(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

  void _refresh(WidgetRef ref) {
    ref.invalidate(travelClaimProvider(claimId));
    ref.invalidate(travelClaimEvalProvider(claimId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(travelClaimProvider(claimId));
    final user = ref.watch(authUserProvider);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Travel Claim'),
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
              onRetry: () => _refresh(ref),
            ),
          ),
          data: (claim) {
            final isOwner =
                user?.employeeId != null && claim.employeeId == user!.employeeId;
            final canEdit = isOwner && claimIsEditable(claim.status);
            final tone = claimStatusTone(claim.status);

            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: Colors.white.withOpacity(0.92),
              onRefresh: () async => _refresh(ref),
              child: ListView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── Header ──
                  GlassCard(
                    shadow: AppShadows.soft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(claim.title,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink)),
                            ),
                            const SizedBox(width: 8),
                            StatusPill(label: tone.label, color: tone.color),
                          ],
                        ),
                        if (claim.claimCode != null && claim.claimCode!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(claim.claimCode!,
                              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                        const SizedBox(height: 12),
                        _kv('Dates', '${_fmt(claim.fromDate)} → ${_fmt(claim.toDate)}'),
                        if (claim.purpose != null && claim.purpose!.isNotEmpty)
                          _kv('Purpose', claim.purpose!),
                        if (claim.policyNameSnapshot != null)
                          _kv('Policy', claim.policyNameSnapshot!),
                        _kv('Claimed', money(claim.totalClaimedAmount)),
                        if (claim.totalApprovedAmount != null)
                          _kv('Approved', money(claim.totalApprovedAmount)),
                        if (claim.approvalLevels != null && claim.approvalLevels! > 0)
                          _kv('Approval levels', '${claim.approvalLevels}'),
                      ],
                    ),
                  ),

                  // ── Policy violation banner ──
                  if (claim.hasPolicyViolation) ...[
                    const SizedBox(height: 12),
                    GlassCard(
                      color: AppColors.danger.withOpacity(0.07),
                      shadow: AppShadows.soft,
                      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.danger, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Policy violation',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.danger,
                                        fontSize: 13)),
                                if (claim.violationDetails != null &&
                                    claim.violationDetails!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(claim.violationDetails!,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.inkSoft,
                                          height: 1.4)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Sent-back notice ──
                  if (claim.status == 'SENT_BACK') ...[
                    const SizedBox(height: 12),
                    _noticeCard(
                      icon: Icons.undo_rounded,
                      color: AppColors.pink,
                      title: 'Sent back for changes',
                      body: _lastRemark(claim) ??
                          'An approver sent this claim back. Update it and submit again.',
                    ),
                  ],
                  if (claim.status == 'REJECTED') ...[
                    const SizedBox(height: 12),
                    _noticeCard(
                      icon: Icons.cancel_rounded,
                      color: AppColors.danger,
                      title: 'Rejected',
                      body: _lastRemark(claim) ?? 'This claim was rejected.',
                    ),
                  ],

                  // ── Policy evaluation (limits vs claimed) ──
                  const SizedBox(height: 18),
                  _EvaluationSection(claimId: claimId),

                  // ── Expenses ──
                  const SizedBox(height: 18),
                  AppSectionHeader(
                    title: 'Expenses',
                    subtitle: '${claim.expenses.length} line(s)',
                    trailing: canEdit
                        ? _SmallAction(
                            icon: Icons.add_rounded,
                            label: 'Add',
                            onTap: () => _addExpense(context, ref, claim.id),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  if (claim.expenses.isEmpty)
                    const AppEmptyState(
                      icon: Icons.receipt_long_rounded,
                      message: 'No expense lines yet.',
                    )
                  else
                    for (final ex in claim.expenses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ExpenseTile(
                          claimId: claim.id,
                          expense: ex,
                          canEdit: canEdit,
                          onEdit: () => _editExpense(context, ref, claim.id, ex),
                          onDelete: () => _deleteExpense(context, ref, claim.id, ex),
                          onAddBill: () => _uploadBills(
                            context,
                            ref,
                            claim.id,
                            expenseId: ex.id,
                          ),
                        ),
                      ),

                  // ── Claim-level attachments ──
                  const SizedBox(height: 18),
                  AppSectionHeader(
                    title: 'Claim bills',
                    subtitle: '${claim.attachments.length} file(s)',
                    trailing: canEdit
                        ? _SmallAction(
                            icon: Icons.upload_file_rounded,
                            label: 'Upload',
                            onTap: () => _uploadBills(context, ref, claim.id),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  if (claim.attachments.isEmpty)
                    const Text('No claim-level bills attached.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5))
                  else
                    for (final att in claim.attachments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AttachmentTile(att: att),
                      ),

                  // ── Approval timeline ──
                  if (claim.approvalSteps.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const AppSectionHeader(title: 'Approval chain'),
                    const SizedBox(height: 10),
                    GlassCard(
                      shadow: AppShadows.soft,
                      child: Column(
                        children: [
                          for (int i = 0; i < claim.approvalSteps.length; i++) ...[
                            if (i > 0)
                              const Divider(height: 16, color: AppColors.hairline),
                            _ApprovalRow(step: claim.approvalSteps[i]),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // ── Settlement ──
                  if (claim.settlement != null) ...[
                    const SizedBox(height: 18),
                    const AppSectionHeader(title: 'Settlement'),
                    const SizedBox(height: 10),
                    GlassCard(
                      color: AppColors.success.withOpacity(0.06),
                      shadow: AppShadows.soft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('Settled amount', money(claim.settlement!.settledAmount)),
                          if (claim.settlement!.paymentMode != null)
                            _kv('Mode', TravelEnums.label(claim.settlement!.paymentMode)),
                          if (claim.settlement!.paymentReference != null &&
                              claim.settlement!.paymentReference!.isNotEmpty)
                            _kv('Reference', claim.settlement!.paymentReference!),
                          if (claim.settlement!.settledAt != null)
                            _kv('Settled on', _fmt(claim.settlement!.settledAt)),
                        ],
                      ),
                    ),
                  ],

                  // ── Owner actions ──
                  if (canEdit) ...[
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await context.push<bool>(
                                '/travel/claims/edit',
                                extra: claim,
                              );
                              if (ok == true) _refresh(ref);
                            },
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('Edit'),
                          ),
                        ),
                        if (claim.status == 'DRAFT') ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _deleteClaim(context, ref, claim.id),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: BorderSide(color: AppColors.danger.withOpacity(0.4)),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text('Delete'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: claim.expenses.isEmpty
                            ? null
                            : () => _submit(context, ref, claim),
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(claim.status == 'SENT_BACK'
                            ? 'Resubmit for approval'
                            : 'Submit for approval'),
                      ),
                    ),
                    if (claim.expenses.isEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Add at least one expense before submitting.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ],
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String? _lastRemark(TravelClaim claim) {
    for (final s in claim.approvalSteps.reversed) {
      if (s.remarks != null && s.remarks!.isNotEmpty) return s.remarks;
    }
    return claim.submissionRemarks;
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(k,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _noticeCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) =>
      GlassCard(
        color: color.withOpacity(0.07),
        shadow: AppShadows.soft,
        border: Border.all(color: color.withOpacity(0.3)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: color, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.inkSoft, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _addExpense(BuildContext context, WidgetRef ref, int claimId) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseSheet(claimId: claimId),
    );
    if (saved == true) _refresh(ref);
  }

  Future<void> _editExpense(
      BuildContext context, WidgetRef ref, int claimId, TravelClaimExpense ex) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseSheet(claimId: claimId, expense: ex),
    );
    if (saved == true) _refresh(ref);
  }

  Future<void> _deleteExpense(
      BuildContext context, WidgetRef ref, int claimId, TravelClaimExpense ex) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
            'Remove the ${TravelEnums.label(ex.category)} line of ${money(ex.amount)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(travelRepositoryProvider).deleteExpense(claimId, ex.id);
      _refresh(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _uploadBills(BuildContext context, WidgetRef ref, int claimId,
      {int? expenseId}) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadBillsSheet(claimId: claimId, expenseId: expenseId),
    );
    if (done == true) _refresh(ref);
  }

  Future<void> _deleteClaim(BuildContext context, WidgetRef ref, int claimId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete claim?'),
        content: const Text('This draft claim will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(travelRepositoryProvider).deleteClaim(claimId);
      if (context.mounted) router.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _submit(BuildContext context, WidgetRef ref, TravelClaim claim) async {
    final eval = ref.read(travelClaimEvalProvider(claim.id)).asData?.value;
    final needsRemark =
        claim.hasPolicyViolation || (eval?.hasViolation ?? false);
    final ctrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(claim.status == 'SENT_BACK' ? 'Resubmit claim' : 'Submit claim'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needsRemark)
              const Text(
                'This claim has a policy violation. A justification remark is required.',
                style: TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.4),
              )
            else
              const Text('Submit this claim for approval?',
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              decoration: InputDecoration(
                hintText: needsRemark ? 'Justification (required)' : 'Remarks (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final remarks = ctrl.text.trim();
    if (needsRemark && remarks.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('A justification remark is required.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(travelRepositoryProvider).submit(claim.id, remarks: remarks);
      _refresh(ref);
      messenger.showSnackBar(const SnackBar(content: Text('Claim submitted ✓')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

// ── Evaluation section ───────────────────────────────────────────────────────

class _EvaluationSection extends ConsumerWidget {
  const _EvaluationSection({required this.claimId});
  final int claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(travelClaimEvalProvider(claimId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (eval) {
        if (eval == null || eval.policyId == null) return const SizedBox.shrink();
        final tone = eval.hasViolation ? AppColors.danger : AppColors.success;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              title: 'Policy check',
              subtitle: eval.policyName ?? 'Limit vs claimed',
            ),
            const SizedBox(height: 10),
            GlassCard(
              shadow: AppShadows.soft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          eval.hasViolation
                              ? Icons.error_outline_rounded
                              : Icons.verified_rounded,
                          color: tone,
                          size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          eval.hasViolation
                              ? 'Some limits are exceeded'
                              : 'Within policy limits',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: tone, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  if (eval.maxClaimAmount != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Total ${money(eval.totalClaimed)} of cap ${money(eval.maxClaimAmount)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                    ),
                  ],
                  if (eval.categories.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final c in eval.categories.where(
                        (c) => (c.claimed ?? 0) > 0 || c.exceeds || c.billMissing))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(expenseCategoryIcon(c.category),
                                size: 15,
                                color: c.exceeds ? AppColors.danger : AppColors.muted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(TravelEnums.label(c.category),
                                  style: const TextStyle(
                                      fontSize: 12.5, color: AppColors.ink)),
                            ),
                            Text(
                              c.limit == null
                                  ? money(c.claimed)
                                  : '${money(c.claimed)} / ${money(c.limit)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.exceeds ? AppColors.danger : AppColors.inkSoft,
                              ),
                            ),
                            if (c.billMissing) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.receipt_long_rounded,
                                  size: 14, color: AppColors.warning),
                            ],
                          ],
                        ),
                      ),
                  ],
                  if (eval.blockOnViolation && eval.hasViolation) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'This policy blocks submission until violations are resolved or justified.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.danger, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Expense tile ─────────────────────────────────────────────────────────────

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.claimId,
    required this.expense,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
    required this.onAddBill,
  });
  final int claimId;
  final TravelClaimExpense expense;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddBill;

  @override
  Widget build(BuildContext context) {
    final ex = expense;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      border: ex.exceedsLimit
          ? Border.all(color: AppColors.danger.withOpacity(0.4))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(expenseCategoryIcon(ex.category),
                    size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(TravelEnums.label(ex.category),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    if (ex.expenseDate != null)
                      Text(DateFormat('d MMM yyyy').format(ex.expenseDate!),
                          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
              Text(money(ex.amount),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ],
          ),
          if (ex.description != null && ex.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(ex.description!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
          ],
          if (ex.exceedsLimit || (ex.billRequired && !ex.hasBill) || ex.hasBill) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (ex.exceedsLimit)
                  StatusPill(
                    label: ex.limitAmount != null
                        ? 'Over limit ${money(ex.limitAmount)}'
                        : 'Over limit',
                    color: AppColors.danger,
                    icon: Icons.trending_up_rounded,
                  ),
                if (ex.billRequired && !ex.hasBill)
                  const StatusPill(
                    label: 'Bill required',
                    color: AppColors.warning,
                    icon: Icons.receipt_long_rounded,
                  ),
                if (ex.hasBill)
                  const StatusPill(
                    label: 'Bill attached',
                    color: AppColors.success,
                    icon: Icons.check_rounded,
                  ),
              ],
            ),
          ],
          if (canEdit) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onAddBill,
                  icon: const Icon(Icons.attach_file_rounded, size: 16),
                  label: const Text('Bill'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.danger),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.att});
  final TravelAttachment att;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: InkWell(
        onTap: () async {
          final url = Env.fileUrl(att.downloadUrl);
          if (url == null) return;
          final ok =
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open bill')),
            );
          }
        },
        child: Row(
          children: [
            const Icon(Icons.description_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(att.fileName ?? 'Bill',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
            ),
            const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({required this.step});
  final TravelClaimApprovalStep step;

  Color get _color {
    switch (step.status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      case 'SENT_BACK':
        return AppColors.pink;
      case 'PENDING':
        return AppColors.warning;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _color.withOpacity(0.14),
            shape: BoxShape.circle,
            border: Border.all(color: _color.withOpacity(0.4)),
          ),
          alignment: Alignment.center,
          child: Text('${step.levelOrder ?? '?'}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _color)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(step.approverName ?? 'Approver',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                  ),
                  StatusPill(label: TravelEnums.label(step.status), color: _color),
                ],
              ),
              if (step.remarks != null && step.remarks!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(step.remarks!,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkSoft, fontStyle: FontStyle.italic)),
              ],
              if (step.actionAt != null) ...[
                const SizedBox(height: 2),
                Text(DateFormat('d MMM yyyy, h:mm a').format(step.actionAt!),
                    style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

// ── Expense add/edit sheet ───────────────────────────────────────────────────

class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet({required this.claimId, this.expense});
  final int claimId;
  final TravelClaimExpense? expense;

  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  late String _category;
  late final TextEditingController _amount;
  late final TextEditingController _desc;
  DateTime? _date;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.expense;
    _category = ex?.category ?? TravelEnums.expenseCategories.first;
    _amount = TextEditingController(
        text: ex?.amount == null ? '' : ex!.amount!.toStringAsFixed(2));
    _desc = TextEditingController(text: ex?.description ?? '');
    _date = ex?.expenseDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(travelRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateExpense(
          widget.claimId,
          widget.expense!.id,
          category: _category,
          amount: amount,
          expenseDate: _date,
          description: _desc.text.trim(),
        );
      } else {
        await repo.addExpense(
          widget.claimId,
          category: _category,
          amount: amount,
          expenseDate: _date,
          description: _desc.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            20,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.xl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEdit ? 'Edit expense' : 'Add expense',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.category_outlined, size: 20)),
              items: [
                for (final c in TravelEnums.expenseCategories)
                  DropdownMenuItem(value: c, child: Text(TravelEnums.label(c))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Amount'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(2015),
                  lastDate: DateTime(2035),
                );
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration:
                    const InputDecoration(prefixIcon: Icon(Icons.event_rounded, size: 20)),
                child: Text(_date == null ? 'Expense date' : df.format(_date!),
                    style: TextStyle(
                        color: _date == null ? AppColors.muted : AppColors.ink)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              decoration: const InputDecoration(hintText: 'Description (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AppErrorPanel(message: _error!),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save' : 'Add expense')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Upload bills sheet ───────────────────────────────────────────────────────

class _UploadBillsSheet extends ConsumerStatefulWidget {
  const _UploadBillsSheet({required this.claimId, this.expenseId});
  final int claimId;
  final int? expenseId;

  @override
  ConsumerState<_UploadBillsSheet> createState() => _UploadBillsSheetState();
}

class _UploadBillsSheetState extends ConsumerState<_UploadBillsSheet> {
  final List<TravelUploadFile> _files = [];
  bool _uploading = false;
  double _progress = 0;
  String? _error;

  Future<void> _upload() async {
    if (_files.isEmpty) {
      setState(() => _error = 'Add at least one file.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
      _progress = 0;
    });
    final repo = ref.read(travelRepositoryProvider);
    try {
      if (widget.expenseId != null) {
        await repo.uploadExpenseAttachments(
          widget.claimId,
          widget.expenseId!,
          _files,
          onProgress: (s, t) {
            if (mounted && t > 0) setState(() => _progress = s / t);
          },
        );
      } else {
        await repo.uploadClaimAttachments(
          widget.claimId,
          _files,
          onProgress: (s, t) {
            if (mounted && t > 0) setState(() => _progress = s / t);
          },
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            20,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.xl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.expenseId != null ? 'Upload expense bill' : 'Upload claim bill',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 16),
            TravelFilePicker(
              files: _files,
              onChanged: () => setState(() {}),
              title: 'Files',
              subtitle: 'Photos of receipts or a PDF',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AppErrorPanel(message: _error!),
            ],
            const SizedBox(height: 16),
            if (_uploading && _progress > 0 && _progress < 1) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _uploading ? null : _upload,
                child: Text(_uploading ? 'Uploading…' : 'Upload'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
