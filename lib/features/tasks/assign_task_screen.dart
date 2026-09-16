import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../team/team_models.dart';
import '../team/team_repository.dart';
import 'form_renderer.dart';
import 'task_models.dart';
import 'task_repository.dart';
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
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
    final mq = MediaQuery.of(context);
    final team = ref.watch(_myTeamProvider);
    final template = _template;
    final schema = _assignedSchema;
    final df = DateFormat('EEE, d MMM yyyy');

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.ink,
          title: const Text(
            'Assign task to team',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
          ),
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(16, 8, 16, mq.padding.bottom + 96),
          children: [
            // ── 1. Task form ─────────────────────────────────────────────
            const AppSectionHeader(
              title: '1. Task form',
              subtitle: 'Which form should they fill?',
            ),
            const SizedBox(height: 8),
            if (template == null)
              GlassCard(
                padding: EdgeInsets.zero,
                shadow: AppShadows.soft,
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: AppColors.heroGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.description_rounded,
                        color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    'Choose a task form',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  subtitle: const Text('Tap to pick from the available forms',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.muted),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  onTap: _pickTemplate,
                ),
              )
            else ...[
              TaskTemplateTile(template: template, onTap: _pickTemplate),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _pickTemplate,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Change form'),
                ),
              ),
            ],

            // ── 2. Team members ──────────────────────────────────────────
            const SizedBox(height: 12),
            AppSectionHeader(
              title: '2. Team members',
              subtitle: _memberIds.isEmpty
                  ? 'Who should do it?'
                  : '${_memberIds.length} selected · one task each',
            ),
            const SizedBox(height: 8),
            team.when(
              loading: () => const AppLoadingBlock(height: 120),
              error: (e, _) => AppErrorPanel(
                message: 'Could not load your team: $e',
                onRetry: () => ref.invalidate(_myTeamProvider),
              ),
              data: (members) {
                if (members.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.group_off_rounded,
                    message: 'Nobody reports to you yet.',
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) =>
                                setState(() => _memberQuery = v),
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: const [TitleCaseTextFormatter()],
                            decoration: const InputDecoration(
                              hintText: 'Search team members',
                              isDense: true,
                              prefixIcon:
                                  Icon(Icons.search_rounded, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() {
                            if (allVisibleSelected) {
                              _memberIds
                                  .removeAll(visible.map((m) => m.id));
                            } else {
                              _memberIds.addAll(visible.map((m) => m.id));
                            }
                          }),
                          child: Text(allVisibleSelected ? 'Clear' : 'All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
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

            // ── 3. Details ───────────────────────────────────────────────
            const SizedBox(height: 12),
            const AppSectionHeader(
              title: '3. Details',
              subtitle: 'Due date, priority and notes',
            ),
            const SizedBox(height: 8),
            GlassCard(
              padding: const EdgeInsets.all(14),
              shadow: AppShadows.soft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: _pickDueDate,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Due date',
                        isDense: true,
                        prefixIcon:
                            const Icon(Icons.event_rounded, size: 20),
                        suffixIcon: _dueDate == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                                onPressed: () =>
                                    setState(() => _dueDate = null),
                              ),
                      ),
                      child: Text(
                        _dueDate == null
                            ? 'Use the form\'s default'
                            : df.format(_dueDate!),
                        style: TextStyle(
                          color: _dueDate == null
                              ? AppColors.muted
                              : AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Priority',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _kPriorities)
                        ChoiceChip(
                          label: Text(p[0] + p.substring(1).toLowerCase()),
                          selected: _priority == p,
                          selectedColor: AppColors.primary.withOpacity(0.15),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _priority == p
                                ? AppColors.primary
                                : AppColors.inkSoft,
                          ),
                          onSelected: (_) => setState(() => _priority = p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Notes for the assignee (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),

            // ── 4. Assigner-owned form fields ────────────────────────────
            if (schema != null) ...[
              const SizedBox(height: 12),
              const AppSectionHeader(
                title: '4. Pre-filled details',
                subtitle: 'These fields are filled by you; the assignee sees '
                    'them read-only',
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.all(14),
                shadow: AppShadows.soft,
                child: FormRenderer(
                  schema: schema,
                  values: _assignedValues,
                  errors: _assignedErrors,
                  ownerFillsAssigned: true,
                  onChanged: (name, value) =>
                      setState(() => _assignedValues[name] = value),
                ),
              ),
            ],

            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(
                _err!,
                style: const TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: mq.padding.bottom + 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              boxShadow: AppShadows.lifted,
            ),
            child: FloatingActionButton.extended(
              heroTag: 'assign_task_fab',
              onPressed: _submitting ? null : _submit,
              backgroundColor: Colors.transparent,
              elevation: 0,
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
              label: Text(
                _submitting
                    ? 'Assigning…'
                    : _memberIds.isEmpty
                        ? 'Assign'
                        : 'Assign to ${_memberIds.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        shadow: const [],
        border: selected
            ? Border.all(color: AppColors.primary.withOpacity(0.5))
            : null,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          leading: UserAvatar(name: member.name, size: 38, radius: 19),
          title: Text(
            member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          subtitle: Text(
            [
              if (member.designation?.isNotEmpty ?? false) member.designation!,
              if (member.branchLabel?.isNotEmpty ?? false) member.branchLabel!,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.primary : AppColors.muted,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
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
                  'Choose a task form',
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
                  'One task per selected team member will be created from it.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search task form',
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
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load task forms: $e',
                      style: const TextStyle(color: AppColors.danger)),
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          all.isEmpty
                              ? 'No task forms are available to assign. Ask your admin to publish one.'
                              : 'No task forms match your search.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted),
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
