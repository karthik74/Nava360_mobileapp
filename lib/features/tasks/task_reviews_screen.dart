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

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'form_renderer.dart';
import 'task_models.dart';
import 'task_repository.dart';

enum _Queue { branch, mine }

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
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Task Reviews'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: _queue == null
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: AppEmptyState(icon: Icons.lock_outline_rounded, message: 'You do not have access to task reviews.'),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _future;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (canBranch && canMine) ...[
                      SegmentedButton<_Queue>(
                        segments: const [
                          ButtonSegment(value: _Queue.branch, label: Text('Branch'), icon: Icon(Icons.store_rounded, size: 16)),
                          ButtonSegment(value: _Queue.mine, label: Text('My reviews'), icon: Icon(Icons.person_rounded, size: 16)),
                        ],
                        selected: {_queue!},
                        onSelectionChanged: (s) {
                          _queue = s.first;
                          _reload();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_queue == _Queue.branch) ...[
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          hintText: 'Search employee, code or task',
                          prefixIcon: Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 400), () {
                            _q = v.trim();
                            _reload();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final v in const [('PENDING', 'Pending'), ('APPROVED', 'Approved'), ('REJECTED', 'Rejected')])
                            ChoiceChip(
                              label: Text(v.$2),
                              selected: _view == v.$1,
                              onSelected: (_) {
                                _view = v.$1;
                                _reload();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    FutureBuilder<List<TeamTaskAssignment>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snap.hasError) {
                          return AppErrorPanel(message: '${snap.error}', onRetry: _reload);
                        }
                        final rows = snap.data ?? const [];
                        if (rows.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: AppEmptyState(icon: Icons.task_alt_rounded, message: 'Nothing waiting for review.'),
                          );
                        }
                        return Column(children: [for (final a in rows) _ReviewTile(a: a, onTap: () => _open(a))]);
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

String _when(DateTime? d) => d == null ? '' : DateFormat('d MMM, h:mm a').format(d.toLocal());

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.a, required this.onTap});
  final TeamTaskAssignment a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (a.status) {
      'IN_REVIEW' => ('In review', const Color(0xFFD97706)),
      'DONE' => ('Approved', AppColors.success),
      'REJECTED' => ('Rejected', AppColors.danger),
      _ => (a.status, AppColors.muted),
    };
    final who = [a.assigneeName, a.assigneeCode].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final meta = [a.assigneeBranchName, a.templateName, a.customerName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.taskTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  if (who.isNotEmpty)
                    Text(who, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                  if (meta.isNotEmpty)
                    Text(meta, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  if (a.submittedAt != null)
                    Text('Submitted ${_when(a.submittedAt)}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ),
            ]),
          ),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final schema = task == null ? null : FormSchema.parse(task.formSchema);
    return Scaffold(
      appBar: AppBar(
        title: Text(_a.taskTitle, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0.5,
      ),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: AppErrorPanel(message: _error!, onRetry: _load))
          : task == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text([_a.assigneeName, _a.assigneeCode].whereType<String>().join(' · '),
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
                        Text(
                          [_a.assigneeBranchName, _a.templateName, _a.customerName]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                        ),
                        if (_a.submittedAt != null)
                          Text('Submitted ${_when(_a.submittedAt)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        if (_a.status == 'REJECTED' && (_a.rejectionReason ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Rejected: ${_a.rejectionReason}',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    if (_editing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Correcting the submitted details. Saving keeps the task in review.',
                            style: TextStyle(fontSize: 12.5, color: AppColors.primary)),
                      ),
                    if (schema == null)
                      const Text('This task has no form details.', style: TextStyle(color: AppColors.muted))
                    else
                      FormRenderer(
                        schema: schema,
                        values: _values,
                        readOnly: !_editing || _busy,
                        errors: _errors,
                        ownerFillsAssigned: true,
                        onChanged: (name, v) => setState(() {
                          if (v == null) {
                            _values.remove(name);
                          } else {
                            _values[name] = v;
                          }
                        }),
                      ),
                  ],
                ),
      bottomNavigationBar: task == null || !_pending
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _editing
                    ? Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _editing = false;
                                      _errors = const {};
                                      _values = parseFormValues(task.formResponse);
                                    }),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy || schema == null ? null : () => _saveEdits(schema),
                            child: Text(_busy ? 'Saving…' : 'Save changes'),
                          ),
                        ),
                      ])
                    : Row(children: [
                        if (widget.branchMode && schema != null) ...[
                          IconButton.outlined(
                            tooltip: 'Edit details',
                            onPressed: _busy ? null : () => setState(() => _editing = true),
                            icon: const Icon(Icons.edit_rounded),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
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
              ),
            ),
    );
  }
}
