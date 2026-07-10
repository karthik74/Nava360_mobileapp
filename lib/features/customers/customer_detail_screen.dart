import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/branding.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../tasks/task_status_ui.dart';
import '../tasks/task_template_models.dart';
import 'customer_models.dart';
import 'customer_repository.dart';

final customerProvider =
    FutureProvider.autoDispose.family<Customer, int>((ref, id) {
  return ref.watch(customerRepositoryProvider).get(id);
});

final customerTasksProvider =
    FutureProvider.autoDispose.family<List<Task>, int>((ref, id) {
  return ref.watch(customerRepositoryProvider).tasksForCustomer(id);
});

final customerTemplatesProvider =
    FutureProvider.autoDispose<List<TaskTemplate>>((ref) {
  return ref.watch(taskRepositoryProvider).customerTemplates();
});

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final int customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  bool _starting = false;

  void _refresh() {
    ref.invalidate(customerTasksProvider(widget.customerId));
  }

  /// Customer-first task creation: pick a template, raise the task assigned to
  /// the current employee, then open it to fill and submit.
  Future<void> _performTask(Customer customer) async {
    final template = await showModalBottomSheet<TaskTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _TemplatePickerSheet(),
    );
    if (template == null || !mounted) return;

    setState(() => _starting = true);
    try {
      final task = await ref.read(customerRepositoryProvider).createSelfTask(
            customer.id,
            templateId: template.id,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)),
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start task: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(customerProvider(widget.customerId));
    final tasksAsync = ref.watch(customerTasksProvider(widget.customerId));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Customer'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0.5,
      ),
      bottomNavigationBar: customerAsync.maybeWhen(
        data: (customer) => SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _starting ? null : () => _performTask(customer),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(50),
            ),
            icon: _starting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.add_task_rounded, size: 20),
            label: Text(_starting ? 'Starting…' : 'Perform task'),
          ),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
      body: customerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(e.toString())),
        ),
        data: (customer) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(customerProvider(widget.customerId));
            _refresh();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _CustomerHeader(customer: customer),
              if (customer.customFields.isNotEmpty) ...[
                const SizedBox(height: 22),
                const _SectionLabel('Details'),
                const SizedBox(height: 12),
                _CustomFieldsCard(fields: customer.customFields),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  const _SectionLabel('Task history'),
                  const Spacer(),
                  tasksAsync.maybeWhen(
                    data: (t) => Text(
                      '${t.length} total',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              tasksAsync.when(
                loading: () => const AppLoadingBlock(height: 120),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: _refresh,
                ),
                data: (tasks) => _TaskHistory(
                  tasks: tasks,
                  onOpen: (task) async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskDetailScreen(taskId: task.id),
                      ),
                    );
                    _refresh();
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Header ───────────────────────────────────

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final rows = <Widget>[
      if (c.mobileNumber != null && c.mobileNumber!.isNotEmpty)
        _InfoRow(icon: Icons.call_outlined, label: 'Mobile', value: c.mobileNumber!),
      if (c.email != null && c.email!.isNotEmpty)
        _InfoRow(icon: Icons.mail_outline_rounded, label: 'Email', value: c.email!),
      if (c.address != null && c.address!.isNotEmpty)
        _InfoRow(icon: Icons.place_outlined, label: 'Address', value: c.address!),
      if (c.branchName != null && c.branchName!.isNotEmpty)
        _InfoRow(
            icon: Icons.store_mall_directory_outlined,
            label: Branding.current.term('branch'),
            value: c.branchName!),
      if (c.assignedEmployeeName != null && c.assignedEmployeeName!.isNotEmpty)
        _InfoRow(
            icon: Icons.person_outline,
            label: 'Account owner',
            value: c.assignedEmployeeName!),
      if (c.createdBy != null && c.createdBy!.isNotEmpty)
        _InfoRow(
            icon: Icons.person_add_alt_outlined,
            label: 'Created by',
            value: c.createdAt != null
                ? '${c.createdBy} · ${DateFormat('d MMM y').format(c.createdAt!)}'
                : c.createdBy!),
      if (c.updatedBy != null && c.updatedBy!.isNotEmpty)
        _InfoRow(
            icon: Icons.update_rounded,
            label: 'Last updated',
            value: c.updatedAt != null
                ? '${c.updatedBy} · ${DateFormat('d MMM y').format(c.updatedAt!)}'
                : c.updatedBy!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(name: c.customerName, size: 52, radius: 15),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.customerCode != null && c.customerCode!.isNotEmpty)
                    Text(
                      c.customerCode!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                        letterSpacing: 0.3,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    c.customerName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: (c.isActive ? AppColors.success : AppColors.muted)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: (c.isActive ? AppColors.success : AppColors.muted)
                            .withOpacity(0.25),
                      ),
                    ),
                    child: Text(
                      (c.status ?? 'ACTIVE').toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: c.isActive ? AppColors.success : AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.muted.withOpacity(0.15)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: AppColors.muted.withOpacity(0.12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: rows[i],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────── Custom fields ────────────────────────────────

/// Renders every dynamic custom field from the customer response as a
/// label/value table (insertion order preserved).
class _CustomFieldsCard extends StatelessWidget {
  const _CustomFieldsCard({required this.fields});
  final Map<String, dynamic> fields;

  static String _humanizeKey(String key) {
    const acronyms = {'id', 'od', 'dpd', 'igl', 'fig'};
    return key
        .split(RegExp(r'[_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => acronyms.contains(w.toLowerCase())
            ? w.toUpperCase()
            : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  static String _formatValue(dynamic v) {
    if (v == null) return '—';
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    final entries = fields.entries.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.muted.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: AppColors.muted.withOpacity(0.12)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      _humanizeKey(entries[i].key),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Text(
                      _formatValue(entries[i].value),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
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

// ─────────────────────────── Task history ─────────────────────────────────

class _TaskHistory extends StatelessWidget {
  const _TaskHistory({required this.tasks, required this.onOpen});
  final List<Task> tasks;
  final void Function(Task) onOpen;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const AppEmptyState(
        icon: Icons.fact_check_outlined,
        message: 'No tasks yet for this customer.\nTap “Perform task” to start one.',
      );
    }

    // Group by status in a sensible workflow order.
    const order = [
      TaskStatuses.inProgress,
      TaskStatuses.todo,
      TaskStatuses.inReview,
      TaskStatuses.done,
      TaskStatuses.rejected,
      TaskStatuses.cancelled,
    ];
    const labels = {
      TaskStatuses.inProgress: 'In progress',
      TaskStatuses.todo: 'To do',
      TaskStatuses.inReview: 'In review',
      TaskStatuses.done: 'Completed',
      TaskStatuses.rejected: 'Rejected',
      TaskStatuses.cancelled: 'Cancelled',
    };

    final groups = <String, List<Task>>{};
    for (final t in tasks) {
      groups.putIfAbsent(t.status, () => []).add(t);
    }

    final sections = <Widget>[];
    for (final status in order) {
      final group = groups.remove(status);
      if (group == null || group.isEmpty) continue;
      sections.add(_group(labels[status] ?? humanizeEnum(status), status, group));
    }
    // Any unexpected statuses.
    for (final entry in groups.entries) {
      sections.add(_group(humanizeEnum(entry.key), entry.key, entry.value));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }

  Widget _group(String label, String status, List<Task> group) {
    final color = statusColor(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                '$label · ${group.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkSoft,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        for (final t in group)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () => onOpen(t),
              child: _TaskTile(task: t),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final due = task.dueDate == null
        ? null
        : DateFormat.yMMMd().format(task.dueDate!);
    return GlassCard(
      padding: const EdgeInsets.all(12),
      radius: AppRadii.md,
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.taskCode != null && task.taskCode!.isNotEmpty)
                  Text(
                    task.taskCode!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                      letterSpacing: 0.3,
                    ),
                  ),
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TaskStatusPill(status: task.status),
                    if (due != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.calendar_today_outlined,
                          size: 12, color: AppColors.muted),
                      const SizedBox(width: 3),
                      Text(
                        due,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.muted),
        ],
      ),
    );
  }
}

// ─────────────────────────── Template picker ──────────────────────────────

/// Quick category filters surfaced as chips above the template list. Each
/// matches against the template name or its category (case-insensitive).
const _kTemplateFilters = <String>[
  'Collection',
  'Renewal',
  'Meeting',
  'Cheque',
  'FTOD',
];

class _TemplatePickerSheet extends ConsumerStatefulWidget {
  const _TemplatePickerSheet();

  @override
  ConsumerState<_TemplatePickerSheet> createState() =>
      _TemplatePickerSheetState();
}

class _TemplatePickerSheetState extends ConsumerState<_TemplatePickerSheet> {
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
    final async = ref.watch(customerTemplatesProvider);
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
                  'Choose a task',
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
                  'Pick the task you want to perform for this customer.',
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
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
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
                  child: Text('Could not load tasks: $e',
                      style: const TextStyle(color: AppColors.danger)),
                ),
                data: (all) {
                  if (all.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No customer task templates are available. Ask your admin to publish one.',
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
                      return _TemplateTile(
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

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.template, required this.onTap});
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
                    if (t.description != null && t.description!.isNotEmpty) ...[
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
