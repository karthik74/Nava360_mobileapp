import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../team/team_models.dart';
import '../team/team_repository.dart';
import 'form_renderer.dart';
import 'task_models.dart';
import 'task_repository.dart';
import 'task_status_ui.dart';
import 'task_template_models.dart';
import 'tasks_screen.dart' show TaskTemplateTile;

/// INTERNAL task templates the manager may hand out (targeting rules apply to
/// the manager; template admins see every active template).
final _assignableTemplatesProvider =
    FutureProvider.autoDispose<List<TaskTemplate>>((ref) {
  return ref.watch(taskRepositoryProvider).assignableTemplates();
});

/// The manager's full reporting downline (direct + indirect).
final _myTeamProvider = FutureProvider.autoDispose<List<TeamMember>>((ref) {
  return ref.watch(teamRepositoryProvider).myTeam();
});

const _kPriorities = ['LOW', 'MEDIUM', 'HIGH', 'URGENT'];

/// Manager flow: pick a task form (template), tick team members, set due date /
/// priority / notes and any assigner-owned form fields, then create one task
/// per member. Pops with the number of tasks created.
class AssignTaskScreen extends ConsumerStatefulWidget {
  const AssignTaskScreen({super.key, this.initialTemplate});

  /// Pre-selected template (e.g. when opened from a template tile).
  final TaskTemplate? initialTemplate;

  @override
  ConsumerState<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends ConsumerState<AssignTaskScreen> {
  TaskTemplate? _template;
  final Set<int> _memberIds = {};
  String _memberQuery = '';
  final _memberSearch = TextEditingController();
  DateTime? _dueDate;
  String? _priority;
  final _description = TextEditingController();
  final FormValues _assignedValues = {};
  Map<String, String> _assignedErrors = {};
  bool _submitting = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _template = widget.initialTemplate;
    _priority = widget.initialTemplate?.defaultPriority;
  }

  @override
  void dispose() {
    _description.dispose();
    _memberSearch.dispose();
    super.dispose();
  }

  /// Only the fields the assigner owns (`assigned: true`) are asked here; the
  /// assignee fills the rest when they perform the task.
  FormSchema? get _assignedSchema {
    final schema = FormSchema.parse(_template?.formSchema);
    if (schema == null) return null;
    final fields = schema.fields.where((f) => f.assigned).toList();
    return fields.isEmpty ? null : FormSchema(fields);
  }

  Future<void> _pickTemplate() async {
    final t = await showModalBottomSheet<TaskTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: kTaskSheetShape,
      builder: (_) => const _AssignTemplatePickerSheet(),
    );
    if (t == null || !mounted) return;
    setState(() {
      _template = t;
      _priority ??= t.defaultPriority;
      _assignedValues.clear();
      _assignedErrors = {};
      _err = null;
    });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    final template = _template;
    if (template == null) {
      setState(() => _err = 'Pick a task form first.');
      return;
    }
    if (_memberIds.isEmpty) {
      setState(() => _err = 'Select at least one team member.');
      return;
    }
    final schema = _assignedSchema;
    if (schema != null) {
      final errors =
          validateForm(schema, _assignedValues, includeAssigned: true);
      if (errors.isNotEmpty) {
        setState(() {
          _assignedErrors = errors;
          _err = 'Please complete the highlighted fields.';
        });
        return;
      }
    }
    setState(() {
      _submitting = true;
      _err = null;
      _assignedErrors = {};
    });
    try {
      final me = ref.read(authUserProvider)?.employeeId;
      final created = await ref.read(taskRepositoryProvider).assignTemplate(
            template.id,
            employeeIds: _memberIds.toList(),
            assignedById: me,
            priority: _priority,
            dueDate: _dueDate == null
                ? null
                : DateFormat('yyyy-MM-dd').format(_dueDate!),
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            assignedFieldValues: (schema != null && _assignedValues.isNotEmpty)
                ? jsonEncode(_assignedValues)
                : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(created.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _err = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(_myTeamProvider);
    final template = _template;
    final schema = _assignedSchema;
    final df = DateFormat('EEE, d MMM yyyy');
    final steps = schema != null ? 4 : 3;
    final step = template == null ? 0 : (_memberIds.isEmpty ? 1 : 2);
    final membersSub = _memberIds.isEmpty
        ? 'Who should do it?'
        : '${_memberIds.length} selected · one task each';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Assign task to team',
        subtitle: _memberIds.isEmpty
            ? 'One task per selected member'
            : '${_memberIds.length} selected · one task each',
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ProStepBar(total: steps, current: step),
          const SizedBox(height: 14),

          // ── 1. Task form ─────────────────────────────────────────────
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepHead(
                  number: 1,
                  done: template != null,
                  title: 'Task form',
                  subtitle: 'Which form should they fill?',
                  action: template == null
                      ? null
                      : TextButton.icon(
                          onPressed: _pickTemplate,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                          label: const Text('Change form'),
                        ),
                ),
                const SizedBox(height: 12),
                if (template == null)
                  _ChooseFormButton(onTap: _pickTemplate)
                else
                  TaskTemplateTile(template: template, onTap: _pickTemplate),
              ],
            ),
          ),

          // ── 2. Team members ──────────────────────────────────────────
          const SizedBox(height: 14),
          GlassCard(
            child: team.when(
              loading: () => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepHead(
                    number: 2,
                    done: _memberIds.isNotEmpty,
                    title: 'Team members',
                    subtitle: membersSub,
                  ),
                  const SizedBox(height: 12),
                  const AppLoadingBlock(height: 120),
                ],
              ),
              error: (e, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepHead(
                    number: 2,
                    done: _memberIds.isNotEmpty,
                    title: 'Team members',
                    subtitle: membersSub,
                  ),
                  const SizedBox(height: 12),
                  AppErrorPanel(
                    message: 'Could not load your team: $e',
                    onRetry: () => ref.invalidate(_myTeamProvider),
                  ),
                ],
              ),
              data: (members) {
                if (members.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StepHead(
                        number: 2,
                        done: false,
                        title: 'Team members',
                        subtitle: membersSub,
                      ),
                      const SizedBox(height: 12),
                      const ProNote(
                        'Nobody reports to you yet.',
                        icon: Icons.group_off_rounded,
                      ),
                    ],
                  );
                }
                final q = _memberQuery.trim().toLowerCase();
                final visible = members.where((m) {
                  if (q.isEmpty) return true;
                  return m.name.toLowerCase().contains(q) ||
                      (m.designation?.toLowerCase().contains(q) ?? false) ||
                      (m.employeeCode?.toLowerCase().contains(q) ?? false);
                }).toList();
                final allVisibleSelected = visible.isNotEmpty &&
                    visible.every((m) => _memberIds.contains(m.id));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepHead(
                      number: 2,
                      done: _memberIds.isNotEmpty,
                      title: 'Team members',
                      subtitle: membersSub,
                      action: TextButton(
                        onPressed: () => setState(() {
                          if (allVisibleSelected) {
                            _memberIds.removeAll(visible.map((m) => m.id));
                          } else {
                            _memberIds.addAll(visible.map((m) => m.id));
                          }
                        }),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(allVisibleSelected ? 'Clear' : 'All'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TaskSearchField(
                      controller: _memberSearch,
                      onChanged: (v) => setState(() => _memberQuery = v),
                      onClear: () => setState(() => _memberQuery = ''),
                      hint: 'Search team members',
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: const [TitleCaseTextFormatter()],
                    ),
                    const SizedBox(height: 8),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Nobody matches your search.',
                          textAlign: TextAlign.center,
                          style: AppText.caption,
                        ),
                      ),
                    for (final m in visible)
                      _MemberTile(
                        member: m,
                        selected: _memberIds.contains(m.id),
                        onTap: () => setState(() {
                          if (!_memberIds.remove(m.id)) _memberIds.add(m.id);
                        }),
                      ),
                  ],
                );
              },
            ),
          ),

          // ── 3. Details ───────────────────────────────────────────────
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _StepHead(
                  number: 3,
                  done: false,
                  title: 'Details',
                  subtitle: 'Due date, priority and notes',
                ),
                const SizedBox(height: 16),
                ProField(
                  label: 'Due date',
                  child: InkWell(
                    onTap: _pickDueDate,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.event_rounded, size: 20),
                        suffixIcon: _dueDate == null
                            ? null
                            : IconButton(
                                tooltip: 'Clear due date',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () =>
                                    setState(() => _dueDate = null),
                              ),
                      ),
                      child: Text(
                        _dueDate == null
                            ? 'Use the form\'s default'
                            : df.format(_dueDate!),
                        style: TextStyle(
                          fontSize: 15,
                          color: _dueDate == null
                              ? AppColors.faint
                              : AppColors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ProField(
                  label: 'Priority',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _kPriorities)
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: taskPriorityDot(p),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(p[0] + p.substring(1).toLowerCase()),
                            ],
                          ),
                          selected: _priority == p,
                          onSelected: (_) => setState(() => _priority = p),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ProField(
                  label: 'Notes for the assignee (optional)',
                  child: TextField(
                    controller: _description,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Anything they should know before they go',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 4. Assigner-owned form fields ────────────────────────────
          if (schema != null) ...[
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _StepHead(
                    number: 4,
                    done: false,
                    title: 'Pre-filled details',
                    subtitle: 'These fields are filled by you; the assignee sees '
                        'them read-only',
                  ),
                  const SizedBox(height: 16),
                  FormRenderer(
                    schema: schema,
                    values: _assignedValues,
                    errors: _assignedErrors,
                    ownerFillsAssigned: true,
                    onChanged: (name, value) =>
                        setState(() => _assignedValues[name] = value),
                  ),
                ],
              ),
            ),
          ],

          if (_err != null) ...[
            const SizedBox(height: 14),
            ProNote(_err!, tone: ProNoteTone.bad),
          ],
        ],
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(
              _submitting
                  ? 'Assigning…'
                  : _memberIds.isEmpty
                      ? 'Assign'
                      : 'Assign to ${_memberIds.length}',
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbered card header for a wizard step, with an optional action.
class _StepHead extends StatelessWidget {
  const _StepHead({
    required this.number,
    required this.done,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final int number;
  final bool done;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done
                ? AppColors.success
                : AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.section),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(subtitle, style: AppText.caption),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 6), action!],
      ],
    );
  }
}

/// Empty state of step 1: a tappable "Choose a task form" row.
class _ChooseFormButton extends StatelessWidget {
  const _ChooseFormButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.deep,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.description_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose a task form',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    Text('Tap to pick from the available forms',
                        style: AppText.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Color(0xFFB3C0C3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.selected,
    required this.onTap,
  });
  final TeamMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (member.designation?.isNotEmpty ?? false) member.designation!,
      if (member.branchLabel?.isNotEmpty ?? false) member.branchLabel!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                ProAvatar(name: member.name, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFB9C7CA),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing the task forms the manager may assign.
class _AssignTemplatePickerSheet extends ConsumerStatefulWidget {
  const _AssignTemplatePickerSheet();

  @override
  ConsumerState<_AssignTemplatePickerSheet> createState() =>
      _AssignTemplatePickerSheetState();
}

class _AssignTemplatePickerSheetState
    extends ConsumerState<_AssignTemplatePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_assignableTemplatesProvider);
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height - mq.padding.top - mq.viewInsets.bottom - 8;
    final sheetH = (mq.size.height * 0.88).clamp(0.0, maxH).toDouble();
    final q = _query.trim().toLowerCase();

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: sheetH,
        child: Column(
          children: [
            const TaskSheetHeader(
              title: 'Choose a task form',
              subtitle: 'One task per selected team member will be created from it.',
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TaskSearchField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                onClear: () => setState(() => _query = ''),
                hint: 'Search task form',
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AppErrorPanel(
                      message: 'Could not load task forms: $e',
                    ),
                  ),
                ),
                data: (all) {
                  final list = [...all]..sort((a, b) => a.id.compareTo(b.id));
                  final templates = list.where((t) {
                    if (q.isEmpty) return true;
                    return t.name.toLowerCase().contains(q) ||
                        (t.categoryName?.toLowerCase().contains(q) ?? false) ||
                        '${t.id}'.contains(q);
                  }).toList();
                  if (templates.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ProEmpty(
                          icon: all.isEmpty
                              ? Icons.assignment_outlined
                              : Icons.search_off_rounded,
                          title: all.isEmpty
                              ? 'No task forms are available to assign. Ask your admin to publish one.'
                              : 'No task forms match your search.',
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, mq.padding.bottom + 24),
                    itemCount: templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => TaskTemplateTile(
                      template: templates[i],
                      onTap: () => Navigator.pop(context, templates[i]),
                    ),
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
