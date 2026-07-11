// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — plan detail + workflow.
//
//  Shows the plan header, status, scores, and the workflow actions available to
//  the signed-in user (gated by permission + current status). "Start audit" /
//  "Continue audit" opens the fill screen; a link opens this audit's findings.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/branding.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import 'audit_fill_screen.dart';
import 'audit_models.dart';
import 'audit_repository.dart';
import 'audit_widgets.dart';
import 'findings_list_screen.dart';

class AuditDetailScreen extends ConsumerStatefulWidget {
  const AuditDetailScreen({super.key, required this.planId});
  final int planId;

  @override
  ConsumerState<AuditDetailScreen> createState() => _AuditDetailScreenState();
}

class _AuditDetailScreenState extends ConsumerState<AuditDetailScreen> {
  bool _busy = false;

  static String? _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('dd MMM yyyy').format(d);
  }

  Future<void> _run(
    Future<AuditPlan> Function() action, {
    String? successMsg,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(auditPlanProvider(widget.planId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg ?? 'Done'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason(String title) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          decoration: const InputDecoration(hintText: 'Enter a reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return (reason != null && reason.isNotEmpty) ? reason : null;
  }

  void _openFill(int execId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuditFillScreen(executionId: execId),
    )).then((_) => ref.invalidate(auditPlanProvider(widget.planId)));
  }

  Future<void> _startOrContinue(AuditPlan plan) async {
    if (plan.executionId != null) {
      _openFill(plan.executionId!);
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(auditRepositoryProvider)
          .startPlan(widget.planId);
      ref.invalidate(auditPlanProvider(widget.planId));
      if (!mounted) return;
      if (updated.executionId != null) {
        _openFill(updated.executionId!);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auditPlanProvider(widget.planId));
    final user = ref.watch(authUserProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Audit Detail'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(auditPlanProvider(widget.planId));
            await Future<void>.delayed(const Duration(milliseconds: 250));
          },
          child: async.when(
            loading: () => ListView(
              padding: const EdgeInsets.all(16),
              children: const [AppLoadingBlock(height: 280)],
            ),
            error: (e, __) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppErrorPanel(
                  message: 'Could not load this audit.\n$e',
                  onRetry: () => ref.invalidate(auditPlanProvider(widget.planId)),
                ),
              ],
            ),
            data: (plan) => _body(plan, user),
          ),
        ),
      ),
    );
  }

  Widget _body(AuditPlan plan, AuthUser? user) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _Header(plan: plan),
        const SizedBox(height: 14),
        AuditSectionCard(
          title: 'Plan details',
          icon: Icons.assignment_rounded,
          children: [
            AuditKeyValueRow(label: 'Code', value: plan.code ?? '—'),
            AuditKeyValueRow(
                label: Branding.current.term('branch'),
                value: plan.branchName ?? '—'),
            AuditKeyValueRow(
                label: 'Template', value: plan.templateName ?? '—'),
            AuditKeyValueRow(
                label: 'Auditor', value: plan.assignedAuditorName ?? '—'),
            AuditKeyValueRow(
              label: 'Planned',
              value:
                  '${_fmt(plan.plannedStartDate) ?? '—'} → ${_fmt(plan.plannedEndDate) ?? '—'}',
            ),
            AuditKeyValueRow(
              label: 'Period',
              value:
                  '${_fmt(plan.periodFrom) ?? '—'} → ${_fmt(plan.periodTo) ?? '—'}',
            ),
            if ((plan.riskFlag ?? '').isNotEmpty)
              AuditKeyValueRow(label: 'Risk flag', value: plan.riskFlag!),
          ],
        ),
        const SizedBox(height: 14),
        // Findings link.
        InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: plan.executionId == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        FindingsListScreen(executionId: plan.executionId!),
                  )),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            shadow: AppShadows.soft,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.24)),
                  ),
                  child: const Icon(Icons.report_problem_rounded,
                      size: 19, color: AppColors.warning),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Findings',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: plan.executionId == null
                      ? AppColors.muted.withValues(alpha: 0.4)
                      : AppColors.muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        ..._actions(plan, user),
      ],
    );
  }

  List<Widget> _actions(AuditPlan plan, AuthUser? user) {
    final status = plan.status;
    final canPerform = user?.hasPermission('AUDIT_PERFORM') ?? false;
    final canSubmit = user?.hasPermission('AUDIT_SUBMIT') ?? false;
    final canBm = user?.hasPermission('AUDIT_BM_COMPLIANCE') ?? false;
    final canVerify = user?.hasPermission('AUDIT_VERIFY') ?? false;

    final btns = <Widget>[];

    final isFillable = status == 'IN_PROGRESS' || status == 'REOPENED';
    final notStarted =
        status == 'DRAFT' || status == 'PLANNED' || status == null;

    if (canPerform && (isFillable || notStarted)) {
      btns.add(_PrimaryAction(
        label: plan.executionId == null ? 'Start audit' : 'Continue audit',
        icon: Icons.play_circle_fill_rounded,
        busy: _busy,
        onTap: () => _startOrContinue(plan),
      ));
    }

    if ((canSubmit || canPerform) && status == 'SUBMITTED') {
      btns.add(_SecondaryAction(
        label: 'Send to Branch Manager',
        icon: Icons.send_rounded,
        busy: _busy,
        onTap: () => _run(
          () => ref.read(auditRepositoryProvider).sendToBm(widget.planId),
          successMsg: 'Sent to Branch Manager',
        ),
      ));
    }

    // Backend statuses: BM_ACTION_PENDING (sent to BM; REOPENED also accepts a
    // BM re-submission) and VERIFICATION_PENDING (BM submitted, awaiting close).
    if (canBm && (status == 'BM_ACTION_PENDING' || status == 'REOPENED')) {
      btns.add(_SecondaryAction(
        label: 'Submit BM compliance',
        icon: Icons.assignment_turned_in_rounded,
        busy: _busy,
        onTap: () => _run(
          () => ref.read(auditRepositoryProvider).bmSubmit(widget.planId),
          successMsg: 'BM compliance submitted',
        ),
      ));
    }

    if (canVerify && status == 'VERIFICATION_PENDING') {
      btns.add(_SecondaryAction(
        label: 'Close audit',
        icon: Icons.check_circle_rounded,
        busy: _busy,
        onTap: () => _run(
          () => ref.read(auditRepositoryProvider).closePlan(widget.planId),
          successMsg: 'Audit closed',
        ),
      ));
    }

    if (canVerify && status == 'CLOSED') {
      btns.add(_SecondaryAction(
        label: 'Reopen audit',
        icon: Icons.lock_open_rounded,
        busy: _busy,
        onTap: () async {
          final reason = await _askReason('Reopen audit');
          if (reason == null) return;
          await _run(
            () =>
                ref.read(auditRepositoryProvider).reopenPlan(widget.planId, reason),
            successMsg: 'Audit reopened',
          );
        },
      ));
    }

    if ((canVerify || canPerform) &&
        (notStarted || isFillable || status == 'SUBMITTED')) {
      btns.add(_DangerAction(
        label: 'Cancel audit',
        icon: Icons.cancel_rounded,
        busy: _busy,
        onTap: () async {
          final reason = await _askReason('Cancel audit');
          if (reason == null) return;
          await _run(
            () =>
                ref.read(auditRepositoryProvider).cancelPlan(widget.planId, reason),
            successMsg: 'Audit cancelled',
          );
        },
      ));
    }

    if (btns.isEmpty) return const [];
    return [
      const AppSectionHeader(title: 'Actions'),
      const SizedBox(height: 10),
      for (final b in btns) ...[b, const SizedBox(height: 10)],
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.plan});
  final AuditPlan plan;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      shadow: AppShadows.card,
      child: Row(
        children: [
          AuditScoreRing(score: plan.finalScore, size: 68, label: 'Score'),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title ?? plan.code ?? 'Audit',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((plan.code ?? '').isNotEmpty) plan.code!,
                    if ((plan.branchName ?? '').isNotEmpty) plan.branchName!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    AuditStatusChip(status: plan.status),
                    if ((plan.grade ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      StatusPill(
                        label: 'Grade ${plan.grade}',
                        color: AppColors.primary,
                      ),
                    ],
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

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _DangerAction extends StatelessWidget {
  const _DangerAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: Icon(icon, size: 18, color: AppColors.danger),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
        ),
        label: Text(label),
      ),
    );
  }
}
