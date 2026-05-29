import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'task_detail_screen.dart';
import 'task_models.dart';
import 'task_repository.dart';

final _myTasksProvider =
    FutureProvider.autoDispose.family<List<Task>, String?>((ref, status) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref
      .watch(taskRepositoryProvider)
      .listForEmployee(user!.employeeId!, status: status);
});

enum _TaskFilter { all, pending, inProgress, done }

extension on _TaskFilter {
  String get label {
    switch (this) {
      case _TaskFilter.all:
        return 'All';
      case _TaskFilter.pending:
        return 'Pending';
      case _TaskFilter.inProgress:
        return 'In progress';
      case _TaskFilter.done:
        return 'Done';
    }
  }

  String? get queryValue {
    switch (this) {
      case _TaskFilter.all:
        return null;
      case _TaskFilter.pending:
        return 'PENDING';
      case _TaskFilter.inProgress:
        return 'IN_PROGRESS';
      case _TaskFilter.done:
        return 'DONE';
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
      // Compare on calendar-day boundaries, ignoring time.
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

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(_myTasksProvider(_selectedFilter.queryValue));

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white.withOpacity(0.85),
        onRefresh: () async {
          ref.invalidate(_myTasksProvider(_selectedFilter.queryValue));
        },
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
            const SizedBox(height: 12),
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
                    ref.invalidate(
                        _myTasksProvider(_selectedFilter.queryValue));
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
                            ref.invalidate(
                              _myTasksProvider(_selectedFilter.queryValue),
                            );
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
                onRetry: () => ref
                    .invalidate(_myTasksProvider(_selectedFilter.queryValue)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final due =
        task.dueDate == null ? null : DateFormat.yMMMd().format(task.dueDate!);
    final dueDate = task.dueDate;
    final today = DateTime.now();
    final isOverdue = dueDate != null &&
        DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(
          DateTime(today.year, today.month, today.day),
        ) &&
        !task.status.toUpperCase().contains('DONE');
    final priority = task.priority?.trim();

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
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _TaskStatusPill(status: task.status)),
            ],
          ),
          if (task.projectName != null || priority != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (task.projectName != null)
                  _MetaPill(
                    icon: Icons.folder_open_rounded,
                    label: task.projectName!,
                    color: AppColors.primary,
                  ),
                if (priority != null)
                  _MetaPill(
                    icon: Icons.flag_rounded,
                    label: _humanPriority(priority),
                    color: _priorityColor(priority),
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
          if (due != null || task.assignedBy != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (due != null) ...[
                  _MetaText(
                    icon: Icons.calendar_today_outlined,
                    label: isOverdue ? 'Overdue $due' : 'Due $due',
                    color: isOverdue ? AppColors.danger : AppColors.muted,
                  ),
                ],
                if (task.assignedBy != null) ...[
                  _MetaText(
                    icon: Icons.person_outline,
                    label: 'Assigned by ${task.assignedBy!}',
                    color: AppColors.muted,
                  ),
                ],
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

class _TaskStatusPill extends StatelessWidget {
  const _TaskStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
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

Color _statusColor(String status) {
  final normalized = status.toUpperCase();
  if (normalized.contains('DONE')) return AppColors.success;
  if (normalized.contains('IN_PROGRESS')) return AppColors.warning;
  if (normalized.contains('CANCEL') || normalized.contains('REJECT')) {
    return AppColors.danger;
  }
  return AppColors.info;
}

String _humanPriority(String priority) {
  final cleaned = priority.trim().replaceAll('_', ' ').toLowerCase();
  if (cleaned.isEmpty) return priority;
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

Color _priorityColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'HIGH':
    case 'URGENT':
      return AppColors.danger;
    case 'MEDIUM':
      return AppColors.warning;
    case 'LOW':
      return AppColors.success;
    default:
      return AppColors.info;
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
                  child: _DatePill(
                    label: 'From',
                    value: _fmt(from),
                  ),
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
                  child: _DatePill(
                    label: 'To',
                    value: _fmt(to),
                  ),
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
