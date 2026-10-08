import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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

  Color get dot => switch (this) {
        _Bucket.pending => const Color(0xFFF2B347),
        _Bucket.inProgress => const Color(0xFF5EC8DE),
        _Bucket.done => AppColors.live,
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
  final _searchCtrl = TextEditingController();

  /// List order: overdue / due first (default) or by member name.
  bool _sortByMember = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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

  String _bucketSub(_Bucket b, List<TeamTaskAssignment> base) {
    final inBucket = base.where((a) => b.matches(a.status));
    switch (b) {
      case _Bucket.pending:
        final od = inBucket.where((a) => a.isOverdue).length;
        return od == 0 ? 'none overdue' : '$od overdue';
      case _Bucket.inProgress:
        final rv =
            inBucket.where((a) => a.status == TaskStatuses.inReview).length;
        return '$rv in review';
      case _Bucket.done:
        return 'of ${base.length} tasks';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final tasks = ref.watch(_teamTasksProvider);
    final members = ref.watch(_teamMembersProvider).valueOrNull ?? const [];
    final all = tasks.valueOrNull;

    final q = _query.trim().toLowerCase();
    bool matchesSearch(TeamTaskAssignment a) =>
        q.isEmpty ||
        a.taskTitle.toLowerCase().contains(q) ||
        (a.assigneeName?.toLowerCase().contains(q) ?? false) ||
        (a.templateName?.toLowerCase().contains(q) ?? false) ||
        (a.taskCode?.toLowerCase().contains(q) ?? false);

    // Member + search filters apply to every bucket, so the counts on the
    // segments reflect what the list would show.
    final searched =
        (all ?? const <TeamTaskAssignment>[]).where(matchesSearch).toList();
    final base = searched
        .where((a) => _memberId == null || a.assigneeId == _memberId)
        .toList();
    final counts = {
      for (final b in _Bucket.values)
        b: base.where((a) => b.matches(a.status)).length,
    };
    final visible = base.where((a) => _bucket.matches(a.status)).toList()
      ..sort(_sortByMember ? _compareByMember : _compare);

    final memberIndex = members.indexWhere((m) => m.id == _memberId);
    final inBucketSearched =
        searched.where((a) => _bucket.matches(a.status)).toList();

    return ProPage(
      topInset: mq.padding.top,
      clearNav: true,
      onRefresh: _refresh,
      hero: ProHero(
        kicker: 'Tasks',
        title: 'Team tasks',
        subtitle: all == null
            ? null
            : '${all.length} task${all.length == 1 ? '' : 's'}'
                '${members.isEmpty ? '' : ' · ${members.length} member${members.length == 1 ? '' : 's'}'}',
        overlap: TaskSearchField(
          raised: true,
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          onClear: () => setState(() => _query = ''),
          hint: 'Search task, member or form',
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
        ),
        children: [
          if (widget.header != null) widget.header!,
          ProHeroStats(
            stats: [
              for (final b in _Bucket.values)
                ProStat(
                  label: b.label,
                  value: all == null ? '–' : '${counts[b] ?? 0}',
                  sub: all == null ? null : _bucketSub(b, base),
                  dot: b.dot,
                  selected: _bucket == b,
                  onTap: () => setState(() => _bucket = b),
                ),
            ],
          ),
        ],
      ),
      children: [
        if (members.isNotEmpty)
          ProChipBar(
            labels: ['Everyone', for (final m in members) m.name],
            counts: all == null
                ? null
                : [
                    inBucketSearched.length,
                    for (final m in members)
                      inBucketSearched.where((a) => a.assigneeId == m.id).length,
                  ],
            selected: memberIndex < 0 ? 0 : memberIndex + 1,
            onSelected: (i) => setState(() {
              if (i == 0) {
                _memberId = null;
              } else {
                final id = members[i - 1].id;
                _memberId = _memberId == id ? null : id;
              }
            }),
            bleed: 0,
          ),
        tasks.when(
          loading: () => const AppLoadingBlock(height: 140),
          error: (e, _) => AppErrorPanel(
            message: 'Could not load team tasks: $e',
            onRetry: _refresh,
          ),
          data: (all) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: '${_bucket.label} · ${visible.length}',
                small: true,
                trailing: TextButton.icon(
                  onPressed: () =>
                      setState(() => _sortByMember = !_sortByMember),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.swap_vert_rounded, size: 17),
                  label: Text(_sortByMember ? 'Member A–Z' : 'Due first'),
                ),
              ),
              const SizedBox(height: 8),
              if (visible.isEmpty)
                ProEmpty(
                  icon: Icons.task_alt_rounded,
                  title: all.isEmpty
                      ? 'No tasks have been assigned to your team yet.'
                      : 'No ${_bucket.label.toLowerCase()} tasks match.',
                  message: all.isEmpty
                      ? null
                      : 'Try another member or clear the search.',
                )
              else
                ProListGroup(
                  dividerIndent: 64,
                  children: [
                    for (final a in visible)
                      _TeamTaskRow(assignment: a, onTap: () => _open(a)),
                  ],
                ),
            ],
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

  /// Member name A–Z, then the default order within each member.
  static int _compareByMember(TeamTaskAssignment a, TeamTaskAssignment b) {
    final c = (a.assigneeName ?? '')
        .toLowerCase()
        .compareTo((b.assigneeName ?? '').toLowerCase());
    return c != 0 ? c : _compare(a, b);
  }
}

class _TeamTaskRow extends StatelessWidget {
  const _TeamTaskRow({required this.assignment, required this.onTap});
  final TeamTaskAssignment assignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final due = a.dueDate == null
        ? null
        : DateFormat('d MMM').format(a.dueDate!) +
            (formatDueTime(a.dueTime) == null ? '' : ', ${formatDueTime(a.dueTime)}');

    return TaskListRow(
      leading: ProAvatar(
        name: a.assigneeName ?? '?',
        size: 40,
        dot: a.isOverdue ? AppColors.danger : taskStatusDot(a.status),
      ),
      title: a.taskTitle,
      subtitle: [
        a.assigneeName ?? 'Unassigned',
        if (a.templateName != null) a.templateName!,
      ].join(' · '),
      footer: [
        taskStatusProPill(a.status),
        if (a.taskPriority != null) taskPriorityProPill(a.taskPriority!),
        if (due != null)
          TaskDueLabel(
            text: a.isOverdue ? 'Overdue · $due' : due,
            overdue: a.isOverdue,
          ),
      ],
      progress: a.status == TaskStatuses.inProgress && a.progressPercentage > 0
          ? a.progressPercentage
          : null,
      progressColor: AppColors.primary,
      onTap: onTap,
    );
  }
}
