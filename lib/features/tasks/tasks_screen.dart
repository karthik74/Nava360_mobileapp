import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'task_detail_screen.dart';
import 'task_models.dart';
import 'task_repository.dart';
import 'task_status_ui.dart';

final _myTasksProvider =
    FutureProvider.autoDispose.family<List<Task>, String?>((ref, status) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref
      .watch(taskRepositoryProvider)
      .listForEmployee(user!.employeeId!, status: status);
});

final _taskDashboardProvider =
    FutureProvider.autoDispose<TaskDashboard>((ref) {
  return ref.watch(taskRepositoryProvider).dashboard();
});

enum _TaskFilter { all, toDo, inProgress, inReview, done }

extension on _TaskFilter {
  String get label {
    switch (this) {
      case _TaskFilter.all:
        return 'All';
      case _TaskFilter.toDo:
        return 'To do';
      case _TaskFilter.inProgress:
        return 'In progress';
      case _TaskFilter.inReview:
        return 'In review';
      case _TaskFilter.done:
        return 'Done';
    }
  }

  String? get queryValue {
    switch (this) {
      case _TaskFilter.all:
        return null;
      case _TaskFilter.toDo:
        return TaskStatuses.todo;
      case _TaskFilter.inProgress:
        return TaskStatuses.inProgress;
      case _TaskFilter.inReview:
        return TaskStatuses.inReview;
      case _TaskFilter.done:
        return TaskStatuses.done;
    }
  }
}

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  _TaskFilter _selectedFilter = _TaskFilter.all;
  DateTime? _fromDate;
  DateTime? _toDate;

  /// Apply the optional date-range filter to a fetched list (client-side).
  /// Matches against `dueDate` — falls back to `startDate` if no due date.
  List<Task> _applyDateFilter(List<Task> tasks) {
    if (_fromDate == null && _toDate == null) return tasks;
    return tasks.where((t) {
      final ref = t.dueDate ?? t.startDate;
      if (ref == null) return false;
      final day = DateTime(ref.year, ref.month, ref.day);
      if (_fromDate != null && day.isBefore(_fromDate!)) return false;
      if (_toDate != null && day.isAfter(_toDate!)) return false;
      return true;
    }).toList();
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      _fromDate = DateTime(picked.year, picked.month, picked.day);
      if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
        _toDate = _fromDate;
      }
    });
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? _fromDate ?? DateTime.now(),
      firstDate:
          _fromDate ?? DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() => _toDate = DateTime(picked.year, picked.month, picked.day));
  }

  void _clearDates() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
  }

  void _refresh() {
    ref.invalidate(_myTasksProvider(_selectedFilter.queryValue));
    ref.invalidate(_taskDashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(_myTasksProvider(_selectedFilter.queryValue));
    final dashboard = ref.watch(_taskDashboardProvider);

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white.withOpacity(0.85),
        onRefresh: () async => _refresh(),
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            mq.padding.top + 1,
            16,
            mq.padding.bottom + AppChrome.bottomNavHeight + 10,
          ),
          children: [
            const SizedBox(height: 12),
            const AppSectionHeader(
              title: 'My tasks',
              subtitle: 'Tasks assigned to your employee account',
            ),
            const SizedBox(height: 14),
            _DashboardStrip(
              async: dashboard,
              onTapFilter: (filter) {
                setState(() => _selectedFilter = filter);
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _TaskFilter.values.map((filter) {
                final selected = filter == _selectedFilter;
                return ChoiceChip(
                  label: Text(filter.label),
                  selected: selected,
                  selectedColor: AppColors.primary,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.inkSoft,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                  backgroundColor: Colors.white.withOpacity(0.55),
                  side: BorderSide(
                    color: selected
                        ? AppColors.primary
                        : Colors.white.withOpacity(0.55),
                  ),
                  onSelected: (value) {
                    if (!value) return;
                    setState(() => _selectedFilter = filter);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _DateRangeBar(
              from: _fromDate,
              to: _toDate,
              onPickFrom: _pickFromDate,
              onPickTo: _pickToDate,
              onClear: _clearDates,
            ),
            const SizedBox(height: 18),
            tasks.when(
              data: (rows) {
                final filtered = _applyDateFilter(rows);
                if (filtered.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.task_alt_rounded,
                    message: (_fromDate != null || _toDate != null)
                        ? 'No tasks match this filter and date range.'
                        : 'No tasks found for this filter.',
                  );
                }
                return Column(
                  children: [
                    for (final task in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TaskDetailScreen(taskId: task.id),
                              ),
                            );
                            _refresh();
                          },
                          child: _TaskCard(task: task),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const AppLoadingBlock(height: 140),
              error: (err, _) => AppErrorPanel(
                message: err.toString(),
                onRetry: () =>
                    ref.invalidate(_myTasksProvider(_selectedFilter.queryValue)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Dashboard strip ─────────────────────────────

class _DashboardStrip extends StatelessWidget {
  const _DashboardStrip({required this.async, required this.onTapFilter});

  final AsyncValue<TaskDashboard> async;
  final ValueChanged<_TaskFilter> onTapFilter;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const AppLoadingBlock(height: 96),
      error: (_, __) => const SizedBox.shrink(),
      data: (d) {
        final items = <Widget>[
          _MiniStat(
            label: 'To do',
            value: d.myPending,
            icon: Icons.radio_button_unchecked_rounded,
            color: AppColors.info,
            onTap: () => onTapFilter(_TaskFilter.toDo),
          ),
          _MiniStat(
            label: 'In progress',
            value: d.myInProgress,
            icon: Icons.timelapse_rounded,
            color: AppColors.warning,
            onTap: () => onTapFilter(_TaskFilter.inProgress),
          ),
          _MiniStat(
            label: 'In review',
            value: d.myInReview,
            icon: Icons.rate_review_outlined,
            color: AppColors.accent,
            onTap: () => onTapFilter(_TaskFilter.inReview),
          ),
          _MiniStat(
            label: 'Overdue',
            value: d.myOverdue,
            icon: Icons.error_outline_rounded,
            color: AppColors.danger,
          ),
          _MiniStat(
            label: 'Urgent',
            value: d.urgentTasks,
            icon: Icons.priority_high_rounded,
            color: AppColors.pink,
          ),
          _MiniStat(
            label: 'Done (mo)',
            value: d.myDoneThisMonth,
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            onTap: () => onTapFilter(_TaskFilter.done),
          ),
        ];
        return SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => items[i],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        radius: AppRadii.md,
        shadow: AppShadows.soft,
        child: SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────── Task card ───────────────────────────────

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final due =
        task.dueDate == null ? null : DateFormat.yMMMd().format(task.dueDate!);
    final dueTime = formatDueTime(task.dueTime);
    final dueDate = task.dueDate;
    final today = DateTime.now();
    final isOverdue = dueDate != null &&
        DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(
          DateTime(today.year, today.month, today.day),
        ) &&
        !task.isClosed;
    final priority = task.priority?.trim();
    final showProgress = task.completionPercentage > 0 && !task.isDone;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (task.taskCode != null && task.taskCode!.isNotEmpty)
                      Text(
                        task.taskCode!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                          letterSpacing: 0.4,
                        ),
                      ),
                    Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: TaskStatusPill(status: task.status)),
            ],
          ),
          if (task.categoryName != null || priority != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (task.categoryName != null)
                  _MetaPill(
                    icon: Icons.folder_open_rounded,
                    label: task.categoryName!,
                    color: AppColors.primary,
                  ),
                if (priority != null)
                  _MetaPill(
                    icon: Icons.flag_rounded,
                    label: humanizeEnum(priority),
                    color: priorityColor(priority),
                  ),
              ],
            ),
          ],
          if (task.description != null && task.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.description!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.inkSoft,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showProgress) ...[
            const SizedBox(height: 10),
            _ProgressBar(percent: task.completionPercentage),
          ],
          if (due != null || task.assignedByName != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (due != null)
                  _MetaText(
                    icon: Icons.calendar_today_outlined,
                    label: (isOverdue ? 'Overdue $due' : 'Due $due') +
                        (dueTime != null ? ' · $dueTime' : ''),
                    color: isOverdue ? AppColors.danger : AppColors.muted,
                  ),
                if (task.assignedByName != null)
                  _MetaText(
                    icon: Icons.person_outline,
                    label: 'Assigned by ${task.assignedByName!}',
                    color: AppColors.muted,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerRight,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Progress',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
            Text(
              '$clamped%',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 6,
            backgroundColor: AppColors.primary.withOpacity(0.12),
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangeBar extends StatelessWidget {
  const _DateRangeBar({
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClear,
  });

  final DateTime? from;
  final DateTime? to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClear;

  String _fmt(DateTime? d) =>
      d == null ? 'Any' : DateFormat('d MMM y').format(d);

  @override
  Widget build(BuildContext context) {
    final active = from != null || to != null;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shadow: AppShadows.soft,
      radius: AppRadii.md,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dateControls = Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onPickFrom,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: _DatePill(label: 'From', value: _fmt(from)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppColors.muted,
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onPickTo,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: _DatePill(label: 'To', value: _fmt(to)),
                ),
              ),
            ],
          );

          final header = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 16, color: AppColors.muted),
              const SizedBox(width: 8),
              const Text(
                'Due date',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              if (active)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                ),
            ],
          );

          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: header),
                const SizedBox(height: 8),
                dateControls,
              ],
            );
          }

          return Row(
            children: [
              header,
              const SizedBox(width: 10),
              Expanded(child: dateControls),
            ],
          );
        },
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.45),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: Colors.white.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
