// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — fill screen (auditor). Tabs: Rating, one per category
//  (Yes/No/NA checklist + observation + BM compliance), the four annexures, and
//  Executive Summary + Submit. Read-only unless the audit is IN_PROGRESS/REOPENED.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text_formatters.dart';
import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'audit_models.dart';
import 'audit_proof.dart';
import 'audit_repository.dart';
import 'audit_widgets.dart';
import 'offline/audit_offline_store.dart';
import 'offline/audit_sync_service.dart';

const _odRootCauses = <String>[
  'Client migrated/absconding', 'Crisis in family/Health', 'Willingful defaulter',
  'Loss of Assets/Business income', 'Loan pipelining/Middlemen', 'Dummy/Ghost Client',
  'Insurance Claim related', 'Staff Fraud', 'Wrong behavior/ promise by staff',
  'Natural Calamities', 'EMI misutilize by group member', 'Wrong selection of client',
  'System/Recon/non geniune case',
];

class AuditFillScreen extends ConsumerStatefulWidget {
  const AuditFillScreen({super.key, required this.executionId});
  final int executionId;

  @override
  ConsumerState<AuditFillScreen> createState() => _AuditFillScreenState();
}

class _AuditFillScreenState extends ConsumerState<AuditFillScreen> {
  final Map<int, String?> _answers = {};
  final Map<int, TextEditingController> _obs = {};
  final Map<int, QuestionLine> _questions = {}; // questionId -> line (for rules + attachment count)
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _obs.values) { c.dispose(); }
    super.dispose();
  }

  AuditOfflineStore get _store => ref.read(auditOfflineStoreProvider);

  void _seed(AuditExecutionDetail d) {
    // Refresh the per-question line snapshot every load so attachmentCount stays current.
    for (final cat in d.categories) {
      for (final sub in cat.subsections) {
        for (final q in sub.questions) {
          final id = q.questionId;
          if (id == null) continue;
          _questions[id] = q;
        }
      }
    }
    if (_seeded) return;
    _questions.forEach((id, q) {
      _answers[id] = q.answer;
      _obs[id] = TextEditingController(text: q.auditorObservation ?? '');
    });
    _seeded = true;
    _applyDraft(); // overlay any locally-saved offline draft
  }

  Future<void> _applyDraft() async {
    final draft = await _store.loadDraft(widget.executionId);
    if (draft == null || !mounted) return;
    draft.answers.forEach((qid, ans) { if (_answers.containsKey(qid)) _answers[qid] = ans; });
    draft.observations.forEach((qid, t) { _obs[qid]?.text = t; });
    setState(() {});
  }

  List<Map<String, dynamic>> _responsesPayload() => _answers.entries
      .map((e) => {
            'questionId': e.key,
            'answer': e.value,
            'auditorObservation': _obs[e.key]?.text,
          })
      .toList();

  Future<void> _persistDraft() async {
    await _store.saveDraft(AuditDraft(
      executionId: widget.executionId,
      answers: Map.of(_answers),
      observations: {for (final e in _obs.entries) e.key: e.value.text},
      compliance: const {},
      updatedAt: DateTime.now().toIso8601String(),
    ));
  }

  // ── Offline-capable validation (live, reflects unsaved edits) ──
  bool _ruleRequires(String? rule, String? ans) {
    if (rule == null || ans == null || ans == 'NA') return false;
    switch (rule) {
      case 'REQUIRED_ALWAYS': return true;
      case 'REQUIRED_IF_YES': return ans == 'YES';
      case 'REQUIRED_IF_NO': return ans == 'NO';
      default: return false;
    }
  }

  bool _isIncomplete(QuestionLine q) {
    final id = q.questionId;
    if (id == null) return false;
    final ans = _answers[id];
    final obs = _obs[id]?.text ?? '';
    if (q.mandatory && ans == null) return true;
    if (_ruleRequires(q.observationRule, ans) && obs.trim().isEmpty) return true;
    if (_ruleRequires(q.attachmentRule, ans) && q.attachmentCount <= 0) return true;
    return false;
  }

  String _reasonFor(QuestionLine q) {
    final id = q.questionId;
    final ans = id == null ? null : _answers[id];
    if (q.mandatory && ans == null) return 'Not answered';
    if (_ruleRequires(q.observationRule, ans) && (_obs[id]?.text ?? '').trim().isEmpty) {
      return 'Observation required';
    }
    if (_ruleRequires(q.attachmentRule, ans) && q.attachmentCount <= 0) return 'Attachment required';
    return '';
  }

  /// (answered, total, pendingCount, anyApplicable)
  ({int answered, int total, int pending, bool applicable}) _progress() {
    int total = 0, answered = 0, pending = 0;
    bool applicable = false;
    for (final q in _questions.values) {
      total++;
      final ans = _answers[q.questionId];
      if (ans != null) answered++;
      if (ans == 'YES' || ans == 'NO') applicable = true;
      if (_isIncomplete(q)) pending++;
    }
    return (answered: answered, total: total, pending: pending, applicable: applicable);
  }

  List<QuestionLine> _pendingList() =>
      _questions.values.where(_isIncomplete).toList()
        ..sort((a, b) => (a.code ?? '').compareTo(b.code ?? ''));

  void _openPendingSheet() {
    final pending = _pendingList();
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => AuditSheet(
        title: 'Pending checklist',
        subtitle: pending.isEmpty ? null : '${pending.length} item(s) to complete',
        child: pending.isEmpty
            ? const ProNote('All questions complete. You can submit.',
                tone: ProNoteTone.ok)
            : ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  ProListGroup(
                    dividerIndent: 58,
                    children: [
                      for (final q in pending)
                        _PendingRow(
                          title: '${q.code ?? ''}  ${q.text ?? ''}',
                          reason: _reasonFor(q),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _enqueueResponses() async {
    await _store.enqueue(AuditQueueItem(
      id: AuditOfflineStore.newItemId(),
      type: 'SAVE_RESPONSES',
      executionId: widget.executionId,
      payload: {'responses': _responsesPayload()},
      createdAt: DateTime.now().toIso8601String(),
    ));
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _saveResponses() async {
    setState(() => _saving = true);
    await _persistDraft(); // always keep a local copy first
    try {
      await ref.read(auditRepositoryProvider).saveResponses(widget.executionId, _responsesPayload());
      ref.invalidate(auditExecutionProvider(widget.executionId));
      _snack('Responses saved');
    } catch (e) {
      if (isNetworkError(e)) {
        await _enqueueResponses();
        _snack('Offline — saved locally, will sync when online');
      } else {
        _snack('Save failed: $e');
      }
    } finally {
      ref.invalidate(auditPendingCountProvider);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    // Block final submit when incomplete (works offline). Save Draft stays allowed separately.
    final p = _progress();
    if (p.pending > 0 || !p.applicable) {
      _snack(p.pending > 0
          ? '${p.pending} item(s) pending — answer mandatory questions and add required observations/attachments.'
          : 'Answer at least one Yes/No question before submitting.');
      _openPendingSheet();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit audit?'),
        content: const Text('This locks the checklist, computes the final score, and raises findings for every "No".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    await _persistDraft();
    try {
      await ref.read(auditRepositoryProvider).saveResponses(widget.executionId, _responsesPayload());
      await ref.read(auditRepositoryProvider).submitAudit(widget.executionId);
      await _store.clearDraft(widget.executionId);
      ref.invalidate(auditExecutionProvider(widget.executionId));
      if (mounted) { _snack('Audit submitted'); Navigator.of(context).pop(); }
    } catch (e) {
      if (isNetworkError(e)) {
        await _enqueueResponses();
        await _store.enqueue(AuditQueueItem(
          id: AuditOfflineStore.newItemId(), type: 'SUBMIT', executionId: widget.executionId,
          payload: const {}, createdAt: DateTime.now().toIso8601String()));
        _snack('Offline — submission queued, will sync when online');
      } else {
        _snack('Submit failed: $e');
      }
    } finally {
      ref.invalidate(auditPendingCountProvider);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncNow() async {
    _snack('Syncing…');
    final result = await ref.read(auditSyncServiceProvider).flush();
    ref.invalidate(auditPendingCountProvider);
    ref.invalidate(auditExecutionProvider(widget.executionId));
    _snack(result.stillOffline
        ? 'Still offline — ${result.remaining} pending'
        : 'Synced ${result.synced} change(s)');
  }

  /// Incomplete questions inside one category (tab badge).
  int _pendingIn(CategoryBlock c) {
    var n = 0;
    for (final sub in c.subsections) {
      for (final q in sub.questions) {
        if (_isIncomplete(q)) n++;
      }
    }
    return n;
  }

  Widget _progressCard(
      ({int answered, int total, int pending, bool applicable}) p) {
    final pct = p.total == 0 ? 0.0 : p.answered / p.total;
    final done = p.pending == 0 && p.applicable;
    final tone = done ? AppColors.success : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProIconWell(
                  icon: done ? Icons.verified_rounded : Icons.checklist_rounded,
                  color: tone,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${p.answered}/${p.total} answered'),
                          if (p.pending > 0)
                            TextSpan(
                              text: '  ·  ${p.pending} pending',
                              style: const TextStyle(color: AppColors.danger),
                            ),
                        ]),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text('${(pct * 100).round()}% of the checklist',
                          style: AppText.caption),
                    ],
                  ),
                ),
                if (p.pending > 0)
                  TextButton(
                    onPressed: _openPendingSheet,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('View pending'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ProBar(value: pct, color: tone, height: 6),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auditExecutionProvider(widget.executionId));
    return async.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: proLightAppBar(context, title: 'Audit'),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: AppLoadingBlock(height: 200),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: proLightAppBar(context, title: 'Audit'),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
              message: '$e',
              onRetry: () =>
                  ref.invalidate(auditExecutionProvider(widget.executionId))),
        ),
      ),
      data: (d) {
        _seed(d);
        final editable = d.isEditable;
        final p = _progress();
        final labels = <String>[
          'Rating',
          for (final c in d.categories) c.code ?? c.name ?? '—',
          'Center',
          'Client',
          'OD/NPA',
          'Legal',
          'Summary',
        ];
        final tabs = <Tab>[
          const Tab(text: 'Rating'),
          for (final c in d.categories)
            Tab(
              child: _TabLabel(
                c.code ?? c.name ?? '—',
                badge: editable ? _pendingIn(c) : 0,
              ),
            ),
          const Tab(text: 'Center'),
          const Tab(text: 'Client'),
          const Tab(text: 'OD/NPA'),
          const Tab(text: 'Legal'),
          const Tab(text: 'Summary'),
        ];
        final subtitle = [
          if (d.branchName != null && d.planCode != null) d.planCode!,
          editable ? 'Fill audit' : auditStatusTone(d.status).label,
        ].join(' · ');
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            backgroundColor: AppColors.bg,
            appBar: proLightAppBar(
              context,
              title: d.branchName ?? d.planCode ?? 'Audit',
              subtitle: subtitle,
              actions: [
                if (editable)
                  IconButton(
                    tooltip: 'Pending checklist',
                    onPressed: _openPendingSheet,
                    icon: Badge(
                      isLabelVisible: p.pending > 0,
                      label: Text('${p.pending}'),
                      child: const Icon(Icons.checklist_rounded),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: tabs,
              ),
            ),
            body: Column(
              children: [
                _PendingBanner(onSync: _syncNow),
                if (editable) _progressCard(p),
                _TabStep(labels: labels),
                Expanded(
                  child: TabBarView(
                    children: [
                      _RatingTab(executionId: widget.executionId, detail: d, editable: editable),
                      for (final c in d.categories) _CategoryTab(
                        category: c,
                        editable: editable,
                        answers: _answers,
                        obs: _obs,
                        executionId: widget.executionId,
                        isIncomplete: _isIncomplete,
                        onChanged: () => setState(() {}),
                        onAttachmentChanged: () => ref.invalidate(auditExecutionProvider(widget.executionId)),
                      ),
                      _AnnexureTab(executionId: widget.executionId, type: 'center', editable: editable),
                      _AnnexureTab(executionId: widget.executionId, type: 'client', editable: editable),
                      _AnnexureTab(executionId: widget.executionId, type: 'od', editable: editable),
                      _AnnexureTab(executionId: widget.executionId, type: 'branch', editable: editable),
                      _SummaryTab(executionId: widget.executionId, detail: d, editable: editable),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: !editable
                ? null
                : ProBottomBar(children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _saveResponses,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: p.pending == 0
                              ? AppColors.primary
                              : AppColors.muted),
                      onPressed: _saving ? null : _submit,
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(_saving
                          ? 'Working…'
                          : (p.pending == 0 ? 'Submit' : 'Submit (${p.pending})')),
                    ),
                  ]),
          ),
        );
      },
    );
  }
}

// ── Header bits ───────────────────────────────────────────────────────────────

/// Tab text with a small red count of incomplete questions.
class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {this.badge = 0});
  final String label;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (badge > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.dangerTint,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '$badge',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Step bar showing which section tab is open ("3 of 10").
class _TabStep extends StatelessWidget {
  const _TabStep({required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final tc = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: tc,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Row(
          children: [
            Expanded(child: ProStepBar(total: labels.length, current: tc.index)),
            const SizedBox(width: 10),
            Text(
              '${tc.index + 1} of ${labels.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.title, required this.reason});
  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProIconWell(
              icon: Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Offline pending-sync banner ─────────────────────────────────────────────

class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.onSync});
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(auditPendingCountProvider).asData?.value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    const ink = Color(0xFF8A5200);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 18, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count change(s) pending sync',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600, color: ink)),
                  const Text('Saved on this phone',
                      style: TextStyle(fontSize: 12, color: ink)),
                ],
              ),
            ),
            TextButton(onPressed: onSync, child: const Text('Sync now')),
          ],
        ),
      ),
    );
  }
}

// ── Rating tab ────────────────────────────────────────────────────────────────

class _RatingTab extends ConsumerStatefulWidget {
  const _RatingTab({required this.executionId, required this.detail, required this.editable});
  final int executionId;
  final AuditExecutionDetail detail;
  final bool editable;
  @override
  ConsumerState<_RatingTab> createState() => _RatingTabState();
}

class _RatingTabState extends ConsumerState<_RatingTab> {
  late final Map<String, TextEditingController> _c = {
    'branchManagerName': TextEditingController(text: widget.detail.branchManagerName ?? ''),
    'areaManagerName': TextEditingController(text: widget.detail.areaManagerName ?? ''),
    'divisionManagerName': TextEditingController(text: widget.detail.divisionManagerName ?? ''),
    'totalCustomers': TextEditingController(text: widget.detail.totalCustomers?.toString() ?? ''),
    'totalCenters': TextEditingController(text: widget.detail.totalCenters?.toString() ?? ''),
    'portfolioOutstanding': TextEditingController(text: widget.detail.portfolioOutstanding?.toString() ?? ''),
    'odCustomers': TextEditingController(text: widget.detail.odCustomers?.toString() ?? ''),
    'odAmount': TextEditingController(text: widget.detail.odAmount?.toString() ?? ''),
    'parPercent': TextEditingController(text: widget.detail.parPercent?.toString() ?? ''),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _c.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'branchManagerName': _c['branchManagerName']!.text,
        'areaManagerName': _c['areaManagerName']!.text,
        'divisionManagerName': _c['divisionManagerName']!.text,
        'totalCustomers': int.tryParse(_c['totalCustomers']!.text),
        'totalCenters': int.tryParse(_c['totalCenters']!.text),
        'portfolioOutstanding': double.tryParse(_c['portfolioOutstanding']!.text),
        'odCustomers': int.tryParse(_c['odCustomers']!.text),
        'odAmount': double.tryParse(_c['odAmount']!.text),
        'parPercent': double.tryParse(_c['parPercent']!.text),
      };
      try {
        await ref.read(auditRepositoryProvider).saveRating(widget.executionId, body);
        ref.invalidate(auditExecutionProvider(widget.executionId));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branch details saved')));
      } catch (e) {
        if (isNetworkError(e)) {
          await ref.read(auditOfflineStoreProvider).enqueue(AuditQueueItem(
            id: AuditOfflineStore.newItemId(), type: 'SAVE_RATING', executionId: widget.executionId,
            payload: body, createdAt: DateTime.now().toIso8601String()));
          ref.invalidate(auditPendingCountProvider);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline — details queued for sync')));
        } else {
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        GlassCard(
          child: AuditScoreBar(
            label: 'Overall score',
            score: d.finalScore,
            sub: d.grade == null ? null : 'Grade ${d.grade}',
            riskLevel: d.riskFlag,
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(title: Branding.current.term('branch')),
              const SizedBox(height: 4),
              ProKeyValue(rows: [
                MapEntry(Branding.current.term('branch'), d.branchName ?? '—'),
                MapEntry('Code', d.branchCode ?? '—'),
                MapEntry(Branding.current.term('state'), d.state ?? '—'),
                MapEntry('Auditor', d.auditorName ?? '—'),
                MapEntry('Period', '${d.periodFrom ?? '—'} → ${d.periodTo ?? '—'}'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Managers & statistics'),
              const SizedBox(height: 12),
              _field('Branch manager', 'branchManagerName'),
              const SizedBox(height: 12),
              _field('Area manager', 'areaManagerName'),
              const SizedBox(height: 12),
              _field('Division manager', 'divisionManagerName'),
              const SizedBox(height: 12),
              pair(
                _field('Total customers', 'totalCustomers', number: true),
                _field('Total centers', 'totalCenters', number: true),
              ),
              const SizedBox(height: 12),
              pair(
                _field('Portfolio outstanding', 'portfolioOutstanding', number: true),
                _field('OD customers', 'odCustomers', number: true),
              ),
              const SizedBox(height: 12),
              pair(
                _field('OD amount', 'odAmount', number: true),
                _field('PAR %', 'parPercent', number: true),
              ),
              if (widget.editable) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save branch details'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, String key, {bool number = false}) => ProField(
        label: label,
        child: TextField(
          controller: _c[key],
          enabled: widget.editable,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
          inputFormatters: number ? null : const [TitleCaseTextFormatter()],
        ),
      );
}

// ── Category checklist tab ──────────────────────────────────────────────────

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.category, required this.editable, required this.answers,
    required this.obs, required this.executionId, required this.isIncomplete,
    required this.onChanged, required this.onAttachmentChanged,
  });
  final CategoryBlock category;
  final bool editable;
  final Map<int, String?> answers;
  final Map<int, TextEditingController> obs;
  final int executionId;
  final bool Function(QuestionLine) isIncomplete;
  final VoidCallback onChanged;
  final VoidCallback onAttachmentChanged;

  /// (answered, total) across the given questions.
  (int, int) _count(Iterable<QuestionLine> qs) {
    var a = 0, t = 0;
    for (final q in qs) {
      if (q.questionId == null) continue;
      t++;
      if (answers[q.questionId] != null) a++;
    }
    return (a, t);
  }

  @override
  Widget build(BuildContext context) {
    final all = _count(category.subsections.expand((s) => s.questions));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((category.code ?? '').isNotEmpty)
                    Text(
                      category.code!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  Text(category.name ?? category.code ?? '—', style: AppText.title),
                ],
              ),
            ),
            const SizedBox(width: 10),
            auditPill(
              '${all.$1}/${all.$2}',
              all.$2 > 0 && all.$1 == all.$2 ? AppColors.success : AppColors.muted,
            ),
          ],
        ),
        for (final sub in category.subsections) ...[
          const SizedBox(height: 16),
          _SubHeader(
            code: sub.code,
            name: sub.name,
            count: _count(sub.questions),
          ),
          const SizedBox(height: 8),
          for (final q in sub.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _QuestionCard(
                q: q, editable: editable, executionId: executionId,
                answer: q.questionId == null ? null : answers[q.questionId],
                obs: q.questionId == null ? null : obs[q.questionId],
                incomplete: isIncomplete(q),
                onAnswer: (v) { if (q.questionId != null) { answers[q.questionId!] = v; onChanged(); } },
                onAttachmentChanged: onAttachmentChanged,
              ),
            ),
        ],
      ],
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.code, required this.name, required this.count});
  final String? code;
  final String? name;
  final (int, int) count;

  @override
  Widget build(BuildContext context) {
    final done = count.$2 > 0 && count.$1 == count.$2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if ((code ?? '').isNotEmpty)
                  TextSpan(
                    text: '$code  ',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                TextSpan(text: name ?? ''),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          auditPill('${count.$1}/${count.$2}',
              done ? AppColors.success : AppColors.muted),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.q, required this.editable, required this.executionId, required this.answer,
    required this.obs, required this.incomplete, required this.onAnswer, required this.onAttachmentChanged,
  });
  final QuestionLine q;
  final bool editable;
  final int executionId;
  final String? answer;
  final TextEditingController? obs;
  final bool incomplete;
  final ValueChanged<String?> onAnswer;
  final VoidCallback onAttachmentChanged;

  bool get _needsAttachment => _ruleRequires(q.attachmentRule);
  bool get _needsObservation => _ruleRequires(q.observationRule);

  bool _ruleRequires(String? rule) {
    if (rule == null || answer == null || answer == 'NA') return false;
    switch (rule) {
      case 'REQUIRED_ALWAYS': return true;
      case 'REQUIRED_IF_YES': return answer == 'YES';
      case 'REQUIRED_IF_NO': return answer == 'NO';
      default: return false;
    }
  }

  static String _answerLabel(String opt) => switch (opt) {
        'YES' => 'Yes',
        'NO' => 'No',
        'NA' => 'N/A',
        _ => opt,
      };

  static Color _answerTone(String opt) => switch (opt) {
        'YES' => AppColors.success,
        'NO' => AppColors.danger,
        _ => AppColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final opts = q.naAllowed ? const ['YES', 'NO', 'NA'] : const ['YES', 'NO'];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      color: incomplete ? const Color(0xFFFFFBFB) : null,
      border: incomplete
          ? Border.all(color: AppColors.danger.withValues(alpha: 0.45), width: 1.2)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    if ((q.code ?? '').isNotEmpty)
                      TextSpan(
                        text: '${q.code}  ',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    TextSpan(text: q.text ?? ''),
                  ]),
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (q.mandatory)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('*',
                      style: TextStyle(
                          fontSize: 15,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          if (q.weightage != null || q.riskLevel != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                if (q.weightage != null) auditPill('Wt ${q.weightage}', AppColors.muted),
                if (q.riskLevel != null)
                  auditPill(_riskLabel(q.riskLevel!), _riskColor(q.riskLevel!)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < opts.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _AnswerButton(
                    label: _answerLabel(opts[i]),
                    tone: _answerTone(opts[i]),
                    selected: answer == opts[i],
                    onTap: editable
                        ? () => onAnswer(answer == opts[i] ? null : opts[i])
                        : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ProField(
            label: 'Auditor observation',
            required: _needsObservation,
            child: TextField(
              controller: obs, enabled: editable, minLines: 1, maxLines: 3,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              style: const TextStyle(fontSize: 14.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (editable && q.questionId != null)
                AddPhotoProofButton(
                  parentType: 'QUESTION',
                  parentId: q.questionId!,
                  executionId: executionId,
                  label: _needsAttachment ? 'Attachment *' : 'Attachment',
                  onUploaded: onAttachmentChanged,
                ),
              const SizedBox(width: 8),
              if (q.attachmentCount > 0)
                // Tapping the count opens the uploaded-file list with remove.
                _FilesChip(
                  count: q.attachmentCount,
                  onTap: q.questionId == null
                      ? null
                      : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _QuestionAttachmentsSheet(
                              questionId: q.questionId!,
                              editable: editable,
                              onChanged: onAttachmentChanged,
                            ),
                          ),
                )
              else if (_needsAttachment)
                ProPill.bad('Required'),
            ],
          ),
        ],
      ),
    );
  }

  static String _riskLabel(String r) =>
      r.isEmpty ? r : '${r[0]}${r.substring(1).toLowerCase()} risk';

  static Color _riskColor(String r) => switch (r) {
        'HIGH' => AppColors.danger,
        'MODERATE' => AppColors.warning,
        _ => AppColors.success,
      };
}

/// One Yes / No / N/A segment.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = auditInk(tone);
    return Material(
      color: selected ? auditTint(tone) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? tone.withValues(alpha: 0.55) : const Color(0xFFD9E2E4),
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? ink
                    : (onTap == null ? AppColors.faint : AppColors.inkSoft),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilesChip extends StatelessWidget {
  const _FilesChip({required this.count, required this.onTap});
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.successTint,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attach_file_rounded, size: 14, color: AppColors.success),
              const SizedBox(width: 4),
              Text(
                '$count file(s)',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 16, color: AppColors.success),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Uploaded question files (view + remove) ─────────────────────────────────

class _QuestionAttachmentsSheet extends ConsumerStatefulWidget {
  const _QuestionAttachmentsSheet({
    required this.questionId,
    required this.editable,
    required this.onChanged,
  });
  final int questionId;
  final bool editable;
  /// Invoked after each successful delete so the parent refreshes its counts.
  final VoidCallback onChanged;

  @override
  ConsumerState<_QuestionAttachmentsSheet> createState() =>
      _QuestionAttachmentsSheetState();
}

class _QuestionAttachmentsSheetState
    extends ConsumerState<_QuestionAttachmentsSheet> {
  List<AuditAttachment>? _items;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(auditRepositoryProvider)
          .attachments('QUESTION', widget.questionId);
      if (mounted) setState(() => _items = list);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _delete(AuditAttachment a) async {
    final id = a.id;
    if (id == null) return;
    setState(() => _busyId = id);
    try {
      await ref.read(auditRepositoryProvider).deleteAttachment(id);
      if (!mounted) return;
      setState(() {
        _items = _items?.where((x) => x.id != id).toList();
        _busyId = null;
      });
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final Widget body;
    if (items == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (items.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No files uploaded for this question.',
            style: AppText.caption),
      );
    } else {
      body = ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          ProListGroup(
            children: [
              for (final a in items)
                ProListRow(
                  leading: const ProIconWell(icon: Icons.attach_file_rounded),
                  title: a.fileName ?? 'File #${a.id}',
                  subtitle: a.capturedAt,
                  chevron: false,
                  trailing: widget.editable
                      ? IconButton(
                          icon: _busyId == a.id
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.delete_outline_rounded,
                                  size: 20, color: AppColors.danger),
                          onPressed:
                              _busyId == null ? () => _delete(a) : null,
                          tooltip: 'Remove',
                        )
                      : null,
                ),
            ],
          ),
        ],
      );
    }
    return AuditSheet(title: 'Uploaded files', child: body);
  }
}

// ── Annexure tab (list + add + delete) ──────────────────────────────────────

String _annexureLabel(String type) => switch (type) {
      'center' => 'Center',
      'client' => 'Client',
      'od' => 'OD/NPA',
      _ => 'Legal',
    };

IconData _annexureIcon(String type) => switch (type) {
      'center' => Icons.groups_rounded,
      'client' => Icons.person_rounded,
      'od' => Icons.warning_amber_rounded,
      _ => Icons.gavel_rounded,
    };

class _AnnexureTab extends ConsumerStatefulWidget {
  const _AnnexureTab({required this.executionId, required this.type, required this.editable});
  final int executionId;
  final String type;
  final bool editable;
  @override
  ConsumerState<_AnnexureTab> createState() => _AnnexureTabState();
}

class _AnnexureTabState extends ConsumerState<_AnnexureTab> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final repo = ref.read(auditRepositoryProvider);
    final e = widget.executionId;
    switch (widget.type) {
      case 'center': return (await repo.centerVisits(e)).map(_centerToMap).toList();
      case 'client': return (await repo.clientVisits(e)).map(_clientToMap).toList();
      case 'od': return (await repo.odVisits(e)).map(_odToMap).toList();
      default: return (await repo.branchAnnexures(e)).map(_branchToMap).toList();
    }
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _add() async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true,
      builder: (_) => _AnnexureForm(type: widget.type),
    );
    if (body == null) return;
    try {
      await ref.read(auditRepositoryProvider).addAnnexure(widget.executionId, widget.type, body);
      _refresh();
    } catch (e) {
      if (isNetworkError(e)) {
        await ref.read(auditOfflineStoreProvider).enqueue(AuditQueueItem(
          id: AuditOfflineStore.newItemId(), type: 'ADD_ANNEXURE', executionId: widget.executionId,
          payload: {'type': widget.type, 'body': body}, createdAt: DateTime.now().toIso8601String()));
        ref.invalidate(auditPendingCountProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline — entry queued for sync')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $e')));
      }
    }
  }

  Future<void> _delete(int id) async {
    try {
      await ref.read(auditRepositoryProvider).deleteAnnexure(widget.executionId, widget.type, id);
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: !widget.editable ? null : FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded), label: const Text('Add'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: AppLoadingBlock(height: 160),
              ),
            );
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: AppErrorPanel(message: '${snap.error}', onRetry: _refresh),
              ),
            );
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              children: [
                ProEmpty(
                  icon: _annexureIcon(widget.type),
                  title: 'No entries yet',
                  message: 'Tap Add to record one.',
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              ProSectionHeader(
                title: '${_annexureLabel(widget.type)} · ${rows.length} '
                    '${rows.length == 1 ? 'entry' : 'entries'}',
                small: true,
              ),
              const SizedBox(height: 8),
              ProListGroup(
                children: [
                  for (final r in rows)
                    ProListRow(
                      leading: ProIconWell(
                        icon: _annexureIcon(widget.type),
                        color: AppColors.primary,
                      ),
                      title: r['title']?.toString() ?? '—',
                      titleMaxLines: 2,
                      subtitle: (r['subtitle'] == null ||
                              r['subtitle'].toString().isEmpty)
                          ? null
                          : r['subtitle'].toString(),
                      chevron: false,
                      trailing: (widget.editable && r['id'] != null)
                          ? IconButton(
                              tooltip: 'Delete entry',
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.danger),
                              onPressed: () => _delete(r['id'] as int),
                            )
                          : null,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, dynamic> _centerToMap(AuditCenterVisit a) =>
      {'id': a.id, 'title': a.centerName ?? '—', 'subtitle': [a.foName, a.collectionStatus].whereType<String>().join(' · ')};
  Map<String, dynamic> _clientToMap(AuditClientVisit a) =>
      {'id': a.id, 'title': a.customerName ?? a.customerLoanNumber ?? '—', 'subtitle': a.villageCenterName};
  Map<String, dynamic> _odToMap(AuditOdVisit a) =>
      {'id': a.id, 'title': a.clientName ?? a.loanAccountNumber ?? '—', 'subtitle': a.rootCause};
  Map<String, dynamic> _branchToMap(AuditBranchAnnexure a) =>
      {'id': a.id, 'title': a.particular, 'subtitle': a.available};
}

/// A minimal add-form per annexure type (key fields only).
class _AnnexureForm extends StatefulWidget {
  const _AnnexureForm({required this.type});
  final String type;
  @override
  State<_AnnexureForm> createState() => _AnnexureFormState();
}

class _AnnexureFormState extends State<_AnnexureForm> {
  final _ctrls = <String, TextEditingController>{};
  String? _rootCause;

  List<String> get _fields => switch (widget.type) {
        'center' => const ['centerName', 'foName', 'collectionStatus', 'disciplineStatus', 'auditorRemarks'],
        'client' => const ['customerName', 'customerLoanNumber', 'villageCenterName', 'lucStatus', 'auditorRemarks'],
        'od' => const ['clientName', 'loanAccountNumber', 'centerName', 'village', 'overdueAmount', 'dpdBucket', 'auditorRemarks'],
        _ => const ['particular', 'observation', 'complianceByBm'],
      };

  TextEditingController _ctrl(String k) => _ctrls.putIfAbsent(k, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _ctrls.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = _annexureLabel(widget.type);
    return AuditSheet(
      title: 'Add ${type == 'OD/NPA' ? type : type.toLowerCase()} entry',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in _fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ProField(
                  label: _label(f),
                  child: TextField(
                    controller: _ctrl(f),
                    keyboardType: _numField(f)
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    textCapitalization: _titleCaseField(f)
                        ? TextCapitalization.words
                        : TextCapitalization.none,
                    inputFormatters:
                        _titleCaseField(f) ? const [TitleCaseTextFormatter()] : null,
                  ),
                ),
              ),
            if (widget.type == 'od')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ProField(
                  label: 'Root cause',
                  child: DropdownButtonFormField<String>(
                    initialValue: _rootCause,
                    isExpanded: true,
                    hint: const Text('Select a root cause'),
                    items: [for (final rc in _odRootCauses) DropdownMenuItem(value: rc, child: Text(rc, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _rootCause = v),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final body = <String, dynamic>{'sortOrder': 0};
                      for (final f in _fields) {
                        final t = _ctrl(f).text.trim();
                        if (t.isEmpty) continue;
                        if (_numField(f)) {
                          final n = num.tryParse(t);
                          if (n == null) {
                            // Never ship free text into a numeric DTO field —
                            // the backend can't parse it and 500s the save.
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${_label(f)} must be a number')),
                            );
                            return;
                          }
                          body[f] = n;
                        } else {
                          body[f] = t;
                        }
                      }
                      if (widget.type == 'od' && _rootCause != null) body['rootCause'] = _rootCause;
                      if (widget.type == 'branch' && body['available'] == null) body['available'] = 'NO';
                      Navigator.pop(context, body);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _numField(String f) => f == 'overdueAmount' || f == 'loanAmount' || f == 'outstandingAmount' || f == 'attendance';
  // Title-case free-text fields only — never numbers or loan/account codes.
  bool _titleCaseField(String f) =>
      !_numField(f) && f != 'customerLoanNumber' && f != 'loanAccountNumber' && f != 'dpdBucket';
  String _label(String f) {
    // "auditorRemarks" → "Auditor remarks" (sentence case for display only).
    final words = f
        .replaceAllMapped(RegExp('([A-Z])'), (m) => ' ${m[1]}')
        .toLowerCase()
        .replaceAll(' by bm', ' by BM')
        .replaceAll('fo ', 'FO ')
        .replaceAll('luc ', 'LUC ')
        .replaceAll('dpd ', 'DPD ');
    return words.replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
  }
}

// ── Executive summary tab ───────────────────────────────────────────────────

class _SummaryTab extends ConsumerStatefulWidget {
  const _SummaryTab({required this.executionId, required this.detail, required this.editable});
  final int executionId;
  final AuditExecutionDetail detail;
  final bool editable;
  @override
  ConsumerState<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<_SummaryTab> {
  late final _remark = TextEditingController(text: widget.detail.auditorFinalRemark ?? '');
  late final _action = TextEditingController(text: widget.detail.bmActionRequirement ?? '');
  bool _saving = false;

  @override
  void dispose() { _remark.dispose(); _action.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'auditorFinalRemark': _remark.text,
      'bmActionRequirement': _action.text,
    };
    try {
      await ref.read(auditRepositoryProvider).saveExecutiveSummary(widget.executionId, body);
      ref.invalidate(auditExecutionProvider(widget.executionId));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Executive summary saved')));
    } catch (e) {
      if (isNetworkError(e)) {
        await ref.read(auditOfflineStoreProvider).enqueue(AuditQueueItem(
          id: AuditOfflineStore.newItemId(), type: 'SAVE_SUMMARY', executionId: widget.executionId,
          payload: body, createdAt: DateTime.now().toIso8601String()));
        ref.invalidate(auditPendingCountProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline — summary queued for sync')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        GlassCard(
          child: AuditScoreBar(
            label: 'Overall score',
            score: d.finalScore,
            sub: d.grade == null ? null : 'Grade ${d.grade}',
            riskLevel: d.riskFlag,
          ),
        ),
        if ((d.executiveSummary ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Auto summary'),
                const SizedBox(height: 8),
                Text(d.executiveSummary!,
                    style: const TextStyle(
                        fontSize: 14, height: 1.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Auditor inputs'),
              const SizedBox(height: 12),
              ProField(
                label: 'Auditor final remark',
                child: TextField(controller: _remark, enabled: widget.editable, minLines: 2, maxLines: 5,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()]),
              ),
              const SizedBox(height: 12),
              ProField(
                label: 'BM action requirement',
                child: TextField(controller: _action, enabled: widget.editable, minLines: 2, maxLines: 5,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()]),
              ),
              if (widget.editable) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save summary'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
