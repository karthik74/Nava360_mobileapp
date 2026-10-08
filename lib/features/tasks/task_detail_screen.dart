import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
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

String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Label of the completion button. Form tasks: the backend decides
/// review-vs-done on submit (server config can force review), so keep the
/// label neutral. Non-form tasks transition exactly as the task config
/// dictates.
String _completeLabel(Task task, FormSchema? schema) => schema != null
    ? 'Submit'
    : (task.requiresReview ? 'Submit for review' : 'Mark done');

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

  /// Hero quick actions jump to these sections.
  final _activityKey = GlobalKey();
  final _commentsKey = GlobalKey();

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

  /// Why the last [_captureLatLng] call produced no fix, for the blocking dialog.
  String? _locationFailure;

  /// One-shot GPS fix for geo-tagging a completion. When the task's template
  /// makes location mandatory the backend refuses a submission without one, so
  /// a null here aborts the completion and [_locationFailure] explains what to
  /// fix; otherwise the completion simply goes ahead untagged.
  Future<({double lat, double lng})?> _captureLatLng() async {
    _locationFailure = null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locationFailure =
            'Location services are turned off. Turn on GPS / location and try again.';
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _locationFailure =
            'Location permission is denied. Allow location access for this app in Settings and try again.';
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      _locationFailure =
          'Could not get a GPS fix. Move to open sky, check that GPS is on, and try again.';
      return null;
    }
  }

  /// Blocking explanation shown when a completion was refused for lack of a fix.
  Future<void> _showLocationRequired() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location required'),
        content: Text(
          'Completing a task must record where you are.\n\n'
          '${_locationFailure ?? 'Your location could not be determined.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      // the completion. Mandatory only when the template says so — then the
      // backend refuses a submission without it, so stop here (before any
      // status change) and tell the employee why. Otherwise best-effort.
      final loc = await _captureLatLng();
      if (loc == null && task.completionLocationRequired) {
        if (!mounted) return;
        setState(() => _submitting = false);
        await _showLocationRequired();
        return;
      }

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

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  /// Action buttons are offered while the task is neither in review nor closed.
  bool _hasActions(Task task) => !task.isInReview && !task.isClosed;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(widget.taskId));
    final loaded = async.valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Task')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(taskDetailProvider(widget.taskId)),
            ),
          ),
        ),
        data: (task) {
          _hydrate(task);
          final schema = FormSchema.parse(task.formSchema);
          final readOnly = !task.isActionable || _submitting;
          // Assigned to one of this employee's reportees: the reporting
          // manager is performing it on the assignee's behalf.
          final onBehalf =
              task.isOnBehalfFor(ref.read(authUserProvider)?.employeeId);
          final required = _requiredProgress(task, schema);

          return ProPage(
            hero: _hero(task, schema, required),
            children: [
              ..._details(task, showAssignee: onBehalf),
              if (onBehalf && task.isActionable)
                ProNote(
                  'Assigned to ${task.assignedToName ?? 'your reportee'}, who '
                  'reports to you. As their reporting manager you can complete '
                  'it on their behalf — whoever submits first completes it.',
                  tone: ProNoteTone.info,
                  icon: Icons.groups_outlined,
                ),
              ProSectionHeader(
                title: required == null
                    ? 'Submission'
                    : 'Submission · ${required.$1} of ${required.$2} required done',
                small: true,
              ),
              if (schema == null)
                GlassCard(
                  child: Row(
                    children: [
                      const ProIconWell(icon: Icons.task_alt_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          task.isActionable
                              ? 'This task has no form. Mark it done when finished.'
                              : 'This task has no form.',
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                )
              else
                FormRenderer(
                  schema: schema,
                  values: _values,
                  readOnly: readOnly,
                  errors: _errors,
                  ownerFillsAssigned: _isSelfTask(task),
                  sectionCards: true,
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
              if (_topError != null && !_hasActions(task))
                ProNote(_topError!, tone: ProNoteTone.bad),
              if (!_hasActions(task)) _StateNote(task: task),
              KeyedSubtree(
                key: _activityKey,
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Activity'),
                      const SizedBox(height: 12),
                      _HistorySection(taskId: task.id),
                    ],
                  ),
                ),
              ),
              KeyedSubtree(
                key: _commentsKey,
                child: _CommentsSection(taskId: task.id),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: loaded == null || !_hasActions(loaded)
          ? null
          : _ActionBar(
              task: loaded,
              schema: FormSchema.parse(loaded.formSchema),
              submitting: _submitting,
              error: _topError,
              onStart: () => _markInProgress(loaded),
              onComplete: () => _complete(loaded),
            ),
    );
  }

  /// `(done, total)` required fields the assignee still has to fill, or null
  /// when the task takes no input (no form, nothing required, or not open).
  (int, int)? _requiredProgress(Task task, FormSchema? schema) {
    if (schema == null || !task.isActionable) return null;
    final self = _isSelfTask(task);
    final req = schema.fields
        .where((f) =>
            isFieldVisible(f, _values) &&
            f.required &&
            !(f.assigned && !self) &&
            !f.readOnly &&
            !f.type.isLayout &&
            !f.type.isSystem)
        .toList();
    if (req.isEmpty) return null;
    final errors = validateForm(schema, _values, includeAssigned: self);
    final done = req.where((f) => errors[f.name] != 'Required').length;
    return (done, req.length);
  }

  Widget _hero(Task task, FormSchema? schema, (int, int)? required) {
    final due = task.dueDate;
    final dueTime = formatDueTime(task.dueTime);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = due == null ? null : DateTime(due.year, due.month, due.day);
    final overdue = dueDay != null && dueDay.isBefore(today) && !task.isClosed;

    final role = [
      if (task.customerName != null && task.customerName!.isNotEmpty)
        task.customerName!,
      if (task.taskCode != null && task.taskCode!.isNotEmpty) task.taskCode!,
    ].join(' · ');

    final priority = task.priority;
    final kpis = <ProKpi>[
      if (due != null)
        ProKpi(
          value: dueTime ?? DateFormat('d MMM').format(due),
          label: dueTime != null
              ? 'Due ${DateFormat('d MMM').format(due)}'
              : 'Due date',
          valueColor: overdue ? AppColors.danger : null,
        ),
      if (task.estimatedHours != null)
        ProKpi(value: '${_trimNum(task.estimatedHours!)} h', label: 'Estimated'),
      if (required != null)
        ProKpi(
          value: '${required.$1} / ${required.$2}',
          label: 'Required done',
          progress: required.$1 / required.$2,
          color: required.$1 == required.$2 ? AppColors.live : null,
        ),
      if (task.completionPercentage > 0 && !task.isDone)
        ProKpi(
          value: '${task.completionPercentage}%',
          label: 'Progress',
          progress: task.completionPercentage / 100,
        ),
    ].take(3).toList();

    final live = _liveLine(task, dueDay, today, dueTime);

    return ProHero(
      overlap: kpis.isEmpty ? null : ProKpiStrip(cells: kpis),
      children: [
        ProHeroIdentity(
          name: task.title,
          role: role.isEmpty ? null : role,
          icon: task.isDone
              ? Icons.task_alt_rounded
              : (task.isCustomerTask
                  ? Icons.storefront_outlined
                  : Icons.assignment_outlined),
          tags: [
            ProHeroTag(statusLabel(task.status),
                tone: taskStatusTagTone(task.status)),
            if (priority != null)
              ProHeroTag(
                humanizeEnum(priority),
                icon: Icons.flag_rounded,
                tone: switch (priority.toUpperCase()) {
                  'URGENT' => ProTagTone.bad,
                  'HIGH' => ProTagTone.warn,
                  _ => ProTagTone.neutral,
                },
              ),
            if (task.categoryName != null)
              ProHeroTag(task.categoryName!, icon: Icons.folder_open_rounded),
          ],
        ),
        if (live != null) ProLiveLine(text: live.$1, color: live.$2),
        ProHeroActions(
          actions: [
            if (_hasActions(task) && task.status == TaskStatuses.todo)
              ProAction(
                icon: Icons.play_arrow_rounded,
                label: 'Start',
                primary: true,
                onTap: _submitting ? null : () => _markInProgress(task),
              ),
            if (_hasActions(task))
              ProAction(
                icon: Icons.check_rounded,
                label: _completeLabel(task, schema),
                primary: task.status != TaskStatuses.todo,
                onTap: _submitting ? null : () => _complete(task),
              ),
            ProAction(
              icon: Icons.history_rounded,
              label: 'Activity',
              onTap: () => _jumpTo(_activityKey),
            ),
            ProAction(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Comments',
              onTap: () => _jumpTo(_commentsKey),
            ),
          ],
        ),
      ],
    );
  }

  /// One-line status for the hero, built from the task's own dates.
  (String, Color)? _liveLine(
      Task task, DateTime? dueDay, DateTime today, String? dueTime) {
    if (task.isInReview) {
      return (
        task.reviewerName != null
            ? 'Awaiting review by ${task.reviewerName}'
            : 'Awaiting review',
        const Color(0xFFF2B347),
      );
    }
    if (task.isDone) {
      final at = task.completedAt;
      return (
        at == null
            ? 'Completed'
            : 'Completed ${DateFormat('d MMM, h:mm a').format(at.toLocal())}',
        AppColors.live,
      );
    }
    if (task.status == TaskStatuses.rejected) {
      return ('Rejected · see the activity below', const Color(0xFFE5484D));
    }
    if (task.status == TaskStatuses.cancelled) {
      return ('Cancelled', Colors.white54);
    }
    if (dueDay == null) return null;
    final time = dueTime == null ? '' : ', $dueTime';
    final day = DateFormat('EEE, d MMM').format(dueDay);
    if (dueDay.isBefore(today)) {
      return ('Overdue · was due $day$time', const Color(0xFFE5484D));
    }
    if (dueDay == today) return ('Due today$time', const Color(0xFFF2B347));
    return ('Due $day$time', AppColors.live);
  }

  /// Details card: description and the task's key facts.
  List<Widget> _details(Task task, {required bool showAssignee}) {
    final due = task.dueDate == null
        ? null
        : DateFormat('EEE, d MMM y').format(task.dueDate!);
    final dueTime = formatDueTime(task.dueTime);
    final rows = <MapEntry<String, String>>[
      if (showAssignee && task.assignedToName != null)
        MapEntry('Assigned to', task.assignedToName!),
      if (task.customerName != null && task.customerName!.isNotEmpty)
        MapEntry('Customer', task.customerName!),
      if (task.assignedByName != null)
        MapEntry('Assigned by', task.assignedByName!),
      if (task.reviewerName != null) MapEntry('Reviewer', task.reviewerName!),
      if (due != null) MapEntry('Due', dueTime != null ? '$due · $dueTime' : due),
      if (task.estimatedHours != null)
        MapEntry('Estimated', '${_trimNum(task.estimatedHours!)} h'),
      if (task.completionPercentage > 0 && !task.isDone)
        MapEntry('Progress', '${task.completionPercentage}%'),
      if (task.completionAddress != null && task.completionAddress!.isNotEmpty)
        MapEntry('Completed at', task.completionAddress!),
    ];
    final hasDescription =
        task.description != null && task.description!.isNotEmpty;
    // The hero clamps the title to two lines; repeat a long one in full here.
    final longTitle = task.title.length > 44;
    if (rows.isEmpty && !hasDescription && !longTitle) return const [];
    return [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ProSectionHeader(title: 'Details'),
            if (longTitle) ...[
              const SizedBox(height: 8),
              Text(
                task.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: AppColors.ink,
                ),
              ),
            ],
            if (hasDescription) ...[
              const SizedBox(height: 8),
              Text(
                task.description!,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.inkSoft,
                  height: 1.45,
                ),
              ),
            ],
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 6),
              ProKeyValue(rows: rows),
            ],
          ],
        ),
      ),
    ];
  }
}

// ───────────────────────────────── Action bar ──────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.task,
    required this.schema,
    required this.submitting,
    required this.onStart,
    required this.onComplete,
    this.error,
  });

  final Task task;
  final FormSchema? schema;
  final bool submitting;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return ProBottomBar(
      top: error == null ? null : ProNote(error!, tone: ProNoteTone.bad),
      children: [
        if (task.status == TaskStatuses.todo)
          OutlinedButton.icon(
            onPressed: submitting ? null : onStart,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Start'),
          ),
        FilledButton(
          onPressed: submitting ? null : onComplete,
          child: submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(_completeLabel(task, schema)),
        ),
      ],
    );
  }
}

/// Where the task stands once it is in review or closed.
class _StateNote extends StatelessWidget {
  const _StateNote({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    if (task.isInReview) {
      return const ProNote(
        'Awaiting review. Your submission is with the reviewer.',
        tone: ProNoteTone.info,
        icon: Icons.rate_review_outlined,
      );
    }
    if (task.isClosed) {
      final (icon, tone, text) = switch (task.status) {
        TaskStatuses.done => (
            Icons.check_circle_rounded,
            ProNoteTone.ok,
            'This task is complete.'
          ),
        TaskStatuses.rejected => (
            Icons.cancel_rounded,
            ProNoteTone.bad,
            'This task was rejected. Check the activity log for the reason.'
          ),
        _ => (
            Icons.block_rounded,
            ProNoteTone.neutral,
            'This task was cancelled.'
          ),
      };
      return ProNote(text, tone: tone, icon: icon);
    }
    return const SizedBox.shrink();
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
        style: TextStyle(color: AppColors.muted, fontSize: 13.5),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const Text(
            'No activity yet.',
            style: TextStyle(color: AppColors.muted, fontSize: 13.5),
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
        ? taskStatusDot(entry.newStatus!)
        : const Color(0xFFB3C0C3);
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
          SizedBox(
            width: 14,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: color, spreadRadius: 1)],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: AppColors.hairline,
                    ),
                  ),
              ],
            ),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (entry.changedByName != null) entry.changedByName!,
                      if (when.isNotEmpty) when,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (entry.changeReason != null &&
                      entry.changeReason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        entry.changeReason!,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: AppColors.inkSoft,
                        ),
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
    final count = async.valueOrNull?.length ?? 0;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: 'Comments',
            trailing: count == 0 ? null : ProPill.neutral('$count'),
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (_, __) => const Text(
              'Could not load comments.',
              style: TextStyle(color: AppColors.muted, fontSize: 13.5),
            ),
            data: (comments) {
              if (comments.isEmpty) {
                return const Text(
                  'No comments yet.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13.5),
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
                  decoration: const InputDecoration(
                    hintText: 'Add a comment…',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Post comment',
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(46, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
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
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final TaskComment comment;

  @override
  Widget build(BuildContext context) {
    final when = comment.createdAt == null
        ? ''
        : DateFormat('d MMM, h:mm a').format(comment.createdAt!.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProAvatar(name: comment.employeeName ?? '?', size: 34),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.faint,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.commentText,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkSoft,
                    height: 1.4,
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
