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

import '../../core/download_saver.dart';
import '../../core/employee_lookup.dart';
import '../../core/report_download.dart';
import '../../core/text_formatters.dart';
import '../../core/branding.dart';
import '../../core/pro_ui.dart';
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

  Future<void> _reload() async {
    ref.invalidate(auditPlanProvider(widget.planId));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auditPlanProvider(widget.planId));
    final user = ref.watch(authUserProvider);
    final loaded = async.valueOrNull;
    final primary = loaded == null ? null : _actionSet(loaded, user).primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Audit detail')),
      body: async.when(
        loading: () => ProPage(
          onRefresh: _reload,
          children: const [AppLoadingBlock(height: 280)],
        ),
        error: (e, __) => ProPage(
          onRefresh: _reload,
          children: [
            AppErrorPanel(
              message: 'Could not load this audit.\n$e',
              onRetry: () => ref.invalidate(auditPlanProvider(widget.planId)),
            ),
          ],
        ),
        data: (plan) => _body(plan, user),
      ),
      bottomNavigationBar: (loaded == null || primary == null)
          ? null
          : ProBottomBar(children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _startOrContinue(loaded),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                label: Text(primary),
              ),
            ]),
    );
  }

  // ── Reports ────────────────────────────────────────────────────────────────

  Future<void> _downloadExcel() async {
    await downloadExcelReport(
      context,
      () => ref.read(auditRepositoryProvider).downloadReport(widget.planId, 'excel'),
      'Audit_${widget.planId}.xlsx',
    );
    ref.invalidate(_reportHistoryProvider(widget.planId));
  }

  Future<void> _downloadPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Preparing report…')));
    try {
      final bytes =
          await ref.read(auditRepositoryProvider).downloadReport(widget.planId, 'pdf');
      final name = 'Audit_${widget.planId}.pdf';
      final saved =
          await DownloadSaver.save(name, bytes, mimeType: 'application/pdf');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('Saved to ${saved.locationLabel}: $name'),
        action: saved.canOpen
            ? SnackBarAction(label: 'Open', onPressed: () => saved.open())
            : null,
      ));
      ref.invalidate(_reportHistoryProvider(widget.planId));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
          SnackBar(content: Text('Could not download the report: $e')));
    }
  }

  ({bool excel, bool pdf}) _reportPerms(AuthUser? user) {
    bool has(List<String> p) => p.any((x) => user?.hasPermission(x) ?? false);
    return (
      excel: has(const ['AUDIT_REPORT_DOWNLOAD', 'AUDIT_EXPORT_EXCEL', 'AUDIT_ADMIN']),
      pdf: has(const ['AUDIT_REPORT_DOWNLOAD', 'AUDIT_EXPORT_PDF', 'AUDIT_ADMIN']),
    );
  }

  Widget? _reportsCard(AuthUser? user) {
    final perms = _reportPerms(user);
    final canExcel = perms.excel;
    final canPdf = perms.pdf;
    if (!canExcel && !canPdf) return null;
    final history = ref.watch(_reportHistoryProvider(widget.planId));
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Reports'),
          const SizedBox(height: 12),
          Row(children: [
            if (canExcel)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _downloadExcel,
                  icon: const Icon(Icons.table_chart_rounded, size: 18),
                  label: const Text('Excel'),
                ),
              ),
            if (canExcel && canPdf) const SizedBox(width: 10),
            if (canPdf)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _downloadPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('PDF'),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          history.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) => rows.isEmpty
                ? const Text('No reports generated yet.', style: AppText.caption)
                : Column(children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          const ProIconWell(
                              icon: Icons.insert_drive_file_outlined, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (r['fileName'] ??
                                      '${r['reportType'] ?? 'Report'} (${r['format'] ?? ''})')
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.ink),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmt(r['generatedAt']?.toString()) ?? '',
                              style: AppText.caption),
                        ]),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }

  // ── Assign / reassign auditor ──────────────────────────────────────────────

  Future<void> _assign(AuditPlan plan) async {
    final picked = await showModalBottomSheet<EmployeeLookup>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AuditorPickerSheet(),
    );
    if (picked == null) return;
    await _run(
      () => ref.read(auditRepositoryProvider).assignAuditor(widget.planId, picked.id),
      successMsg: 'Auditor assigned: ${picked.name}',
    );
  }

  void _openFindings(AuditPlan plan) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FindingsListScreen(executionId: plan.executionId!),
    ));
  }

  // ── Hero helpers ───────────────────────────────────────────────────────────

  String _liveText(AuditPlan p) {
    final a = p.assignedAuditorName;
    final s = _fmt(p.plannedStartDate);
    final e = _fmt(p.plannedEndDate);
    final window = (s == null && e == null) ? null : '${s ?? '—'} → ${e ?? '—'}';
    if (a == null || a.isEmpty) {
      return window == null
          ? 'No auditor assigned yet'
          : 'No auditor assigned · planned $window';
    }
    return window == null ? 'Auditor $a' : '$a · planned $window';
  }

  Color _liveColor(AuditPlan p) {
    final c = auditStatusTone(p.status).color;
    if (c == AppColors.danger) return const Color(0xFFE5484D);
    if (c == AppColors.warning || c == AppColors.pink) {
      return const Color(0xFFF2B347);
    }
    if (c == AppColors.muted) return Colors.white54;
    return AppColors.live;
  }

  /// "Day 3/7" through the planned window (derived from the plan dates).
  ProKpi _windowKpi(AuditPlan p) {
    DateTime? parse(String? v) =>
        (v == null || v.isEmpty) ? null : DateTime.tryParse(v);
    final s = parse(p.plannedStartDate);
    final e = parse(p.plannedEndDate);
    if (s == null || e == null) {
      return const ProKpi(value: '—', label: 'Planned window');
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final start = DateUtils.dateOnly(s);
    final end = DateUtils.dateOnly(e);
    final total = end.difference(start).inDays + 1;
    if (total <= 0) return const ProKpi(value: '—', label: 'Planned window');
    if (today.isBefore(start)) {
      return ProKpi(
        value: '${start.difference(today).inDays}d',
        label: 'Until planned start',
        progress: 0,
      );
    }
    if (today.isAfter(end)) {
      return ProKpi(
        value: '$total ${total == 1 ? 'day' : 'days'}',
        label: 'Planned window · ended',
        progress: 1,
      );
    }
    final n = today.difference(start).inDays + 1;
    return ProKpi(
      value: 'Day $n/$total',
      label: 'Planned window',
      progress: n / total,
    );
  }

  Widget _body(AuditPlan plan, AuthUser? user) {
    final st = auditStatusTone(plan.status);
    final tone = auditScoreTone(plan.finalScore);
    final set = _actionSet(plan, user);
    final perms = _reportPerms(user);
    final reports = _reportsCard(user);
    final reportCount = (perms.excel || perms.pdf)
        ? ref.watch(_reportHistoryProvider(widget.planId)).valueOrNull?.length
        : null;
    final idLine = [
      if ((plan.code ?? '').isNotEmpty) plan.code!,
      if ((plan.branchName ?? '').isNotEmpty) plan.branchName!,
    ].join(' · ');

    return ProPage(
      onRefresh: _reload,
      hero: ProHero(
        overlap: ProKpiStrip(cells: [
          ProKpi(
            value: auditPct(plan.finalScore),
            label: plan.finalScore == null
                ? 'Score · not yet scored'
                : ((plan.grade ?? '').isNotEmpty
                    ? 'Score · grade ${plan.grade}'
                    : 'Score'),
            progress: ((plan.finalScore ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
            color: tone,
            valueColor: plan.finalScore == null ? null : auditInk(tone),
          ),
          _windowKpi(plan),
          if (perms.excel || perms.pdf)
            ProKpi(
              value: reportCount == null ? '—' : '$reportCount',
              label: 'Reports generated',
            )
          else
            ProKpi(value: plan.riskFlag ?? '—', label: 'Risk flag'),
        ]),
        children: [
          ProHeroIdentity(
            name: plan.title ?? plan.code ?? 'Audit',
            role: idLine.isEmpty ? null : idLine,
            icon: Icons.fact_check_rounded,
            tags: [
              ProHeroTag(st.label, tone: auditTagTone(st.color)),
              if ((plan.grade ?? '').isNotEmpty)
                ProHeroTag('Grade ${plan.grade}', tone: auditTagTone(tone)),
            ],
          ),
          ProLiveLine(text: _liveText(plan), color: _liveColor(plan)),
          ProHeroActions(actions: [
            if (set.primary != null)
              ProAction(
                icon: Icons.play_arrow_rounded,
                label: plan.status == 'ASSIGNED' ? 'Start' : 'Continue',
                primary: true,
                onTap: _busy ? null : () => _startOrContinue(plan),
              ),
            ProAction(
              icon: Icons.report_problem_outlined,
              label: 'Findings',
              onTap: plan.executionId == null ? null : () => _openFindings(plan),
            ),
            if (perms.excel)
              ProAction(
                icon: Icons.table_chart_outlined,
                label: 'Excel',
                onTap: _busy ? null : _downloadExcel,
              ),
            if (perms.pdf)
              ProAction(
                icon: Icons.picture_as_pdf_outlined,
                label: 'PDF',
                onTap: _busy ? null : _downloadPdf,
              ),
          ]),
        ],
      ),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Plan details'),
              const SizedBox(height: 4),
              ProKeyValue(rows: [
                MapEntry('Code', plan.code ?? '—'),
                MapEntry(Branding.current.term('branch'), plan.branchName ?? '—'),
                MapEntry('Template', plan.templateName ?? '—'),
                MapEntry('Auditor', plan.assignedAuditorName ?? '—'),
                MapEntry(
                  'Planned',
                  '${_fmt(plan.plannedStartDate) ?? '—'} → ${_fmt(plan.plannedEndDate) ?? '—'}',
                ),
                MapEntry(
                  'Period',
                  '${_fmt(plan.periodFrom) ?? '—'} → ${_fmt(plan.periodTo) ?? '—'}',
                ),
                if ((plan.riskFlag ?? '').isNotEmpty)
                  MapEntry('Risk flag', plan.riskFlag!),
              ]),
            ],
          ),
        ),
        // Findings link.
        ProListGroup(children: [
          ProListRow(
            leading: const ProIconWell(
              icon: Icons.report_problem_rounded,
              color: AppColors.warning,
            ),
            title: 'Findings',
            subtitle: 'Raised for every “No” when the audit is submitted',
            onTap: plan.executionId == null ? null : () => _openFindings(plan),
          ),
        ]),
        if (reports != null) reports,
        if (set.others.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Actions', small: true),
              const SizedBox(height: 10),
              for (var i = 0; i < set.others.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                set.others[i],
              ],
            ],
          ),
      ],
    );
  }

  /// Workflow actions for the signed-in user. [primary] is the Start /
  /// Continue label (shown in the hero and the bottom bar); `others` are the
  /// remaining buttons, in the same order as before.
  ({String? primary, List<Widget> others}) _actionSet(
      AuditPlan plan, AuthUser? user) {
    final status = plan.status;
    // Same gates as the web plan-detail page (AuditPlanDetailPage.tsx).
    bool has(List<String> p) => p.any((x) => user?.hasPermission(x) ?? false);
    final canPerform = has(const ['AUDIT_PERFORM', 'AUDIT_ADMIN']);
    final canSubmit = has(const ['AUDIT_SUBMIT', 'AUDIT_PERFORM', 'AUDIT_ADMIN']);
    final canBm = has(const ['AUDIT_BM_COMPLIANCE', 'AUDIT_ADMIN']);
    final canAssign = has(const ['AUDIT_ASSIGN', 'AUDIT_ADMIN']);
    final canClose = has(const ['AUDIT_CLOSE', 'AUDIT_ADMIN']);
    final canReopen = has(const ['AUDIT_REOPEN', 'AUDIT_ADMIN']);
    final canCancel =
        has(const ['AUDIT_ASSIGN', 'AUDIT_PLAN_CREATE', 'AUDIT_ADMIN']);
    final canSupervisorApprove =
        has(const ['AUDIT_SUPERVISOR_APPROVE', 'AUDIT_ADMIN']);

    String? primary;
    final btns = <Widget>[];

    // Web shows Start/Continue only for ASSIGNED, IN_PROGRESS and REOPENED.
    final isFillable = status == 'IN_PROGRESS' || status == 'REOPENED';

    if (canPerform && (isFillable || status == 'ASSIGNED')) {
      primary = status == 'ASSIGNED' ? 'Start audit' : 'Continue audit';
    }

    if (canAssign &&
        const ['DRAFT', 'PLANNED', 'ASSIGNED', 'REOPENED'].contains(status)) {
      btns.add(_SecondaryAction(
        label: plan.assignedAuditorId != null ? 'Reassign auditor' : 'Assign auditor',
        icon: Icons.person_add_alt_1_rounded,
        busy: _busy,
        onTap: () => _assign(plan),
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

    // The auditor's supervisor approves a submitted audit (with findings) before
    // the branch manager can act. Only the reporting manager / AUDIT_ADMIN passes
    // the backend guard; the button just needs the permission to appear.
    if (canSupervisorApprove && status == 'SUPERVISOR_APPROVAL_PENDING') {
      btns.add(_SecondaryAction(
        label: 'Approve (supervisor)',
        icon: Icons.verified_rounded,
        busy: _busy,
        onTap: () => _run(
          () => ref.read(auditRepositoryProvider).supervisorApprove(widget.planId),
          successMsg: 'Approved — branch action pending',
        ),
      ));
      btns.add(_DangerAction(
        label: 'Reject',
        icon: Icons.close_rounded,
        busy: _busy,
        onTap: () async {
          final reason = await _askReason('Reject audit');
          if (reason == null) return;
          await _run(
            () => ref
                .read(auditRepositoryProvider)
                .supervisorReject(widget.planId, reason),
            successMsg: 'Sent back to auditor',
          );
        },
      ));
    }

    // Backend statuses: BM_ACTION_PENDING (sent to BM; REOPENED also accepts a
    // BM re-submission) and VERIFICATION_PENDING (BM submitted, awaiting close).
    if (canBm && status == 'BM_ACTION_PENDING') {
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

    if (canClose &&
        const ['SUBMITTED', 'BM_ACTION_SUBMITTED', 'VERIFICATION_PENDING']
            .contains(status)) {
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

    if (canReopen && status == 'CLOSED') {
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

    if (canCancel && status != 'CLOSED' && status != 'CANCELLED') {
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

    return (primary: primary, others: btns);
  }
}

final _reportHistoryProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int>(
  (ref, planId) => ref.watch(auditRepositoryProvider).reportHistory(planId),
);

/// Bottom sheet: search employees with the AUDITOR role and pick one.
class _AuditorPickerSheet extends ConsumerStatefulWidget {
  const _AuditorPickerSheet();

  @override
  ConsumerState<_AuditorPickerSheet> createState() =>
      _AuditorPickerSheetState();
}

class _AuditorPickerSheetState extends ConsumerState<_AuditorPickerSheet> {
  final _ctrl = TextEditingController();
  Future<List<EmployeeLookup>>? _future;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() {
      _future = q.trim().length < 2
          ? null
          : ref.read(auditRepositoryProvider).searchAuditors(q.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuditSheet(
      title: 'Select auditor',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search auditor by name',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 10),
          if (_future != null)
            FutureBuilder<List<EmployeeLookup>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(minHeight: 2));
                }
                if (snap.hasError) {
                  return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('${snap.error}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.danger)));
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('No matching auditors', style: AppText.caption));
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: ProListGroup(
                      children: [
                        for (final e in list)
                          ProListRow(
                            leading: ProAvatar(name: e.name, size: 36),
                            title: e.name,
                            subtitle: (e.code ?? '').isEmpty ? null : e.code,
                            chevron: false,
                            dense: true,
                            onTap: () => Navigator.pop(context, e),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
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
      child: FilledButton.icon(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.dangerTint,
          foregroundColor: AppColors.danger,
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
