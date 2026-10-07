// ─────────────────────────────────────────────────────────────────────────────
//  Task Reviews — route /tasks/reviews (HRMS menu, mirrors web /tasks/branch-review
//  and /tasks/pending-review).
//
//  Two queues, each shown only when the user holds its permission:
//   * Branch (TASK_REVIEW_BRANCH) — review-required submissions of every
//     employee in the reviewer's branches; the reviewer may correct the
//     submitted details before approving or rejecting.
//   * Mine (TASK_REVIEW) — tasks naming the user as reviewer, plus their
//     reportees' tasks on templates with "show review to hierarchy" on.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'form_renderer.dart';
import 'task_models.dart';
import 'task_repository.dart';

enum _Queue { branch, mine }

/// Branch review views (server value, label).
const _kViews = [('PENDING', 'Pending'), ('APPROVED', 'Approved'), ('REJECTED', 'Rejected')];

class TaskReviewsScreen extends ConsumerStatefulWidget {
  const TaskReviewsScreen({super.key});

  @override
  ConsumerState<TaskReviewsScreen> createState() => _TaskReviewsScreenState();
}

class _TaskReviewsScreenState extends ConsumerState<TaskReviewsScreen> {
  _Queue? _queue;
  String _view = 'PENDING';
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  late Future<List<TeamTaskAssignment>> _future;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authUserProvider);
    _queue = (user?.hasPermission('TASK_REVIEW_BRANCH') ?? false)
        ? _Queue.branch
        : ((user?.hasPermission('TASK_REVIEW') ?? false) ? _Queue.mine : null);
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<List<TeamTaskAssignment>> _load() {
    final repo = ref.read(taskRepositoryProvider);
    return switch (_queue) {
      _Queue.branch => repo.branchReview(view: _view, q: _q),
      _Queue.mine => repo.pendingReview(),
      null => Future.value(const []),
    };
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open(TeamTaskAssignment a) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TaskReviewDetailScreen(assignment: a, branchMode: _queue == _Queue.branch),
    ));
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canBranch = user?.hasPermission('TASK_REVIEW_BRANCH') ?? false;
    final canMine = user?.hasPermission('TASK_REVIEW') ?? false;
    final branch = _queue == _Queue.branch;
    final viewIndex = _kViews.indexWhere((v) => v.$1 == _view);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Task reviews')),
      body: _queue == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: AppEmptyState(icon: Icons.lock_outline_rounded, message: 'You do not have access to task reviews.'),
            )
          : ProPage(
              onRefresh: () async {
                _reload();
                await _future;
              },
              hero: ProHero(
                title: branch ? 'Branch reviews' : 'My reviews',
                subtitle: branch
                    ? 'Submissions from employees in your branches'
                    : 'Tasks waiting on your review',
                overlap: branch
                    ? ProSearchField(
                        raised: true,
                        controller: _search,
                        hint: 'Search employee, code or task',
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 400), () {
                            _q = v.trim();
                            _reload();
                          });
                        },
                      )
                    : null,
                children: [
                  if (canBranch && canMine)
                    ProHeroSegmented(
                      labels: const ['Branch', 'My reviews'],
                      icons: const [Icons.store_rounded, Icons.person_rounded],
                      selected: branch ? 0 : 1,
                      onChanged: (i) {
                        _queue = i == 0 ? _Queue.branch : _Queue.mine;
                        _reload();
                      },
                    ),
                ],
              ),
              children: [
                if (branch)
                  ProChipBar(
                    labels: [for (final v in _kViews) v.$2],
                    selected: viewIndex < 0 ? 0 : viewIndex,
                    onSelected: (i) {
                      _view = _kViews[i].$1;
                      _reload();
                    },
                    bleed: 0,
                  ),
                FutureBuilder<List<TeamTaskAssignment>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const AppLoadingBlock(height: 140);
                    }
                    if (snap.hasError) {
                      return AppErrorPanel(message: '${snap.error}', onRetry: _reload);
                    }
                    final rows = snap.data ?? const [];
                    if (rows.isEmpty) {
                      return const ProEmpty(
                        icon: Icons.task_alt_rounded,
                        title: 'Nothing waiting for review.',
                      );
                    }
                    final label = branch
                        ? (viewIndex < 0 ? _view : _kViews[viewIndex].$2)
                        : 'Waiting for you';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ProSectionHeader(title: '$label · ${rows.length}', small: true),
                        const SizedBox(height: 10),
                        ProListGroup(
                          dividerIndent: 64,
                          children: [for (final a in rows) _ReviewTile(a: a, onTap: () => _open(a))],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }
}

String _when(DateTime? d) => d == null ? '' : DateFormat('d MMM, h:mm a').format(d.toLocal());

/// Status label + Pro pill for a review row.
ProPill _reviewPill(String status) => switch (status) {
      'IN_REVIEW' => ProPill.warn('In review'),
      'DONE' => ProPill.ok('Approved'),
      'REJECTED' => ProPill.bad('Rejected'),
      _ => ProPill.neutral(status),
    };

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.a, required this.onTap});
  final TeamTaskAssignment a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final who = [a.assigneeName, a.assigneeCode].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final meta = [a.assigneeBranchName, a.templateName, a.customerName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    final sub = [who, meta].where((s) => s.isNotEmpty).join(' · ');
    return ProListRow(
      leading: ProAvatar(name: a.assigneeName ?? a.taskTitle, size: 40),
      title: a.taskTitle,
      titleMaxLines: 2,
      subtitle: sub.isEmpty ? null : sub,
      meta: a.submittedAt != null ? 'Submitted ${_when(a.submittedAt)}' : null,
      pill: _reviewPill(a.status),
      onTap: onTap,
    );
  }
}

/// One submission: the filled form, and — while it is in review — Approve / Reject,
/// plus Edit details on the branch desk.
class TaskReviewDetailScreen extends ConsumerStatefulWidget {
  const TaskReviewDetailScreen({super.key, required this.assignment, required this.branchMode});
  final TeamTaskAssignment assignment;
  final bool branchMode;

  @override
  ConsumerState<TaskReviewDetailScreen> createState() => _TaskReviewDetailScreenState();
}

class _TaskReviewDetailScreenState extends ConsumerState<TaskReviewDetailScreen> {
  Task? _task;
  String? _error;
  FormValues _values = {};
  Map<String, String> _errors = const {};
  bool _editing = false;
  bool _busy = false;

  TeamTaskAssignment get _a => widget.assignment;
  bool get _pending => _a.status == 'IN_REVIEW';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _a.taskId;
    if (id == null) {
      setState(() => _error = 'This submission has no task.');
      return;
    }
    try {
      final t = await ref.read(taskRepositoryProvider).get(id);
      if (!mounted) return;
      setState(() {
        _task = t;
        _values = parseFormValues(t.formResponse);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  Future<String?> _ask({required String title, required String hint, required bool required}) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (required && ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _toast(done);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final repo = ref.read(taskRepositoryProvider);
    if (widget.branchMode) {
      final remarks = await _ask(title: 'Approve submission', hint: 'Remarks (optional)', required: false);
      if (remarks == null) return;
      await _run(() => repo.branchApprove(_a.id, remarks: remarks), 'Approved');
    } else {
      await _run(() => repo.approveAssignment(_a.id), 'Approved');
    }
  }

  Future<void> _reject() async {
    final reason = await _ask(title: 'Reject submission', hint: 'Why is it being rejected?', required: true);
    if (reason == null || reason.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    await _run(
      () => widget.branchMode ? repo.branchReject(_a.id, reason) : repo.rejectAssignment(_a.id, reason),
      'Rejected — the employee has been notified.',
    );
  }

  Future<void> _saveEdits(FormSchema schema) async {
    final errors = validateForm(schema, _values, includeAssigned: true);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      _toast('Please fix the highlighted fields.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final json = jsonEncode(_values);
      await ref.read(taskRepositoryProvider).branchUpdateForm(_a.id, json);
      if (!mounted) return;
      setState(() => _editing = false);
      _toast('Details updated — approve or reject when ready.');
    } catch (e) {
      if (mounted) _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _hero() {
    final who = [_a.assigneeName, _a.assigneeCode].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final (label, tone, dot) = switch (_a.status) {
      'IN_REVIEW' => ('In review', ProTagTone.warn, const Color(0xFFF2B347)),
      'DONE' => ('Approved', ProTagTone.ok, AppColors.live),
      'REJECTED' => ('Rejected', ProTagTone.bad, const Color(0xFFE5484D)),
      _ => (_a.status, ProTagTone.neutral, Colors.white54),
    };
    return ProHero(
      children: [
        ProHeroIdentity(
          name: _a.taskTitle,
          role: who.isEmpty ? null : who,
          icon: Icons.fact_check_outlined,
          tags: [
            ProHeroTag(label, tone: tone),
            if (_a.templateName != null && _a.templateName!.isNotEmpty)
              ProHeroTag(_a.templateName!, icon: Icons.description_outlined),
          ],
        ),
        if (_a.submittedAt != null)
          ProLiveLine(text: 'Submitted ${_when(_a.submittedAt)}', color: dot),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final schema = task == null ? null : FormSchema.parse(task.formSchema);
    final summary = <MapEntry<String, String>>[
      if ((_a.assigneeName ?? '').isNotEmpty) MapEntry('Employee', _a.assigneeName!),
      if ((_a.assigneeCode ?? '').isNotEmpty) MapEntry('Employee code', _a.assigneeCode!),
      if ((_a.assigneeBranchName ?? '').isNotEmpty) MapEntry('Branch', _a.assigneeBranchName!),
      if ((_a.templateName ?? '').isNotEmpty) MapEntry('Form', _a.templateName!),
      if ((_a.customerName ?? '').isNotEmpty) MapEntry('Customer', _a.customerName!),
      if (_a.submittedAt != null) MapEntry('Submitted', _when(_a.submittedAt)),
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Review')),
      body: ProPage(
        hero: _hero(),
        children: [
          if (_error != null)
            AppErrorPanel(message: _error!, onRetry: _load)
          else if (task == null)
            const AppLoadingBlock(height: 160)
          else ...[
            if (summary.isNotEmpty)
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Submission'),
                    const SizedBox(height: 6),
                    ProKeyValue(rows: summary),
                  ],
                ),
              ),
            if (_a.status == 'REJECTED' && (_a.rejectionReason ?? '').isNotEmpty)
              ProNote('Rejected: ${_a.rejectionReason}', tone: ProNoteTone.bad),
            if (_editing)
              const ProNote(
                'Correcting the submitted details. Saving keeps the task in review.',
                tone: ProNoteTone.info,
                icon: Icons.edit_note_rounded,
              ),
            const ProSectionHeader(title: 'Submitted answers', small: true),
            if (schema == null)
              const GlassCard(
                child: Text('This task has no form details.',
                    style: TextStyle(fontSize: 14, color: AppColors.muted)),
              )
            else
              FormRenderer(
                schema: schema,
                values: _values,
                readOnly: !_editing || _busy,
                errors: _errors,
                ownerFillsAssigned: true,
                sectionCards: true,
                onChanged: (name, v) => setState(() {
                  if (v == null) {
                    _values.remove(name);
                  } else {
                    _values[name] = v;
                  }
                }),
              ),
          ],
        ],
      ),
      bottomNavigationBar: task == null || !_pending
          ? null
          : _editing
              ? ProBottomBar(children: [
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _editing = false;
                              _errors = const {};
                              _values = parseFormValues(task.formResponse);
                            }),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _busy || schema == null ? null : () => _saveEdits(schema),
                    child: Text(_busy ? 'Saving…' : 'Save changes'),
                  ),
                ])
              : _DecisionBar(children: [
                  if (widget.branchMode && schema != null) ...[
                    IconButton.outlined(
                      tooltip: 'Edit details',
                      onPressed: _busy ? null : () => setState(() => _editing = true),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: Color(0xFFD4DEE0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.dangerTint,
                        foregroundColor: AppColors.danger,
                      ),
                      onPressed: _busy ? null : _reject,
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _approve,
                      child: const Text('Approve'),
                    ),
                  ),
                ]),
    );
  }
}

/// Sticky bottom bar in the [ProBottomBar] style whose children size
/// themselves (an icon button next to two expanded buttons).
class _DecisionBar extends StatelessWidget {
  const _DecisionBar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0F4F6F6),
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: children),
        ),
      ),
    );
  }
}
