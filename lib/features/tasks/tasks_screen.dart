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
import 'task_template_models.dart';

final _myTasksProvider =
    FutureProvider.autoDispose.family<List<Task>, String?>((ref, status) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref
      .watch(taskRepositoryProvider)
      .listForEmployee(user!.employeeId!, status: status);
});

/// Active INTERNAL templates an employee can raise a self-task from.
final _individualTemplatesProvider =
    FutureProvider.autoDispose<List<TaskTemplate>>((ref) {
  return ref.watch(taskRepositoryProvider).individualTemplates();
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
  const TasksScreen({super.key, this.header});

  /// Optional widget rendered at the very top of the list (e.g. the
  /// Customers ⇄ My tasks toggle when embedded in the customer-first hub).
  final Widget? header;

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  _TaskFilter _selectedFilter = _TaskFilter.all;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _creating = false;

  /// Self-task creation: pick an INTERNAL template, raise the task assigned to
  /// the current employee, then open it to fill and submit.
  Future<void> _createSelfTask() async {
    final template = await showModalBottomSheet<TaskTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _TaskTemplatePickerSheet(),
    );
    if (template == null || !mounted) return;

    setState(() => _creating = true);
    try {
      final task = await ref
          .read(taskRepositoryProvider)
          .createSelfTask(templateId: template.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)),
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create task: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

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
    final user = ref.watch(authUserProvider);

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Only employees can raise a task for themselves. Lift the button above
      // the app's custom bottom navigation bar so it never overlaps it.
      floatingActionButton: user?.employeeId == null
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: mq.padding.bottom + AppChrome.bottomNavHeight,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  boxShadow: AppShadows.lifted,
                ),
                child: FloatingActionButton.extended(
                  heroTag: 'new_self_task_fab',
                  onPressed: _creating ? null : _createSelfTask,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  icon: _creating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add_task_rounded, color: Colors.white),
                  label: Text(
                    _creating ? 'Creating…' : 'New task',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
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
            if (widget.header != null) widget.header!,
            const SizedBox(height: 12),
            const AppSectionHeader(
              title: 'My tasks',
              subtitle: 'Tasks assigned to your employee account',
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
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: TaskStatusPill(status: task.status),
              ),
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

// ─────────────────────────── Self-task template picker ─────────────────────

/// Bottom sheet listing active INTERNAL templates the employee can raise a
/// self-task from. Returns the chosen [TaskTemplate] via `Navigator.pop`.
/// Quick category filters surfaced as chips above the template list. Each
/// matches against the template name or its category (case-insensitive).
const _kTemplateFilters = <String>[
  'Collection',
  'Renewal',
  'Meeting',
  'Cheque',
  'FTOD',
];

class _TaskTemplatePickerSheet extends ConsumerStatefulWidget {
  const _TaskTemplatePickerSheet();

  @override
  ConsumerState<_TaskTemplatePickerSheet> createState() =>
      _TaskTemplatePickerSheetState();
}

class _TaskTemplatePickerSheetState
    extends ConsumerState<_TaskTemplatePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _filter; // null => All

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Sort by task number ascending, then apply the search query and the
  /// selected category filter.
  List<TaskTemplate> _visible(List<TaskTemplate> all) {
    final list = [...all]..sort((a, b) => a.id.compareTo(b.id));
    final q = _query.trim().toLowerCase();
    final f = _filter?.toLowerCase();
    return list.where((t) {
      final name = t.name.toLowerCase();
      final cat = t.categoryName?.toLowerCase() ?? '';
      if (q.isNotEmpty &&
          !name.contains(q) &&
          !cat.contains(q) &&
          !'${t.id}'.contains(q)) {
        return false;
      }
      if (f != null && !name.contains(f) && !cat.contains(f)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_individualTemplatesProvider);
    final mq = MediaQuery.of(context);

    // Occupy ~88% of the screen, but never exceed the space left above the
    // keyboard / status bar so the sheet always fits small Android screens.
    final maxH = mq.size.height - mq.padding.top - mq.viewInsets.bottom - 8;
    final sheetH = (mq.size.height * 0.88).clamp(0.0, maxH).toDouble();

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: sheetH,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.muted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Create a task',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick a template to raise a task for yourself.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ),
            ),
            // ── Search ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search task template',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            // ── Category filter chips ───────────────────────────────────
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final f in _kTemplateFilters)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _FilterChip(
                        label: f,
                        selected: _filter == f,
                        onTap: () =>
                            setState(() => _filter = _filter == f ? null : f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // ── Template list ───────────────────────────────────────────
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load templates: $e',
                      style: const TextStyle(color: AppColors.danger)),
                ),
                data: (all) {
                  if (all.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No task templates are available. Ask your admin to publish one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    );
                  }
                  final templates = _visible(all);
                  if (templates.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No templates match your search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    // Bottom inset keeps the last card clear of the system nav
                    // bar / app bottom navigation.
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, mq.padding.bottom + 24),
                    itemCount: templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final t = templates[i];
                      return _TaskTemplateTile(
                        template: t,
                        onTap: () => Navigator.pop(context, t),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill-style category filter used in the template picker header.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskTemplateTile extends StatelessWidget {
  const _TaskTemplateTile({required this.template, required this.onTap});
  final TaskTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = template;
    Color accent = AppColors.primary;
    final hex = t.color;
    if (hex != null && hex.isNotEmpty) {
      final parsed = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
      if (parsed != null) {
        accent = Color(parsed | 0xFF000000);
      }
    }
    final hasCategory =
        t.categoryName != null && t.categoryName!.trim().isNotEmpty;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            // Arrow + icon stay vertically centred against the (variable-height)
            // text block.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.22)),
                ),
                alignment: Alignment.center,
                child:
                    Icon(Icons.assignment_outlined, size: 21, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Line 1: short category (when available).
                    if (hasCategory) ...[
                      Text(
                        t.categoryName!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                    ],
                    // Full task name — wraps to up to 3 lines, never a
                    // single-line ellipsis. Card grows with the text.
                    Text(
                      t.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.3,
                      ),
                    ),
                    if (t.description != null &&
                        t.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        t.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
