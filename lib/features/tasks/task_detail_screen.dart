import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../auth/auth_controller.dart';
import 'form_renderer.dart';
import 'task_done_screen.dart';
import 'task_models.dart';
import 'task_repository.dart';
import 'task_status_ui.dart';

final taskDetailProvider =
    FutureProvider.autoDispose.family<Task, int>((ref, id) async {
  return ref.watch(taskRepositoryProvider).get(id);
});

final taskHistoryProvider =
    FutureProvider.autoDispose.family<List<TaskHistoryEntry>, int>((ref, id) {
  return ref.watch(taskRepositoryProvider).history(id);
});

final taskCommentsProvider =
    FutureProvider.autoDispose.family<List<TaskComment>, int>((ref, id) {
  return ref.watch(taskRepositoryProvider).comments(id);
});

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final int taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  FormValues _values = {};
  Map<String, String> _errors = {};
  bool _submitting = false;
  String? _topError;
  bool _hydrated = false;

  void _hydrate(Task task) {
    if (_hydrated) return;
    _values = parseFormValues(task.formResponse);
    _hydrated = true;
  }

  /// A self-task is one the employee raised for themselves: they are both the
  /// assignee and the assigner, so they must also fill the assigner-owned
  /// (`assigned: true`) form fields.
  bool _isSelfTask(Task task) {
    final me = ref.read(authUserProvider)?.employeeId;
    return me != null && task.assignedToId == me && task.assignedById == me;
  }

  /// One-shot GPS fix for geo-tagging a completion. Returns null if location is
  /// unavailable or denied — completion still proceeds without coordinates.
  Future<({double lat, double lng})?> _captureLatLng() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _markInProgress(Task task) async {
    try {
      await ref
          .read(taskRepositoryProvider)
          .updateStatus(task.id, TaskStatuses.inProgress);
      ref.invalidate(taskDetailProvider(task.id));
      ref.invalidate(taskHistoryProvider(task.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Complete the task, honouring the backend status machine
  /// (TODO → IN_PROGRESS → IN_REVIEW | DONE):
  ///
  ///  * The task is first advanced to IN_PROGRESS if it is still TODO — no
  ///    forward move other than IN_PROGRESS is allowed from TODO.
  ///  * Form tasks: submitting the form response makes the backend perform the
  ///    final transition itself (to IN_REVIEW when review is required — which
  ///    may be forced by server config — otherwise DONE). We do NOT issue a
  ///    second status update.
  ///  * Non-form tasks: we transition explicitly, geo-tagging only an outright
  ///    completion (the backend stores coordinates only for the DONE state).
  ///
  /// The resulting status comes back in the response, so the confirmation
  /// message reflects what actually happened.
  Future<void> _complete(Task task) async {
    final schema = FormSchema.parse(task.formSchema);
    if (schema != null) {
      final errors =
          validateForm(schema, _values, includeAssigned: _isSelfTask(task));
      setState(() {
        _errors = errors;
        _topError = errors.isEmpty ? null : 'Please fix the highlighted fields.';
      });
      if (errors.isNotEmpty) return;
    }

    setState(() {
      _submitting = true;
      _topError = null;
    });
    try {
      final repo = ref.read(taskRepositoryProvider);

      // Capture a single GPS fix up front and geo-tag whichever call performs
      // the completion. Best-effort — completion still proceeds without it.
      final loc = await _captureLatLng();

      // From TODO the only legal forward transition is IN_PROGRESS.
      if (task.status == TaskStatuses.todo) {
        await repo.updateStatus(task.id, TaskStatuses.inProgress);
      }

      final Task result;
      if (schema != null) {
        final FormValues pruned = {};
        for (final f in schema.fields) {
          if (isFieldVisible(f, _values) && _values.containsKey(f.name)) {
            pruned[f.name] = _values[f.name];
          }
        }
        // form-response performs the final transition (IN_REVIEW or DONE) and
        // records the submission coordinates.
        result = await repo.submitFormResponse(
          task.id,
          jsonEncode(pruned),
          lat: loc?.lat,
          lng: loc?.lng,
        );
      } else {
        final target =
            task.requiresReview ? TaskStatuses.inReview : TaskStatuses.done;
        result = await repo.updateStatus(
          task.id,
          target,
          lat: loc?.lat,
          lng: loc?.lng,
        );
      }

      if (!mounted) return;
      ref.invalidate(taskDetailProvider(task.id));
      ref.invalidate(taskHistoryProvider(task.id));

      final wentToReview = result.status == TaskStatuses.inReview;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TaskDoneScreen(
            taskTitle: task.title,
            message: wentToReview
                ? 'Submitted for review. Your reviewer will be notified.'
                : 'Marked as Done. You can review submitted answers from the task list.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _topError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(widget.taskId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Task'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0.5,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(e.toString())),
        ),
        data: (task) {
          _hydrate(task);
          final schema = FormSchema.parse(task.formSchema);
          final readOnly = !task.isActionable || _submitting;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(task: task),
              const SizedBox(height: 16),
              _MetaGrid(task: task),
              if (task.description != null &&
                  task.description!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _SectionLabel('Description'),
                const SizedBox(height: 6),
                Text(
                  task.description!,
                  style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
                ),
              ],
              if (task.completionAddress != null &&
                  task.completionAddress!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Completed at',
                  value: task.completionAddress!,
                ),
              ],
              const SizedBox(height: 20),
              const _SectionLabel('Submission'),
              const SizedBox(height: 10),
              if (schema == null)
                Text(
                  task.isActionable
                      ? 'This task has no form. Mark it done when finished.'
                      : 'This task has no form.',
                  style: const TextStyle(color: AppColors.muted),
                )
              else
                FormRenderer(
                  schema: schema,
                  values: _values,
                  readOnly: readOnly,
                  errors: _errors,
                  ownerFillsAssigned: _isSelfTask(task),
                  onChanged: (name, v) {
                    setState(() {
                      if (v == null) {
                        _values.remove(name);
                      } else {
                        _values[name] = v;
                      }
                      _errors.remove(name);
                    });
                  },
                ),
              const SizedBox(height: 16),
              if (_topError != null) _TopBanner(message: _topError!),
              const SizedBox(height: 4),
              _ActionArea(
                task: task,
                schema: schema,
                submitting: _submitting,
                onStart: () => _markInProgress(task),
                onComplete: () => _complete(task),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('Activity'),
              const SizedBox(height: 10),
              _HistorySection(taskId: task.id),
              const SizedBox(height: 24),
              const _SectionLabel('Comments'),
              const SizedBox(height: 10),
              _CommentsSection(taskId: task.id),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────────────── Action area ─────────────────────────────

class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.task,
    required this.schema,
    required this.submitting,
    required this.onStart,
    required this.onComplete,
  });

  final Task task;
  final FormSchema? schema;
  final bool submitting;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    if (task.isInReview) {
      return const _StatusBanner(
        icon: Icons.rate_review_outlined,
        color: AppColors.accent,
        text: 'Awaiting review. Your submission is with the reviewer.',
      );
    }
    if (task.isClosed) {
      final (icon, color, text) = switch (task.status) {
        TaskStatuses.done => (
            Icons.check_circle_rounded,
            AppColors.success,
            'This task is complete.'
          ),
        TaskStatuses.rejected => (
            Icons.cancel_rounded,
            AppColors.danger,
            'This task was rejected. Check the activity log for the reason.'
          ),
        _ => (Icons.block_rounded, AppColors.muted, 'This task was cancelled.'),
      };
      return _StatusBanner(icon: icon, color: color, text: text);
    }

    // Form tasks: the backend decides review-vs-done on submit (server config
    // can force review), so keep the label neutral. Non-form tasks transition
    // exactly as the task config dictates.
    final completeLabel = schema != null
        ? 'Submit'
        : (task.requiresReview ? 'Submit for review' : 'Mark done');

    return Row(
      children: [
        if (task.status == TaskStatuses.todo) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: submitting ? null : onStart,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Start'),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: FilledButton(
            onPressed: submitting ? null : onComplete,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(completeLabel),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────── Header ────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task.taskCode != null && task.taskCode!.isNotEmpty)
          Text(
            task.taskCode!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
              letterSpacing: 0.4,
            ),
          ),
        const SizedBox(height: 2),
        Text(
          task.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TaskStatusPill(status: task.status, dense: false),
            if (task.priority != null)
              _Chip(
                label: humanizeEnum(task.priority!),
                color: priorityColor(task.priority!),
                icon: Icons.flag_rounded,
              ),
            if (task.categoryName != null)
              _Chip(
                label: task.categoryName!,
                color: AppColors.primary,
                icon: Icons.folder_open_rounded,
              ),
          ],
        ),
      ],
    );
  }
}

class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final due = task.dueDate == null
        ? null
        : DateFormat('EEE, d MMM y').format(task.dueDate!);
    final dueTime = formatDueTime(task.dueTime);
    final rows = <Widget>[
      if (task.customerName != null && task.customerName!.isNotEmpty)
        _InfoRow(
          icon: Icons.badge_outlined,
          label: 'Customer',
          value: task.customerName!,
        ),
      if (task.assignedByName != null)
        _InfoRow(
          icon: Icons.person_outline,
          label: 'Assigned by',
          value: task.assignedByName!,
        ),
      if (task.reviewerName != null)
        _InfoRow(
          icon: Icons.verified_user_outlined,
          label: 'Reviewer',
          value: task.reviewerName!,
        ),
      if (due != null)
        _InfoRow(
          icon: Icons.event_outlined,
          label: 'Due',
          value: dueTime != null ? '$due · $dueTime' : due,
        ),
      if (task.estimatedHours != null)
        _InfoRow(
          icon: Icons.schedule_outlined,
          label: 'Estimated',
          value: '${_trimNum(task.estimatedHours!)} h',
        ),
      if (task.completionPercentage > 0 && !task.isDone)
        _InfoRow(
          icon: Icons.donut_large_outlined,
          label: 'Progress',
          value: '${task.completionPercentage}%',
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.muted.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.muted.withOpacity(0.12)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: rows[i],
            ),
          ],
        ],
      ),
    );
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.muted),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────── History ────────────────────────────────

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.taskId});
  final int taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taskHistoryProvider(taskId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, __) => const Text(
        'Could not load activity.',
        style: TextStyle(color: AppColors.muted, fontSize: 12.5),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const Text(
            'No activity yet.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < entries.length; i++)
              _HistoryTile(entry: entries[i], isLast: i == entries.length - 1),
          ],
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.isLast});
  final TaskHistoryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = entry.isStatusChange && entry.newStatus != null
        ? statusColor(entry.newStatus!)
        : AppColors.muted;
    final when = entry.createdAt == null
        ? ''
        : DateFormat('d MMM, h:mm a').format(entry.createdAt!.toLocal());

    final String title;
    if (entry.isStatusChange) {
      final from = entry.oldStatus == null || entry.oldStatus!.isEmpty
          ? null
          : humanizeEnum(entry.oldStatus!);
      final to = humanizeEnum(entry.newStatus ?? '');
      title = from == null ? 'Set to $to' : '$from → $to';
    } else {
      title = 'Updated ${humanizeEnum(entry.changedField ?? 'task')}';
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.muted.withOpacity(0.18),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (entry.changedByName != null) entry.changedByName!,
                      if (when.isNotEmpty) when,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                  if (entry.changeReason != null &&
                      entry.changeReason!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.changeReason!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkSoft,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────── Comments ───────────────────────────────

class _CommentsSection extends ConsumerStatefulWidget {
  const _CommentsSection({required this.taskId});
  final int taskId;

  @override
  ConsumerState<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<_CommentsSection> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(taskRepositoryProvider).addComment(widget.taskId, text);
      _controller.clear();
      ref.invalidate(taskCommentsProvider(widget.taskId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post comment: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskCommentsProvider(widget.taskId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (_, __) => const Text(
            'Could not load comments.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          data: (comments) {
            if (comments.isEmpty) {
              return const Text(
                'No comments yet.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              );
            }
            return Column(
              children: [for (final c in comments) _CommentTile(comment: c)],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Add a comment…',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide:
                        BorderSide(color: AppColors.muted.withOpacity(0.25)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide:
                        BorderSide(color: AppColors.muted.withOpacity(0.25)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final TaskComment comment;

  @override
  Widget build(BuildContext context) {
    final initials = (comment.employeeName ?? '?')
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();
    final when = comment.createdAt == null
        ? ''
        : DateFormat('d MMM, h:mm a').format(comment.createdAt!.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withOpacity(0.12),
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.employeeName ?? 'Someone',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.commentText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkSoft,
                    height: 1.35,
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

// ─────────────────────────────── Small widgets ─────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: AppColors.muted,
      ),
    );
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
