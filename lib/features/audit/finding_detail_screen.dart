// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — finding detail.
//
//  Shows the finding, its CAPA history and verification trail. A BM (with
//  AUDIT_BM_COMPLIANCE) can submit a CAPA; an auditor (with AUDIT_VERIFY) can
//  take a verification action (ACCEPT / REJECT / REOPEN / ESCALATE / CLOSE).
//  Photo proof can be attached to the finding. Required fields are validated
//  before submit.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'audit_models.dart';
import 'audit_proof.dart';
import 'audit_repository.dart';
import 'audit_widgets.dart';

class FindingDetailScreen extends ConsumerWidget {
  const FindingDetailScreen({super.key, required this.findingId});
  final int findingId;

  static String? _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('dd MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(findingDetailProvider(findingId));
    final user = ref.watch(authUserProvider);
    // Same gates as web AuditFindingsPage (ADMIN fallback + close/reopen roles).
    bool has(List<String> p) => p.any((x) => user?.hasPermission(x) ?? false);
    final canBm = has(const ['AUDIT_BM_COMPLIANCE', 'AUDIT_ADMIN']);
    final canVerify = has(const [
      'AUDIT_VERIFY', 'AUDIT_REOPEN', 'AUDIT_CLOSE', 'AUDIT_ADMIN',
    ]);

    Future<void> reload() async {
      ref.invalidate(findingDetailProvider(findingId));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Finding detail')),
      body: async.when(
        loading: () => ProPage(
          onRefresh: reload,
          children: const [AppLoadingBlock(height: 280)],
        ),
        error: (e, __) => ProPage(
          onRefresh: reload,
          children: [
            AppErrorPanel(
              message: 'Could not load this finding.\n$e',
              onRetry: () => ref.invalidate(findingDetailProvider(findingId)),
            ),
          ],
        ),
        data: (detail) => ProPage(
          onRefresh: reload,
          hero: _hero(detail),
          children: [
            _findingCard(detail.finding),
            _capaHistory(detail.capaHistory),
            _verifications(detail.verifications),
            _photoCard(detail.finding),
            // Compliance can be submitted only while the finding awaits action
            // (not once already submitted, until a verifier reopens/rejects it).
            if (canBm && detail.canSubmitCompliance)
              _CapaForm(findingId: findingId)
            else if (canBm && detail.complianceSubmitted)
              const ProNote(
                'Compliance has been submitted and is awaiting verification. '
                'You can submit again only if a verifier rejects or reopens this finding.',
                tone: ProNoteTone.info,
              ),
            // Verification is available only to verifiers, and only once
            // compliance has been submitted.
            if (canVerify && detail.canVerify)
              _VerifyForm(findingId: findingId)
            else if (canVerify && !detail.canVerify)
              const ProNote(
                'Verification becomes available once the branch manager submits '
                'compliance for this finding.',
              ),
          ],
        ),
      ),
    );
  }

  // ── Hero ───────────────────────────────────────────────────────────────────

  Widget _hero(AuditFindingDetail detail) {
    final f = detail.finding;
    final st = findingStatusTone(f.status);
    final sev = severityTone(f.severity);
    final role = [
      if ((f.code ?? '').isNotEmpty) f.code!,
      if ((f.category ?? '').isNotEmpty) f.category!,
    ].join(' · ');

    // Workflow line, from the flags the server already sent.
    final String live;
    final Color liveColor;
    if (f.status == 'CLOSED') {
      live = 'Finding closed';
      liveColor = AppColors.live;
    } else if (detail.canVerify || detail.complianceSubmitted) {
      live = 'Compliance submitted · awaiting verification';
      liveColor = const Color(0xFFF2B347);
    } else if (detail.canSubmitCompliance) {
      live = 'Waiting for branch manager compliance';
      liveColor = const Color(0xFFF2B347);
    } else {
      live = st.label;
      liveColor = st.color == AppColors.danger
          ? const Color(0xFFE5484D)
          : AppColors.live;
    }

    return ProHero(
      overlap: ProKpiStrip(cells: [
        _dueKpi(f),
        ProKpi(value: '${detail.capaHistory.length}', label: 'CAPA submitted'),
        ProKpi(
          value: '${detail.verifications.length}',
          label: 'Verification actions',
        ),
      ]),
      children: [
        ProHeroIdentity(
          name: f.title ?? f.code ?? 'Finding',
          role: role.isEmpty ? null : role,
          icon: Icons.report_problem_rounded,
          tags: [
            ProHeroTag(st.label, tone: auditTagTone(st.color)),
            ProHeroTag(sev.label,
                tone: auditTagTone(sev.color), icon: Icons.flag_rounded),
            if ((f.questionCode ?? '').isNotEmpty)
              ProHeroTag('Q ${f.questionCode}'),
          ],
        ),
        ProLiveLine(text: live, color: liveColor),
      ],
    );
  }

  /// Days left until the due date (or overdue), derived from the finding.
  static ProKpi _dueKpi(AuditFinding f) {
    final due = (f.dueDate == null || f.dueDate!.isEmpty)
        ? null
        : DateTime.tryParse(f.dueDate!);
    if (due == null) return const ProKpi(value: '—', label: 'No due date');
    final label = DateFormat('dd MMM').format(due);
    if (f.status == 'CLOSED') {
      return ProKpi(value: 'Closed', label: 'Due $label');
    }
    final days = DateUtils.dateOnly(due)
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    if (days < 0) {
      return ProKpi(
        value: '${-days}d',
        label: 'Overdue · due $label',
        valueColor: AppColors.danger,
      );
    }
    return ProKpi(
      value: days == 0 ? 'Today' : '${days}d',
      label: days == 0 ? 'Due today' : 'Left · due $label',
      valueColor: days <= 2 ? const Color(0xFF9A5B00) : null,
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _findingCard(AuditFinding f) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Observation'),
          if ((f.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              f.description!,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: AppColors.inkSoft,
              ),
            ),
          ],
          const SizedBox(height: 6),
          _PillRow(label: 'Severity', child: SeverityChip(severity: f.severity)),
          _PillRow(label: 'Status', child: FindingStatusChip(status: f.status)),
          ProKeyValue(rows: [
            if (_fmt(f.dueDate) != null) MapEntry('Due', _fmt(f.dueDate)!),
            if ((f.code ?? '').isNotEmpty) MapEntry('Finding', f.code!),
            if ((f.category ?? '').isNotEmpty) MapEntry('Category', f.category!),
            if ((f.questionCode ?? '').isNotEmpty)
              MapEntry('Question', f.questionCode!),
          ]),
        ],
      ),
    );
  }

  Widget _capaHistory(List<Capa> history) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'CAPA history'),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Text('No CAPA submitted yet.', style: AppText.caption)
          else
            for (var i = 0; i < history.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
              _capaEntry(history[i]),
            ],
        ],
      ),
    );
  }

  Widget _capaEntry(Capa c) {
    Widget line(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final by = c.submittedByName ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (by.isNotEmpty || _fmt(c.createdAt) != null)
          Row(
            children: [
              if (by.isNotEmpty) ...[
                ProAvatar(name: by, size: 28),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  [
                    if (by.isNotEmpty) by,
                    if (_fmt(c.createdAt) != null) _fmt(c.createdAt)!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkSoft,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        line('Root cause', c.rootCause),
        line('Corrective', c.correctiveAction),
        line('Preventive', c.preventiveAction),
        line('Remarks', c.complianceRemarks),
        line('Expected closure', _fmt(c.expectedClosureDate)),
      ],
    );
  }

  Widget _verifications(List<Verification> verifications) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Verification trail'),
          const SizedBox(height: 8),
          if (verifications.isEmpty)
            const Text('No verification actions yet.', style: AppText.caption)
          else
            for (final v in verifications)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    auditPill(v.action ?? '—', _actionColor(v.action)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((v.remarks ?? '').isNotEmpty)
                            Text(
                              v.remarks!,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.4,
                                color: AppColors.ink,
                              ),
                            ),
                          Text(
                            [
                              if ((v.verifiedByName ?? '').isNotEmpty)
                                v.verifiedByName!,
                              if (_fmt(v.createdAt) != null) _fmt(v.createdAt)!,
                              if (_fmt(v.dueDate) != null)
                                'Due ${_fmt(v.dueDate)}',
                            ].join(' · '),
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static Color _actionColor(String? a) => switch (a) {
        'ACCEPT' || 'CLOSE' => AppColors.success,
        'REJECT' => AppColors.danger,
        'REOPEN' || 'ESCALATE' => AppColors.warning,
        _ => AppColors.primary,
      };

  Widget _photoCard(AuditFinding f) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(
            title: 'Photo proof',
            subtitle: 'Photos are compressed and stamped with the time and your location.',
          ),
          const SizedBox(height: 12),
          AddPhotoProofButton(
            parentType: 'FINDING',
            parentId: findingId,
            executionId: f.executionId,
          ),
        ],
      ),
    );
  }
}

/// "Label ............ [pill]" row matching [ProKeyValue] spacing.
class _PillRow extends StatelessWidget {
  const _PillRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

// ── BM CAPA form ─────────────────────────────────────────────────────────────

class _CapaForm extends ConsumerStatefulWidget {
  const _CapaForm({required this.findingId});
  final int findingId;

  @override
  ConsumerState<_CapaForm> createState() => _CapaFormState();
}

class _CapaFormState extends ConsumerState<_CapaForm> {
  final _rootCause = TextEditingController();
  final _corrective = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _rootCause.dispose();
    _corrective.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rootCause.text.trim().isEmpty ||
        _corrective.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Root cause and corrective action are required.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(auditRepositoryProvider).submitCapa(widget.findingId, {
        'rootCause': _rootCause.text.trim(),
        'correctiveAction': _corrective.text.trim(),
      });
      ref.invalidate(findingDetailProvider(widget.findingId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compliance submitted.'),
          backgroundColor: AppColors.success,
        ),
      );
      _rootCause.clear();
      _corrective.clear();
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
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Submit compliance'),
          const SizedBox(height: 12),
          _field(_rootCause, 'Root cause', maxLines: 2),
          const SizedBox(height: 12),
          _field(_corrective, 'Corrective action', maxLines: 2),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(_busy ? 'Submitting…' : 'Submit compliance'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) {
    return ProField(
      label: label,
      required: true,
      child: TextField(
        controller: c,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.words,
        inputFormatters: const [TitleCaseTextFormatter()],
      ),
    );
  }
}

// ── Auditor verify form ──────────────────────────────────────────────────────

const _kVerifyActions = ['ACCEPT', 'REJECT', 'REOPEN', 'ESCALATE', 'CLOSE'];

class _VerifyForm extends ConsumerStatefulWidget {
  const _VerifyForm({required this.findingId});
  final int findingId;

  @override
  ConsumerState<_VerifyForm> createState() => _VerifyFormState();
}

class _VerifyFormState extends ConsumerState<_VerifyForm> {
  String _action = 'ACCEPT';
  final _remarks = TextEditingController();
  DateTime? _dueDate;
  bool _busy = false;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(auditRepositoryProvider).verifyFinding(widget.findingId, {
        'action': _action,
        'remarks': _remarks.text.trim(),
        if (_dueDate != null)
          'dueDate': DateFormat('yyyy-MM-dd').format(_dueDate!),
      });
      ref.invalidate(findingDetailProvider(widget.findingId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Finding ${_action.toLowerCase()}ed.'),
          backgroundColor: AppColors.success,
        ),
      );
      _remarks.clear();
      setState(() => _dueDate = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _actionLabel(String a) =>
      a.isEmpty ? a : '${a[0]}${a.substring(1).toLowerCase()}';

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Verify finding (auditor)'),
          const SizedBox(height: 12),
          ProField(
            label: 'Action',
            child: DropdownButtonFormField<String>(
              initialValue: _action,
              items: [
                for (final a in _kVerifyActions)
                  DropdownMenuItem(value: a, child: Text(_actionLabel(a))),
              ],
              onChanged: (v) => setState(() => _action = v ?? 'ACCEPT'),
            ),
          ),
          const SizedBox(height: 12),
          ProField(
            label: 'Remarks',
            child: TextField(
              controller: _remarks,
              maxLines: 2,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
            ),
          ),
          const SizedBox(height: 12),
          ProField(
            label: 'Due date (for reopen/escalate)',
            child: _DatePickerRow(
              label: 'Select a date',
              value: _dueDate,
              onPick: (d) => setState(() => _dueDate = d),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(_busy ? 'Submitting…' : 'Submit action'),
          ),
        ],
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    required this.label,
    required this.value,
    required this.onPick,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

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
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 3),
          );
          if (picked != null) onPick(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.event_rounded, size: 18, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value == null ? label : DateFormat('dd MMM yyyy').format(value!),
                  style: TextStyle(
                    fontSize: 15,
                    color: value == null ? AppColors.faint : AppColors.ink,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
