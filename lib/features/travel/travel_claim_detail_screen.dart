import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
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

/// Rounded rupee amount for the KPI strip ("₹ 14,600").
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

class TravelClaimDetailScreen extends ConsumerWidget {
  const TravelClaimDetailScreen({super.key, required this.claimId});
  final int claimId;

  String _fmt(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

  void _refresh(WidgetRef ref) {
    ref.invalidate(travelClaimProvider(claimId));
    ref.invalidate(travelClaimEvalProvider(claimId));
  }

  /// Approval-step tone used in this screen's timeline (unchanged wording).
  static StatusTone _stepTone(String status) {
    switch (status) {
      case 'APPROVED':
        return StatusTone(AppColors.success, TravelEnums.label(status));
      case 'REJECTED':
        return StatusTone(AppColors.danger, TravelEnums.label(status));
      case 'SENT_BACK':
        return StatusTone(AppColors.pink, TravelEnums.label(status));
      case 'PENDING':
        return StatusTone(AppColors.warning, TravelEnums.label(status));
      default:
        return StatusTone(AppColors.muted, TravelEnums.label(status));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(travelClaimProvider(claimId));
    final user = ref.watch(authUserProvider);

    bool ownerOf(TravelClaim c) =>
        user?.employeeId != null && c.employeeId == user!.employeeId;

    return Scaffold(
      appBar: AppBar(title: const Text('Travel claim')),
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
          final isOwner = ownerOf(claim);
          final canEdit = isOwner && claimIsEditable(claim.status);
          final tone = claimStatusTone(claim.status);

          final missingBills =
              claim.expenses.where((e) => e.billRequired && !e.hasBill).length;
          final stepTotal = claim.approvalSteps.isNotEmpty
              ? claim.approvalSteps.length
              : (claim.approvalLevels ?? 0);
          final stepsApproved =
              claim.approvalSteps.where((s) => s.status == 'APPROVED').length;
          final dates = claim.fromDate == null && claim.toDate == null
              ? null
              : '${_fmt(claim.fromDate)} → ${_fmt(claim.toDate)}';

          return ProPage(
            onRefresh: () async => _refresh(ref),
            hero: ProHero(
              overlap: ProKpiStrip(cells: [
                ProKpi(
                  value: _inr0.format(claim.totalClaimedAmount ?? 0),
                  label: claim.totalApprovedAmount != null
                      ? 'Claimed · ${_inr0.format(claim.totalApprovedAmount)} approved'
                      : 'Claimed',
                ),
                ProKpi(
                  value: '$missingBills',
                  label: 'Bills missing',
                  valueColor: missingBills > 0 ? AppColors.warning : null,
                ),
                ProKpi(
                  value: '$stepsApproved / $stepTotal',
                  label: 'Levels approved',
                  progress: stepTotal > 0 ? stepsApproved / stepTotal : null,
                  color: AppColors.success,
                ),
              ]),
              children: [
                ProHeroIdentity(
                  name: claim.title,
                  role: (claim.claimCode == null || claim.claimCode!.isEmpty) && dates == null
                      ? null
                      : [
                          if (claim.claimCode != null && claim.claimCode!.isNotEmpty)
                            claim.claimCode!,
                          if (dates != null) dates,
                        ].join(' · '),
                  icon: Icons.receipt_long_rounded,
                  tags: [
                    ProHeroTag(tone.label, tone: claimTagTone(claim.status)),
                    if (claim.hasPolicyViolation)
                      const ProHeroTag('Policy flag',
                          tone: ProTagTone.bad, icon: Icons.warning_amber_rounded),
                    if (claim.approvalLevels != null && claim.approvalLevels! > 0)
                      ProHeroTag(
                          '${claim.approvalLevels} approval level${claim.approvalLevels == 1 ? '' : 's'}'),
                  ],
                ),
                ProLiveLine(
                  text: claimLiveText(claim),
                  color: claimLiveColor(claim.status),
                ),
                if (canEdit)
                  ProHeroActions(actions: [
                    ProAction(
                      icon: Icons.add_rounded,
                      label: 'Add expense',
                      primary: true,
                      onTap: () => _addExpense(context, ref, claim.id),
                    ),
                    ProAction(
                      icon: Icons.upload_file_rounded,
                      label: 'Upload bill',
                      onTap: () => _uploadBills(context, ref, claim.id),
                    ),
                    ProAction(
                      icon: Icons.edit_rounded,
                      label: 'Edit claim',
                      onTap: () async {
                        final ok = await context.push<bool>(
                          '/travel/claims/edit',
                          extra: claim,
                        );
                        if (ok == true) _refresh(ref);
                      },
                    ),
                  ]),
              ],
            ),
            children: [
              // ── Policy violation banner ──
              if (claim.hasPolicyViolation)
                TravelNotice(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  background: AppColors.dangerTint,
                  title: 'Policy violation',
                  body: claim.violationDetails,
                ),

              // ── Sent-back / rejected notices ──
              if (claim.status == 'SENT_BACK')
                TravelNotice(
                  icon: Icons.undo_rounded,
                  color: const Color(0xFF8A5200),
                  background: AppColors.warningTint,
                  title: 'Sent back for changes',
                  body: _lastRemark(claim) ??
                      'An approver sent this claim back. Update it and submit again.',
                ),
              if (claim.status == 'REJECTED')
                TravelNotice(
                  icon: Icons.cancel_rounded,
                  color: AppColors.danger,
                  background: AppColors.dangerTint,
                  title: 'Rejected',
                  body: _lastRemark(claim) ?? 'This claim was rejected.',
                ),

              // ── Trip details ──
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Trip details'),
                    const SizedBox(height: 4),
                    ProKeyValue(rows: [
                      MapEntry('Dates', '${_fmt(claim.fromDate)} → ${_fmt(claim.toDate)}'),
                      if (claim.purpose != null && claim.purpose!.isNotEmpty)
                        MapEntry('Purpose', claim.purpose!),
                      if (claim.policyNameSnapshot != null)
                        MapEntry('Policy', claim.policyNameSnapshot!),
                      MapEntry('Claimed', money(claim.totalClaimedAmount)),
                      if (claim.totalApprovedAmount != null)
                        MapEntry('Approved', money(claim.totalApprovedAmount)),
                      if (claim.approvalLevels != null && claim.approvalLevels! > 0)
                        MapEntry('Approval levels', '${claim.approvalLevels}'),
                    ]),
                  ],
                ),
              ),

              // ── Policy evaluation (limits vs claimed) ──
              _EvaluationSection(claimId: claimId),

              // ── Expenses ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title: 'Expenses',
                    subtitle:
                        '${claim.expenses.length} line(s) · ${money(claim.totalClaimedAmount)}',
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
                    const ProEmpty(
                      icon: Icons.receipt_long_rounded,
                      title: 'No expense lines yet.',
                      message: 'Add at least one expense before submitting.',
                    )
                  else
                    ProListGroup(
                      dividerIndent: 58,
                      children: [
                        for (final ex in claim.expenses)
                          _ExpenseTile(
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
                      ],
                    ),
                ],
              ),

              // ── Claim-level attachments ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
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
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Text('No claim-level bills attached.', style: AppText.caption),
                    )
                  else
                    ProListGroup(
                      children: [
                        for (final att in claim.attachments) _AttachmentTile(att: att),
                      ],
                    ),
                ],
              ),

              // ── Approval timeline ──
              if (claim.approvalSteps.isNotEmpty)
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProSectionHeader(
                        title: 'Approval chain',
                        trailing: Text(
                          '$stepsApproved of ${claim.approvalSteps.length} approved',
                          style: AppText.caption,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TravelApprovalTimeline(
                        steps: claim.approvalSteps,
                        toneOf: _stepTone,
                      ),
                    ],
                  ),
                ),

              // ── Settlement ──
              if (claim.settlement != null)
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProSectionHeader(
                        title: 'Settlement',
                        trailing: ProPill.ok('Settled'),
                      ),
                      const SizedBox(height: 4),
                      ProKeyValue(rows: [
                        MapEntry('Settled amount', money(claim.settlement!.settledAmount)),
                        if (claim.settlement!.paymentMode != null)
                          MapEntry('Mode', TravelEnums.label(claim.settlement!.paymentMode)),
                        if (claim.settlement!.paymentReference != null &&
                            claim.settlement!.paymentReference!.isNotEmpty)
                          MapEntry('Reference', claim.settlement!.paymentReference!),
                        if (claim.settlement!.settledAt != null)
                          MapEntry('Settled on', _fmt(claim.settlement!.settledAt)),
                      ]),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (claim) {
          final isOwner = ownerOf(claim);
          final canEdit = isOwner && claimIsEditable(claim.status);
          final canDelete = isOwner && claimIsDeletable(claim.status);

          // ── Owner actions ──
          if (canEdit) {
            return ProBottomBar(
              top: claim.expenses.isEmpty
                  ? const Text(
                      'Add at least one expense before submitting.',
                      textAlign: TextAlign.center,
                      style: AppText.caption,
                    )
                  : null,
              children: [
                if (canDelete)
                  FilledButton.icon(
                    onPressed: () => _deleteClaim(context, ref, claim),
                    style: travelDangerFilled,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                FilledButton.icon(
                  onPressed:
                      claim.expenses.isEmpty ? null : () => _submit(context, ref, claim),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    claim.status == 'SENT_BACK' ? 'Resubmit for approval' : 'Submit for approval',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          }
          if (canDelete) {
            // Awaiting approval: nothing here is editable any more, but the
            // claimant can still withdraw a claim nobody has acted on.
            return ProBottomBar(children: [
              FilledButton.icon(
                onPressed: () => _deleteClaim(context, ref, claim),
                style: travelDangerFilled,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete claim'),
              ),
            ]);
          }
          return null;
        },
        orElse: () => null,
      ),
    );
  }

  String? _lastRemark(TravelClaim claim) {
    for (final s in claim.approvalSteps.reversed) {
      if (s.remarks != null && s.remarks!.isNotEmpty) return s.remarks;
    }
    return claim.submissionRemarks;
  }

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
            style: travelDangerFilled,
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

  Future<void> _deleteClaim(BuildContext context, WidgetRef ref, TravelClaim claim) async {
    final claimId = claim.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete claim?'),
        content: Text(claim.status == 'SUBMITTED'
            ? 'This claim will be withdrawn from the approver and permanently deleted.'
            : 'This draft claim will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: travelDangerFilled,
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
                style: TextStyle(fontSize: 13, color: AppColors.danger, height: 1.4),
              )
            else
              const Text('Submit this claim for approval?',
                  style: TextStyle(fontSize: 14, color: AppColors.inkSoft)),
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
        final rows = eval.categories
            .where((c) => (c.claimed ?? 0) > 0 || c.exceeds || c.billMissing)
            .toList();
        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: 'Policy check',
                subtitle: eval.maxClaimAmount != null
                    ? '${eval.policyName ?? 'Limit vs claimed'} · total ${money(eval.totalClaimed)} of cap ${money(eval.maxClaimAmount)}'
                    : (eval.policyName ?? 'Limit vs claimed'),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: eval.hasViolation ? AppColors.dangerTint : AppColors.successTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
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
                            fontWeight: FontWeight.w600, color: tone, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
              for (final c in rows) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(expenseCategoryIcon(c.category),
                        size: 16,
                        color: c.exceeds ? AppColors.danger : AppColors.muted),
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
                      c.limit == null
                          ? money(c.claimed)
                          : '${money(c.claimed)} / ${money(c.limit)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.exceeds ? AppColors.danger : AppColors.inkSoft,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
              if (eval.blockOnViolation && eval.hasViolation) ...[
                const SizedBox(height: 12),
                const Text(
                  'This policy blocks submission until violations are resolved or justified.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.4),
                ),
              ],
            ],
          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProIconWell(
                icon: expenseCategoryIcon(ex.category),
                color: ex.exceedsLimit ? AppColors.danger : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(TravelEnums.label(ex.category),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.15,
                            color: AppColors.ink)),
                    if (ex.expenseDate != null)
                      Text(DateFormat('d MMM yyyy').format(ex.expenseDate!),
                          style: AppText.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(money(ex.amount),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          if (ex.description != null && ex.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Text(ex.description!,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.4, color: AppColors.inkSoft)),
            ),
          ],
          if (ex.exceedsLimit || (ex.billRequired && !ex.hasBill) || ex.hasBill) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (ex.exceedsLimit)
                    ProPill.bad(ex.limitAmount != null
                        ? 'Over limit ${money(ex.limitAmount)}'
                        : 'Over limit'),
                  if (ex.billRequired && !ex.hasBill) ProPill.warn('Bill required'),
                  if (ex.hasBill) ProPill.ok('Bill attached'),
                ],
              ),
            ),
          ],
          if (canEdit) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: onAddBill,
                    icon: const Icon(Icons.attach_file_rounded, size: 16),
                    label: const Text('Bill'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 19, color: AppColors.danger),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Delete',
                  ),
                ],
              ),
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
    return ProListRow(
      leading: ProIconWell(icon: Icons.description_rounded, color: AppColors.primary),
      title: att.fileName ?? 'Bill',
      chevron: false,
      trailing: const Icon(Icons.open_in_new_rounded, size: 17, color: AppColors.muted),
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
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
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
    return TravelSheet(
      title: _isEdit ? 'Edit expense' : 'Add expense',
      children: [
        // DB-driven categories (/api/lookups/travel-expense-categories) —
        // the backend enum was removed, so companies can define their own.
        // The provider itself falls back to the legacy built-in list.
        ProField(
          label: 'Category',
          child: Builder(builder: (context) {
            final serverCats =
                ref.watch(travelExpenseCategoriesProvider).maybeWhen(
                      data: (list) => list,
                      orElse: () => const <TravelCategoryOption>[],
                    );
            final options = serverCats.isNotEmpty
                ? [...serverCats] // copy — never mutate the provider cache
                : [
                    for (final c in TravelEnums.expenseCategories)
                      TravelCategoryOption(
                          code: c, label: TravelEnums.label(c)),
                  ];
            // Keep an existing expense's (possibly retired) code selectable.
            final codes = options.map((o) => o.code).toSet();
            if (!codes.contains(_category)) {
              options.insert(
                  0,
                  TravelCategoryOption(
                      code: _category, label: TravelEnums.label(_category)));
            }
            return DropdownButtonFormField<String>(
              value: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.category_outlined, size: 20)),
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o.code, child: Text(o.label)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            );
          }),
        ),
        const SizedBox(height: 14),
        ProField(
          label: 'Amount',
          required: true,
          child: TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Amount'),
          ),
        ),
        const SizedBox(height: 14),
        ProField(
          label: 'Expense date',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
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
                      fontSize: 15,
                      color: _date == null ? AppColors.faint : AppColors.ink)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ProField(
          label: 'Description (optional)',
          child: TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseTextFormatter()],
            decoration: const InputDecoration(hintText: 'What was this for?'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          AppErrorPanel(message: _error!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save' : 'Add expense')),
        ),
      ],
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
    return TravelSheet(
      title: widget.expenseId != null ? 'Upload expense bill' : 'Upload claim bill',
      children: [
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
          ProBar(value: _progress),
          const SizedBox(height: 10),
        ],
        FilledButton(
          onPressed: _uploading ? null : _upload,
          child: Text(_uploading ? 'Uploading…' : 'Upload'),
        ),
      ],
    );
  }
}
