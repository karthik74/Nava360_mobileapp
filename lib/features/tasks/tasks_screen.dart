import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../../core/navigation/mobile_menu_config.dart';
import 'assign_task_screen.dart';
import 'task_detail_screen.dart';
import 'task_models.dart';
import 'task_repository.dart';
import 'task_status_ui.dart';
import 'task_template_models.dart';

final _myTasksProvider = FutureProvider.autoDispose
    .family<List<Task>, ({String? status, String? q})>((ref, key) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref
      .watch(taskRepositoryProvider)
      .listForEmployee(user!.employeeId!, status: key.status, q: key.q);
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

/// Priority filter values in chip order; null = all.
const _kPriorityKeys = <String?>[null, 'URGENT', 'HIGH', 'MEDIUM', 'LOW'];
const _kPriorityLabels = <String>['All', 'Urgent', 'High', 'Medium', 'Low'];

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

  final TextEditingController _titleCtrl = TextEditingController();
  String _titleQuery = '';
  // Debounced copy of the search text sent to the SERVER (searches ALL tasks,
  // not just the loaded page). _titleQuery still filters instantly client-side.
  String _serverQuery = '';
  Timer? _searchDebounce;
  String? _priorityFilter; // null = all; else URGENT / HIGH / MEDIUM / LOW

  /// Current provider key: status chip + debounced server-side title search.
  ({String? status, String? q}) get _tasksKey => (
        status: _selectedFilter.queryValue,
        q: _serverQuery.trim().isEmpty ? null : _serverQuery.trim(),
      );

  void _onSearchChanged(String v) {
    setState(() => _titleQuery = v);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _serverQuery = v);
    });
  }

  /// Clear button of the search field (the field clears its own text).
  void _clearSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _titleQuery = '';
      _serverQuery = '';
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _titleCtrl.dispose();
    super.dispose();
  }

  /// Managers holding TASK_ASSIGN can also hand a task form to their team.
  bool get _canAssignToTeam {
    final user = ref.read(authUserProvider);
    return isManagerUser(user) && (user?.hasPermission('TASK_ASSIGN') ?? false);
  }

  /// "New task" FAB: employees go straight to the self-task picker; managers
  /// first choose between a task for themselves and one for their team.
  Future<void> _onNewTask() async {
    if (!_canAssignToTeam) {
      await _createSelfTask();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: kTaskSheetShape,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TaskSheetHeader(title: 'New task'),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ProListGroup(
                  children: [
                    ProListRow(
                      leading: ProIconWell(
                        icon: Icons.person_rounded,
                        color: AppColors.primary,
                      ),
                      title: 'Task for myself',
                      subtitle: 'Pick a form and fill it now',
                      onTap: () => Navigator.pop(ctx, 'self'),
                    ),
                    ProListRow(
                      leading: const ProIconWell(
                        icon: Icons.group_add_rounded,
                        color: AppColors.pink,
                      ),
                      title: 'Assign to my team',
                      subtitle:
                          'Pick a form and the team members who should do it',
                      onTap: () => Navigator.pop(ctx, 'team'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'self') {
      await _createSelfTask();
    } else {
      await _assignToTeam();
    }
  }

  Future<void> _assignToTeam() async {
    final count = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const AssignTaskScreen()),
    );
    if (!mounted || count == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Assigned $count task${count == 1 ? '' : 's'} to your team')),
    );
    _refresh();
  }

  /// Self-task creation: pick an INTERNAL template, raise the task assigned to
  /// the current employee, then open it to fill and submit.
  Future<void> _createSelfTask() async {
    final template = await showModalBottomSheet<TaskTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: kTaskSheetShape,
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

  /// Apply all client-side filters: date range, task-title search and priority.
  List<Task> _applyFilters(List<Task> tasks) {
    var list = _applyDateFilter(tasks);
    final q = _titleQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) => t.title.toLowerCase().contains(q)).toList();
    }
    if (_priorityFilter != null) {
      list = list
          .where((t) => (t.priority ?? '').toUpperCase() == _priorityFilter)
          .toList();
    }
    return list;
  }

  bool get _hasActiveFilters =>
      _fromDate != null ||
      _toDate != null ||
      _titleQuery.trim().isNotEmpty ||
      _priorityFilter != null;

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
    ref.invalidate(_myTasksProvider(_tasksKey));
    ref.invalidate(_taskDashboardProvider);
  }

  /// Filters chosen in the Filter sheet (title search is separate).
  int get _activeFilterCount =>
      (_selectedFilter != _TaskFilter.all ? 1 : 0) +
      (_priorityFilter != null ? 1 : 0) +
      (_fromDate != null || _toDate != null ? 1 : 0);

  void _clearAllFilters() {
    setState(() {
      _selectedFilter = _TaskFilter.all;
      _priorityFilter = null;
      _fromDate = null;
      _toDate = null;
    });
  }

  String _fmtDay(DateTime d) => DateFormat('d MMM').format(d);

  /// One sheet for every filter type — applied live; "Show tasks" closes it.
  Future<void> _openFilters() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          void update(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          Widget group(String label, List<Widget> chips) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.label.copyWith(color: AppColors.muted)),
                  const SizedBox(height: 9),
                  Wrap(spacing: 8, runSpacing: 8, children: chips),
                ],
              );

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, 16 + MediaQuery.of(sheetCtx).padding.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D7E8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Filter tasks',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _activeFilterCount == 0
                            ? null
                            : () => update(() {
                                  _selectedFilter = _TaskFilter.all;
                                  _priorityFilter = null;
                                  _fromDate = null;
                                  _toDate = null;
                                }),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  group('Status', [
                    for (final f in _TaskFilter.values)
                      _FilterChoice(
                        label: f.label,
                        selected: _selectedFilter == f,
                        onTap: () => update(() => _selectedFilter = f),
                      ),
                  ]),
                  const SizedBox(height: 18),
                  group('Priority', [
                    for (var i = 0; i < _kPriorityKeys.length; i++)
                      _FilterChoice(
                        label: i == 0 ? 'Any' : _kPriorityLabels[i],
                        selected: _priorityFilter == _kPriorityKeys[i],
                        onTap: () =>
                            update(() => _priorityFilter = _kPriorityKeys[i]),
                      ),
                  ]),
                  const SizedBox(height: 18),
                  _DateRangeBar(
                    from: _fromDate,
                    to: _toDate,
                    onPickFrom: () async {
                      await _pickFromDate();
                      setSheet(() {});
                    },
                    onPickTo: () async {
                      await _pickToDate();
                      setSheet(() {});
                    },
                    onClear: () => update(() {
                      _fromDate = null;
                      _toDate = null;
                    }),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: Text(_activeFilterCount == 0
                        ? 'Show all tasks'
                        : 'Show tasks · $_activeFilterCount '
                            '${_activeFilterCount == 1 ? 'filter' : 'filters'}'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Hero stat tiles double as status filters (tap again to clear).
  void _toggleFilter(_TaskFilter f) {
    setState(() => _selectedFilter = _selectedFilter == f ? _TaskFilter.all : f);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(_myTasksProvider(_tasksKey));
    final dashboard = ref.watch(_taskDashboardProvider);
    final user = ref.watch(authUserProvider);
    final dash = dashboard.valueOrNull;
    final canCreate = user?.employeeId != null;

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Only employees can raise a task for themselves. Lift the button above
      // the app's floating bottom navigation so it never overlaps it.
      floatingActionButton: !canCreate
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: math.max(mq.padding.bottom, AppChrome.bottomNavHeight),
              ),
              child: FloatingActionButton.extended(
                heroTag: 'new_self_task_fab',
                onPressed: _creating ? null : _onNewTask,
                icon: _creating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.add_task_rounded),
                label: Text(_creating ? 'Creating…' : 'New task'),
              ),
            ),
      body: ProPage(
        topInset: mq.padding.top,
        clearNav: true,
        // Extra room at the end so the last row clears the "New task" button.
        padding: EdgeInsets.fromLTRB(16, 16, 16, canCreate ? 88 : 24),
        onRefresh: () async => _refresh(),
        hero: ProHero(
          kicker: 'Tasks',
          title: 'My tasks',
          // Search by task title.
          overlap: TaskSearchField(
            raised: true,
            controller: _titleCtrl,
            onChanged: _onSearchChanged,
            onClear: _clearSearch,
            hint: 'Search by task title…',
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseTextFormatter()],
          ),
          children: [
            if (widget.header != null) widget.header!,
            if (dash != null) ...[
              ProHeroStats(
                stats: [
                  ProStat(
                    label: 'To do',
                    value: '${dash.myPending}',
                    sub: '${dash.myInProgress} in progress',
                    dot: const Color(0xFFF2B347),
                    selected: _selectedFilter == _TaskFilter.toDo,
                    onTap: () => _toggleFilter(_TaskFilter.toDo),
                  ),
                  ProStat(
                    label: 'Overdue',
                    value: '${dash.myOverdue}',
                    sub: dash.urgentTasks > 0
                        ? '${dash.urgentTasks} urgent'
                        : 'open tasks',
                    dot: const Color(0xFFE5484D),
                  ),
                  ProStat(
                    label: 'Done',
                    value: '${dash.myDoneThisMonth}',
                    sub: 'this month',
                    dot: AppColors.live,
                    selected: _selectedFilter == _TaskFilter.done,
                    onTap: () => _toggleFilter(_TaskFilter.done),
                  ),
                ],
              ),
              if (dash.myDoneThisMonth +
                      dash.myInReview +
                      dash.myInProgress +
                      dash.myPending >
                  0)
                _StatusMixBar(dash: dash),
            ],
          ],
        ),
        children: [
          // One Filter button (status, priority, due date live in a sheet);
          // the chosen filters show as removable tags underneath.
          Builder(builder: (context) {
            final rows = tasks.valueOrNull;
            final n = rows == null ? null : _applyFilters(rows).length;
            final active = _activeFilterCount;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${active > 0 ? 'Filtered tasks' : 'All tasks'}'
                        '${n == null ? '' : ' · $n'}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    _FilterButton(count: active, onTap: _openFilters),
                  ],
                ),
                if (active > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_selectedFilter != _TaskFilter.all)
                        _ActiveFilterTag(
                          label: _selectedFilter.label,
                          onRemove: () =>
                              setState(() => _selectedFilter = _TaskFilter.all),
                        ),
                      if (_priorityFilter != null)
                        _ActiveFilterTag(
                          label:
                              '${_kPriorityLabels[_kPriorityKeys.indexOf(_priorityFilter)]} priority',
                          onRemove: () => setState(() => _priorityFilter = null),
                        ),
                      if (_fromDate != null || _toDate != null)
                        _ActiveFilterTag(
                          label: 'Due ${_fromDate == null ? '…' : _fmtDay(_fromDate!)}'
                              ' – ${_toDate == null ? '…' : _fmtDay(_toDate!)}',
                          onRemove: _clearDates,
                        ),
                      TextButton(
                        onPressed: _clearAllFilters,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        child: const Text('Clear all'),
                      ),
                    ],
                  ),
                ],
              ],
            );
          }),
          tasks.when(
            data: (rows) {
              final filtered = _applyFilters(rows);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (filtered.isEmpty)
                    ProEmpty(
                      icon: Icons.task_alt_rounded,
                      title: 'No tasks here',
                      message: _hasActiveFilters
                          ? 'No tasks match your filters.'
                          : 'No tasks found for this filter.',
                    )
                  else
                    ProListGroup(
                      children: [
                        for (final task in filtered)
                          _TaskRow(
                            task: task,
                            currentEmployeeId: user?.employeeId,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TaskDetailScreen(taskId: task.id),
                                ),
                              );
                              _refresh();
                            },
                          ),
                      ],
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 140),
            error: (err, _) => AppErrorPanel(
              message: err.toString(),
              onRetry: () => ref.invalidate(_myTasksProvider(_tasksKey)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Done / in review / in progress / to do mix on the deep hero.
class _StatusMixBar extends StatelessWidget {
  const _StatusMixBar({required this.dash});
  final TaskDashboard dash;

  @override
  Widget build(BuildContext context) {
    final parts = <(int, Color, String)>[
      (dash.myDoneThisMonth, AppColors.live, 'Done'),
      (dash.myInReview, const Color(0xFFB79CF0), 'In review'),
      (dash.myInProgress, const Color(0xFF3CC2D8), 'In progress'),
      (dash.myPending, Colors.white.withValues(alpha: 0.3), 'To do'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProStackBar(
          parts: [for (final p in parts) MapEntry(p.$1.toDouble(), p.$2)],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: p.$2, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${p.$3} ${p.$1}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white70,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────────────── Task row ────────────────────────────────

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onTap,
    this.currentEmployeeId,
  });
  final Task task;
  final VoidCallback onTap;

  /// The signed-in employee, to flag tasks assigned to one of their reportees
  /// that they, as the reporting manager, may perform on the assignee's behalf.
  final int? currentEmployeeId;

  @override
  Widget build(BuildContext context) {
    final onBehalf = task.isOnBehalfFor(currentEmployeeId);
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
    final (ink, _) = taskStatusTones(task.status);

    return TaskListRow(
      leading: ProIconWell(icon: taskStatusIcon(task.status), color: ink),
      title: task.title,
      // Category · assigned-by.
      subtitle: [
        if (task.categoryName != null) task.categoryName!,
        if (task.assignedByName != null) 'by ${task.assignedByName}',
      ].join(' · '),
      footer: [
        if (due != null)
          TaskDueLabel(
            text: (isOverdue ? 'Overdue $due' : due) +
                (dueTime != null ? ' · $dueTime' : ''),
            overdue: isOverdue,
          ),
        if (priority != null) taskPriorityProPill(priority),
        taskStatusProPill(task.status),
        // Assigned to one of this employee's reportees — as the reporting
        // manager they can perform it on the assignee's behalf.
        if (onBehalf)
          ProPill(
            'For ${task.assignedToName ?? 'reportee'}',
            color: AppColors.accent,
            background: AppColors.infoTint,
          ),
      ],
      // Inline progress (only while in progress).
      progress: showProgress ? task.completionPercentage : null,
      progressColor: AppColors.primary,
      onTap: onTap,
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dateControls = Row(
            children: [
              Expanded(
                child: _DatePill(label: 'From', value: _fmt(from), onTap: onPickFrom),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppColors.faint,
                ),
              ),
              Expanded(
                child: _DatePill(label: 'To', value: _fmt(to), onTap: onPickTo),
              ),
            ],
          );

          final header = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_rounded, size: 17, color: AppColors.muted),
              const SizedBox(width: 6),
              const Text('Due date', style: AppText.label),
              if (active)
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
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
  const _DatePill({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
            const TaskSheetHeader(
              title: 'Create a task',
              subtitle: 'Pick a template to raise a task for yourself.',
            ),
            const SizedBox(height: 12),
            // ── Search ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TaskSearchField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                onClear: () => setState(() => _query = ''),
                hint: 'Search task template',
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
              ),
            ),
            // ── Category filter chips ───────────────────────────────────
            ProChipBar(
              labels: const ['All', ..._kTemplateFilters],
              selected: _filter == null
                  ? 0
                  : _kTemplateFilters.indexOf(_filter!) + 1,
              onSelected: (i) => setState(() {
                if (i == 0) {
                  _filter = null;
                } else {
                  final f = _kTemplateFilters[i - 1];
                  _filter = _filter == f ? null : f;
                }
              }),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            // ── Template list ───────────────────────────────────────────
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AppErrorPanel(
                      message: 'Could not load templates: $e',
                    ),
                  ),
                ),
                data: (all) {
                  if (all.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ProEmpty(
                          icon: Icons.assignment_outlined,
                          title: 'No task templates',
                          message:
                              'No task templates are available. Ask your admin to publish one.',
                        ),
                      ),
                    );
                  }
                  final templates = _visible(all);
                  if (templates.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ProEmpty(
                          icon: Icons.search_off_rounded,
                          title: 'No templates match your search.',
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
                      return TaskTemplateTile(
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

class TaskTemplateTile extends StatelessWidget {
  const TaskTemplateTile({super.key, required this.template, required this.onTap});
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
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            // Arrow + icon stay vertically centred against the (variable-height)
            // text block.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProIconWell(
                icon: Icons.assignment_outlined,
                color: accent,
                size: 42,
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
                        t.categoryName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    // Full task name — wraps to up to 3 lines, never a
                    // single-line ellipsis. Card grows with the text.
                    Text(
                      t.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                        height: 1.3,
                      ),
                    ),
                    if (t.description != null &&
                        t.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        t.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Color(0xFFB3C0C3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// White pill "Filter" button with a brand count badge when filters are on.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: count > 0 ? 'Filter tasks, $count active' : 'Filter tasks',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppShadows.soft,
        ),
        child: Material(
          color: Colors.white,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 17, color: AppColors.primary),
                  const SizedBox(width: 7),
                  const Text(
                    'Filter',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 7),
                    Container(
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(AppColors.primary, Colors.white, 0.22)!,
                            AppColors.primary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-choice pill inside the Filter sheet.
class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? brand : Colors.white,
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(brand, Colors.white, 0.22)!, brand],
                  )
                : null,
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: AppColors.hairline),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: brand.withOpacity(0.35),
                      blurRadius: 14,
                      spreadRadius: -6,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          // widthFactor 1: the pill hugs its label instead of filling the row.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand-tinted tag for an applied filter; tap × to remove it.
class _ActiveFilterTag extends StatelessWidget {
  const _ActiveFilterTag({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.primary;
    return Semantics(
      button: true,
      label: 'Remove filter $label',
      child: Material(
        color: brand.withOpacity(0.1),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onRemove,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 9, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: brand,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(Icons.close_rounded, size: 15, color: brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
