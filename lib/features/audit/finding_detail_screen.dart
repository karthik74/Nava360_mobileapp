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
    final canBm = user?.hasPermission('AUDIT_BM_COMPLIANCE') ?? false;
    final canVerify = user?.hasPermission('AUDIT_VERIFY') ?? false;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Finding'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(findingDetailProvider(findingId));
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
                  message: 'Could not load this finding.\n$e',
                  onRetry: () =>
                      ref.invalidate(findingDetailProvider(findingId)),
                ),
              ],
            ),
            data: (detail) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _findingCard(detail.finding),
                const SizedBox(height: 14),
                _capaHistory(detail.capaHistory),
                const SizedBox(height: 14),
                _verifications(detail.verifications),
                const SizedBox(height: 14),
                AddPhotoProofButton(
                  parentType: 'FINDING',
                  parentId: findingId,
                  executionId: detail.finding.executionId,
                ),
                if (canBm) ...[
                  const SizedBox(height: 18),
                  _CapaForm(findingId: findingId),
                ],
                if (canVerify) ...[
                  const SizedBox(height: 18),
                  _VerifyForm(findingId: findingId),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _findingCard(AuditFinding f) {
    return GlassCard(
      shadow: AppShadows.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  f.title ?? f.code ?? 'Finding',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SeverityChip(severity: f.severity),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FindingStatusChip(status: f.status),
              const Spacer(),
              if (_fmt(f.dueDate) != null)
                Text(
                  'Due ${_fmt(f.dueDate)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
            ],
          ),
          if ((f.description ?? '').isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              f.description!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.inkSoft,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              if ((f.code ?? '').isNotEmpty) f.code!,
              if ((f.category ?? '').isNotEmpty) f.category!,
              if ((f.questionCode ?? '').isNotEmpty) 'Q ${f.questionCode}',
            ].join(' · '),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _capaHistory(List<Capa> history) {
    return AuditSectionCard(
      title: 'CAPA history',
      icon: Icons.healing_rounded,
      children: history.isEmpty
          ? const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'No CAPA submitted yet.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ]
          : [
              for (final c in history) ...[
                _capaEntry(c),
                const Divider(height: 18),
              ],
            ],
    );
  }

  Widget _capaEntry(Capa c) {
    Widget line(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((c.submittedByName ?? '').isNotEmpty || _fmt(c.createdAt) != null)
          Text(
            [
              if ((c.submittedByName ?? '').isNotEmpty) c.submittedByName!,
              if (_fmt(c.createdAt) != null) _fmt(c.createdAt)!,
            ].join(' · '),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        const SizedBox(height: 4),
        line('Root cause', c.rootCause),
        line('Corrective', c.correctiveAction),
        line('Preventive', c.preventiveAction),
        line('Remarks', c.complianceRemarks),
        line('Expected closure', _fmt(c.expectedClosureDate)),
      ],
    );
  }

  Widget _verifications(List<Verification> verifications) {
    return AuditSectionCard(
      title: 'Verification trail',
      icon: Icons.verified_user_rounded,
      children: verifications.isEmpty
          ? const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'No verification actions yet.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ]
          : [
              for (final v in verifications)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusPill(
                        label: v.action ?? '—',
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((v.remarks ?? '').isNotEmpty)
                              Text(
                                v.remarks!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.inkSoft,
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
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
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
  final _preventive = TextEditingController();
  final _remarks = TextEditingController();
  DateTime? _closure;
  bool _busy = false;

  @override
  void dispose() {
    _rootCause.dispose();
    _corrective.dispose();
    _preventive.dispose();
    _remarks.dispose();
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
        'preventiveAction': _preventive.text.trim(),
        'complianceRemarks': _remarks.text.trim(),
        if (_closure != null)
          'expectedClosureDate':
              DateFormat('yyyy-MM-dd').format(_closure!),
      });
      ref.invalidate(findingDetailProvider(widget.findingId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CAPA submitted.'),
          backgroundColor: AppColors.success,
        ),
      );
      _rootCause.clear();
      _corrective.clear();
      _preventive.clear();
      _remarks.clear();
      setState(() => _closure = null);
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
    return AuditSectionCard(
      title: 'Submit CAPA (Branch Manager)',
      icon: Icons.edit_note_rounded,
      children: [
        _field(_rootCause, 'Root cause *', maxLines: 2),
        _field(_corrective, 'Corrective action *', maxLines: 2),
        _field(_preventive, 'Preventive action', maxLines: 2),
        _field(_remarks, 'Compliance remarks', maxLines: 2),
        const SizedBox(height: 8),
        _DatePickerRow(
          label: 'Expected closure date',
          value: _closure,
          onPick: (d) => setState(() => _closure = d),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(_busy ? 'Submitting…' : 'Submit CAPA'),
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
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

  @override
  Widget build(BuildContext context) {
    return AuditSectionCard(
      title: 'Verify finding (Auditor)',
      icon: Icons.rule_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: DropdownButtonFormField<String>(
            initialValue: _action,
            decoration: const InputDecoration(labelText: 'Action'),
            items: [
              for (final a in _kVerifyActions)
                DropdownMenuItem(value: a, child: Text(a)),
            ],
            onChanged: (v) => setState(() => _action = v ?? 'ACCEPT'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: _remarks,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Remarks'),
          ),
        ),
        const SizedBox(height: 8),
        _DatePickerRow(
          label: 'Due date (for reopen/escalate)',
          value: _dueDate,
          onPick: (d) => setState(() => _dueDate = d),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(_busy ? 'Submitting…' : 'Submit action'),
          ),
        ),
      ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value == null
                    ? label
                    : '$label: ${DateFormat('dd MMM yyyy').format(value!)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: value == null ? AppColors.muted : AppColors.ink,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
