import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../team/team_models.dart';
import '../team/team_repository.dart';
import 'task_detail_screen.dart';
import 'task_models.dart';
import 'task_repository.dart';
import 'task_status_ui.dart';

/// Every open + recently finished assignment of the manager's team (server
/// scopes to the reporting hierarchy / assigned branches).
final _teamTasksProvider =
    FutureProvider.autoDispose<List<TeamTaskAssignment>>((ref) {
  return ref.watch(taskRepositoryProvider).teamTasks();
});

final _teamMembersProvider =
    FutureProvider.autoDispose<List<TeamMember>>((ref) {
  return ref.watch(teamRepositoryProvider).myTeam();
});

/// Status buckets shown as segments: what still needs doing, what is being
/// worked on (incl. awaiting review), and what is finished.
enum _Bucket { pending, inProgress, done }

extension on _Bucket {
  String get label => switch (this) {
        _Bucket.pending => 'Pending',
        _Bucket.inProgress => 'In progress',
        _Bucket.done => 'Done',
      };

  bool matches(String status) => switch (this) {
        _Bucket.pending => status == TaskStatuses.todo,
        _Bucket.inProgress =>
          status == TaskStatuses.inProgress || status == TaskStatuses.inReview,
        _Bucket.done => status == TaskStatuses.done,
      };
}

/// Manager view of the team's tasks: Pending / In progress / Done segments,
/// an optional member filter, search, and tap-through to the task.
class TeamTasksScreen extends ConsumerStatefulWidget {
  const TeamTasksScreen({super.key, this.header});

  /// Optional widget rendered above the title (the Tasks hub toggle).
  final Widget? header;

  @override
  ConsumerState<TeamTasksScreen> createState() => _TeamTasksScreenState();
}

class _TeamTasksScreenState extends ConsumerState<TeamTasksScreen> {
  _Bucket _bucket = _Bucket.pending;
  int? _memberId;
  String _query = '';

  Future<void> _refresh() async {
    ref.invalidate(_teamTasksProvider);
    await ref.read(_teamTasksProvider.future);
  }

  Future<void> _open(TeamTaskAssignment a) async {
    final id = a.taskId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final tasks = ref.watch(_teamTasksProvider);
    final members = ref.watch(_teamMembersProvider).valueOrNull ?? const [];

    return Column(
      children: [
        SizedBox(height: mq.padding.top + 8),
        if (widget.header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: widget.header,
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Team tasks',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        Expanded(
          child: tasks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: AppErrorPanel(
                message: 'Could not load team tasks: $e',
                onRetry: _refresh,
              ),
            ),
            data: (all) {
              final q = _query.trim().toLowerCase();
              // Member + search filters apply to every bucket, so the counts on
              // the segments reflect what the list would show.
              final base = all.where((a) {
                if (_memberId != null && a.assigneeId != _memberId) return false;
                if (q.isNotEmpty &&
                    !a.taskTitle.toLowerCase().contains(q) &&
                    !(a.assigneeName?.toLowerCase().contains(q) ?? false) &&
                    !(a.templateName?.toLowerCase().contains(q) ?? false) &&
                    !(a.taskCode?.toLowerCase().contains(q) ?? false)) {
                  return false;
                }
                return true;
              }).toList();
              final counts = {
                for (final b in _Bucket.values)
                  b: base.where((a) => b.matches(a.status)).length,
              };
              final visible =
                  base.where((a) => _bucket.matches(a.status)).toList()
                    ..sort(_compare);

              return RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.primary,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                      16, 0, 16, mq.padding.bottom + AppChrome.bottomNavHeight + 24),
                  children: [
                    _BucketBar(
                      value: _bucket,
                      counts: counts,
                      onChanged: (b) => setState(() => _bucket = b),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: const [TitleCaseTextFormatter()],
                      decoration: InputDecoration(
                        hintText: 'Search task, member or form',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () => setState(() => _query = ''),
                              ),
                      ),
                    ),
                    if (members.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _MemberChip(
                              label: 'Everyone',
                              selected: _memberId == null,
                              onTap: () => setState(() => _memberId = null),
                            ),
                            for (final m in members)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _MemberChip(
                                  label: m.name,
                                  selected: _memberId == m.id,
                                  onTap: () => setState(() =>
                                      _memberId = _memberId == m.id ? null : m.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: AppEmptyState(
                          icon: Icons.task_alt_rounded,
                          message: all.isEmpty
                              ? 'No tasks have been assigned to your team yet.'
                              : 'No ${_bucket.label.toLowerCase()} tasks match.',
                        ),
                      )
                    else
                      for (final a in visible) ...[
                        _TeamTaskCard(assignment: a, onTap: () => _open(a)),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Overdue first, then nearest due date, then most recently updated.
  static int _compare(TeamTaskAssignment a, TeamTaskAssignment b) {
    final ao = a.isOverdue, bo = b.isOverdue;
    if (ao != bo) return ao ? -1 : 1;
    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    return (b.updatedAt ?? b.createdAt ?? DateTime(2000))
        .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(2000));
  }
}

class _BucketBar extends StatelessWidget {
  const _BucketBar({
    required this.value,
    required this.counts,
    required this.onChanged,
  });
  final _Bucket value;
  final Map<_Bucket, int> counts;
  final ValueChanged<_Bucket> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          for (final b in _Bucket.values)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                onTap: () => onChanged(b),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == b ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${b.label} · ${counts[b] ?? 0}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: value == b ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.14)
              : Colors.white.withOpacity(0.55),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _TeamTaskCard extends StatelessWidget {
  const _TeamTaskCard({required this.assignment, required this.onTap});
  final TeamTaskAssignment assignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final sColor = statusColor(a.status);
    final due = a.dueDate == null
        ? null
        : DateFormat('d MMM').format(a.dueDate!) +
            (formatDueTime(a.dueTime) == null ? '' : ', ${formatDueTime(a.dueTime)}');
    final dueColor = a.isOverdue ? AppColors.danger : AppColors.muted;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      shadow: AppShadows.soft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    a.taskTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    statusLabel(a.status),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: sColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                UserAvatar(name: a.assigneeName ?? '?', size: 24, radius: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.assigneeName ?? 'Unassigned',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                if (due != null) ...[
                  Icon(
                    a.isOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.event_rounded,
                    size: 14,
                    color: dueColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    a.isOverdue ? 'Overdue · $due' : due,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: dueColor,
                    ),
                  ),
                ],
              ],
            ),
            if (a.templateName != null || a.taskPriority != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (a.taskPriority != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: priorityColor(a.taskPriority!),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      humanizeEnum(a.taskPriority!),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                  if (a.templateName != null) ...[
                    if (a.taskPriority != null)
                      const Text('  ·  ',
                          style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    Expanded(
                      child: Text(
                        a.templateName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (a.status == TaskStatuses.inProgress && a.progressPercentage > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: a.progressPercentage / 100,
                  minHeight: 5,
                  backgroundColor: AppColors.hairline,
                  color: sColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
