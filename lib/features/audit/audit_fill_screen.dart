// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — fill screen (auditor). Tabs: Rating, one per category
//  (Yes/No/NA checklist + observation + BM compliance), the four annexures, and
//  Executive Summary + Submit. Read-only unless the audit is IN_PROGRESS/REOPENED.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text_formatters.dart';
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
      builder: (_) => SafeArea(
        child: pending.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('All questions complete. You can submit.'))
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Pending checklist', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                  for (final q in pending)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                      title: Text('${q.code ?? ''}  ${q.text ?? ''}',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                      subtitle: Text(_reasonFor(q), style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
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

  Widget _completionBar() {
    final p = _progress();
    final pct = p.total == 0 ? 0.0 : p.answered / p.total;
    final done = p.pending == 0 && p.applicable;
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(done ? Icons.verified_rounded : Icons.checklist_rounded,
                    size: 16, color: done ? AppColors.success : AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${p.answered}/${p.total} answered'
                      '${p.pending > 0 ? '  ·  ${p.pending} pending' : ''}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                if (p.pending > 0)
                  TextButton(
                    onPressed: _openPendingSheet,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: const Text('View pending', style: TextStyle(fontSize: 12, color: AppColors.danger)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: AppColors.muted.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(done ? AppColors.success : AppColors.primary),
              ),
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
      loading: () => const Scaffold(body: Center(child: AppLoadingBlock(height: 200))),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Audit')),
        body: AppErrorPanel(message: '$e', onRetry: () => ref.invalidate(auditExecutionProvider(widget.executionId))),
      ),
      data: (d) {
        _seed(d);
        final editable = d.isEditable;
        final tabs = <Tab>[
          const Tab(text: 'Rating'),
          for (final c in d.categories) Tab(text: c.code ?? c.name ?? '—'),
          const Tab(text: 'Center'),
          const Tab(text: 'Client'),
          const Tab(text: 'OD/NPA'),
          const Tab(text: 'Legal'),
          const Tab(text: 'Summary'),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.ink,
              title: Text(d.branchName ?? d.planCode ?? 'Audit'),
              bottom: TabBar(
                isScrollable: true,
                labelColor: AppColors.primary,
                indicatorColor: AppColors.primary,
                tabs: tabs,
              ),
            ),
            body: Column(
              children: [
                _PendingBanner(onSync: _syncNow),
                if (editable) _completionBar(),
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
            bottomNavigationBar: !editable ? null : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _saveResponses,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: _progress().pending == 0 ? AppColors.primary : AppColors.muted),
                        onPressed: _saving ? null : _submit,
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(_saving
                            ? 'Working…'
                            : (_progress().pending == 0 ? 'Submit' : 'Submit (${_progress().pending})')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
    return Material(
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$count change(s) pending sync',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
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
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        AuditScoreBar(
          label: 'Overall Score',
          score: d.finalScore,
          sub: d.grade == null ? null : 'Grade ${d.grade}',
          riskLevel: d.riskFlag,
        ),
        const SizedBox(height: 12),
        AuditSectionCard(
          title: 'Branch',
          icon: Icons.store_mall_directory_rounded,
          children: [
            AuditKeyValueRow(label: 'Branch', value: d.branchName ?? '—'),
            AuditKeyValueRow(label: 'Code', value: d.branchCode ?? '—'),
            AuditKeyValueRow(label: 'State', value: d.state ?? '—'),
            AuditKeyValueRow(label: 'Auditor', value: d.auditorName ?? '—'),
            AuditKeyValueRow(label: 'Period', value: '${d.periodFrom ?? '—'} → ${d.periodTo ?? '—'}'),
          ],
        ),
        const SizedBox(height: 12),
        AuditSectionCard(
          title: 'Managers & Statistics',
          icon: Icons.insights_rounded,
          children: [
            _field('Branch Manager', 'branchManagerName'),
            _field('Area Manager', 'areaManagerName'),
            _field('Division Manager', 'divisionManagerName'),
            _field('Total Customers', 'totalCustomers', number: true),
            _field('Total Centers', 'totalCenters', number: true),
            _field('Portfolio Outstanding', 'portfolioOutstanding', number: true),
            _field('OD Customers', 'odCustomers', number: true),
            _field('OD Amount', 'odAmount', number: true),
            _field('PAR %', 'parPercent', number: true),
            if (widget.editable) ...[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save branch details'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _field(String label, String key, {bool number = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: TextField(
          controller: _c[key],
          enabled: widget.editable,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
          inputFormatters: number ? null : const [TitleCaseTextFormatter()],
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        for (final sub in category.subsections)
          AuditSectionCard(
            title: '${sub.code ?? ''} ${sub.name ?? ''}'.trim(),
            children: [
              for (final q in sub.questions) _QuestionCard(
                q: q, editable: editable, executionId: executionId,
                answer: q.questionId == null ? null : answers[q.questionId],
                obs: q.questionId == null ? null : obs[q.questionId],
                incomplete: isIncomplete(q),
                onAnswer: (v) { if (q.questionId != null) { answers[q.questionId!] = v; onChanged(); } },
                onAttachmentChanged: onAttachmentChanged,
              ),
            ],
          ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: incomplete ? AppColors.danger.withValues(alpha: 0.55) : AppColors.hairline,
          width: incomplete ? 1.2 : 1,
        ),
        color: incomplete ? AppColors.danger.withValues(alpha: 0.04) : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('${q.code ?? ''}  ${q.text ?? ''}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ),
              if (q.mandatory)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('*', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: [
              if (q.weightage != null) _miniChip('Wt ${q.weightage}', AppColors.muted),
              if (q.riskLevel != null) _miniChip(q.riskLevel!, _riskColor(q.riskLevel!)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final opt in q.naAllowed ? const ['YES', 'NO', 'NA'] : const ['YES', 'NO'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(opt),
                    selected: answer == opt,
                    onSelected: editable ? (_) => onAnswer(answer == opt ? null : opt) : null,
                    selectedColor: opt == 'NO' ? AppColors.danger.withValues(alpha: 0.18)
                        : opt == 'YES' ? AppColors.success.withValues(alpha: 0.18)
                        : AppColors.muted.withValues(alpha: 0.18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: obs, enabled: editable, minLines: 1, maxLines: 3,
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseTextFormatter()],
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              labelText: 'Auditor observation${_needsObservation ? ' *' : ''}',
              isDense: true, border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
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
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: q.questionId == null
                      ? null
                      : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16)),
                            ),
                            builder: (_) => _QuestionAttachmentsSheet(
                              questionId: q.questionId!,
                              editable: editable,
                              onChanged: onAttachmentChanged,
                            ),
                          ),
                  child:
                      _miniChip('${q.attachmentCount} file(s) ▾', AppColors.success),
                )
              else if (_needsAttachment)
                _miniChip('required', AppColors.danger),
            ],
          ),
        ],
      ),
    );
  }

  static Color _riskColor(String r) => switch (r) {
        'HIGH' => AppColors.danger,
        'MODERATE' => AppColors.warning,
        _ => AppColors.success,
      };

  static Widget _miniChip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
      );
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Uploaded files',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (items == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No files uploaded for this question.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.attach_file_rounded,
                            size: 18, color: AppColors.muted),
                        title: Text(
                          a.fileName ?? 'File #${a.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        subtitle: a.capturedAt != null
                            ? Text(a.capturedAt!,
                                style: const TextStyle(fontSize: 10.5))
                            : null,
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
              ),
          ],
        ),
      ),
    );
  }
}

// ── Annexure tab (list + add + delete) ──────────────────────────────────────

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
        onPressed: _add, backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded), label: const Text('Add'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const AppLoadingBlock(height: 160);
          if (snap.hasError) return AppErrorPanel(message: '${snap.error}', onRetry: _refresh);
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const AppEmptyState(icon: Icons.list_alt_rounded, message: 'No entries yet. Tap Add to record one.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = rows[i];
              return GlassCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['title']?.toString() ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                          if (r['subtitle'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(r['subtitle'].toString(),
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                            ),
                        ],
                      ),
                    ),
                    if (widget.editable && r['id'] != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                        onPressed: () => _delete(r['id'] as int),
                      ),
                  ],
                ),
              );
            },
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
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add ${widget.type} entry',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final f in _fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
                  decoration: InputDecoration(labelText: _label(f), isDense: true, border: const OutlineInputBorder()),
                ),
              ),
            if (widget.type == 'od')
              DropdownButtonFormField<String>(
                initialValue: _rootCause,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Root cause', isDense: true, border: OutlineInputBorder()),
                items: [for (final rc in _odRootCauses) DropdownMenuItem(value: rc, child: Text(rc, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _rootCause = v),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
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
  String _label(String f) => f
      .replaceAllMapped(RegExp('([A-Z])'), (m) => ' ${m[1]}')
      .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
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
      padding: const EdgeInsets.all(14),
      children: [
        AuditScoreBar(
          label: 'Overall Score',
          score: d.finalScore,
          sub: d.grade == null ? null : 'Grade ${d.grade}',
          riskLevel: d.riskFlag,
        ),
        const SizedBox(height: 12),
        if ((d.executiveSummary ?? '').isNotEmpty)
          AuditSectionCard(title: 'Auto Summary', icon: Icons.summarize_rounded, children: [
            Text(d.executiveSummary!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
          ]),
        const SizedBox(height: 12),
        AuditSectionCard(title: 'Auditor Inputs', icon: Icons.edit_note_rounded, children: [
          TextField(controller: _remark, enabled: widget.editable, minLines: 2, maxLines: 5,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              decoration: const InputDecoration(labelText: 'Auditor final remark', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _action, enabled: widget.editable, minLines: 2, maxLines: 5,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              decoration: const InputDecoration(labelText: 'BM action requirement', border: OutlineInputBorder())),
          if (widget.editable) ...[
            const SizedBox(height: 10),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save summary')),
          ],
        ]),
      ],
    );
  }
}
