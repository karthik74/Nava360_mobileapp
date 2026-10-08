import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/text_formatters.dart';
import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../tasks/task_status_ui.dart';
import '../tasks/task_template_models.dart';
import 'customer_models.dart';
import 'customer_notice_screen.dart';
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

  /// Selected section tab (Contact / Details / Tasks).
  int _section = 0;

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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

  void _openNotices(Customer customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerNoticeScreen(customer: customer),
      ),
    );
  }

  /// Opens the dialler with the customer's number.
  Future<void> _call(Customer c) async {
    final cleaned = (c.mobileNumber ?? '').replaceAll(RegExp(r'[^0-9+#*]'), '');
    if (cleaned.isEmpty) return;
    try {
      if (await launchUrl(Uri(scheme: 'tel', path: cleaned),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialler.')),
      );
    }
  }

  /// Directions to the customer's stored pin — only the coordinates leave
  /// the app.
  Future<void> _navigate(Customer c) async {
    if (!c.hasLocation) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1'
        '&destination=${c.latitude},${c.longitude}&travelmode=driving');
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(customerProvider(widget.customerId));
    final tasksAsync = ref.watch(customerTasksProvider(widget.customerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          customerAsync.maybeWhen(
            data: (customer) => IconButton(
              tooltip: 'Notices',
              icon: const Icon(Icons.description_outlined),
              onPressed: () => _openNotices(customer),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      bottomNavigationBar: customerAsync.maybeWhen(
        data: (customer) => ProBottomBar(
          children: [
            FilledButton.icon(
              onPressed: _starting ? null : () => _performTask(customer),
              style: FilledButton.styleFrom(
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
          ],
        ),
        orElse: () => const SizedBox.shrink(),
      ),
      body: customerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(customerProvider(widget.customerId)),
            ),
          ),
        ),
        data: (customer) => _body(customer, tasksAsync),
      ),
    );
  }

  Widget _body(Customer customer, AsyncValue<List<Task>> tasksAsync) {
    final c = customer;
    final sections = <String>[
      'Contact',
      if (c.customFields.isNotEmpty) 'Details',
      tasksAsync.hasValue ? 'Tasks · ${tasksAsync.value!.length}' : 'Tasks',
    ];
    final section = _section.clamp(0, sections.length - 1);
    final isTasks = section == sections.length - 1;
    final isDetails = c.customFields.isNotEmpty && section == 1;

    final role = [
      if (c.customerCode != null && c.customerCode!.isNotEmpty) c.customerCode!,
      if (c.branchName != null && c.branchName!.isNotEmpty) c.branchName!,
    ].join(' · ');
    final live = _liveLine(tasksAsync.valueOrNull);

    return DefaultTabController(
      key: ValueKey(sections.length),
      length: sections.length,
      initialIndex: section,
      child: ProPage(
        onRefresh: () async {
          ref.invalidate(customerProvider(widget.customerId));
          _refresh();
        },
        hero: ProHero(
          overlap: ProKpiStrip(cells: _kpis(c, tasksAsync)),
          children: [
            ProHeroIdentity(
              name: c.customerName,
              role: role.isEmpty ? null : role,
              initials: ProAvatar.initialsOf(c.customerName),
              ringColor: c.isActive ? AppColors.live : const Color(0xFFB3C0C3),
              tags: [
                ProHeroTag(
                  _sentence(c.status ?? 'ACTIVE'),
                  tone: c.isActive ? ProTagTone.ok : ProTagTone.neutral,
                ),
                _locationTag(c),
                if (c.createdAt != null)
                  ProHeroTag('Since ${DateFormat('MMM y').format(c.createdAt!)}'),
              ],
            ),
            if (live != null) live,
            ProHeroActions(actions: [
              ProAction(
                icon: Icons.call_rounded,
                label: 'Call',
                onTap: (c.mobileNumber ?? '').trim().isEmpty ? null : () => _call(c),
              ),
              ProAction(
                icon: Icons.directions_rounded,
                label: 'Navigate',
                onTap: c.hasLocation ? () => _navigate(c) : null,
              ),
              ProAction(
                icon: Icons.add_task_rounded,
                label: _starting ? 'Starting…' : 'Perform task',
                primary: true,
                onTap: _starting ? null : () => _performTask(c),
              ),
              ProAction(
                icon: Icons.description_outlined,
                label: 'Notices',
                onTap: () => _openNotices(c),
              ),
            ]),
          ],
        ),
        children: [
          TabBar(
            isScrollable: false,
            dividerColor: AppColors.hairline,
            onTap: (i) => setState(() => _section = i),
            tabs: [for (final s in sections) Tab(text: s, height: 42)],
          ),
          if (isTasks)
            ..._taskSection(tasksAsync)
          else if (isDetails)
            _CustomFieldsCard(fields: c.customFields)
          else
            _ContactCard(customer: c),
        ],
      ),
    );
  }

  List<Widget> _taskSection(AsyncValue<List<Task>> tasksAsync) {
    return [
      ProSectionHeader(
        title: 'Task history',
        subtitle: tasksAsync.maybeWhen(
          data: (t) => '${t.length} total',
          orElse: () => null,
        ),
      ),
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
    ];
  }

  /// "3 open tasks · next due 08 Oct" — built from the task history already
  /// loaded for this screen.
  Widget? _liveLine(List<Task>? tasks) {
    if (tasks == null) return null;
    const openStatuses = {
      TaskStatuses.todo,
      TaskStatuses.inProgress,
      TaskStatuses.inReview,
    };
    final open = tasks.where((t) => openStatuses.contains(t.status)).toList();
    if (open.isEmpty) return null;
    final today = DateUtils.dateOnly(DateTime.now());
    final dues = open.map((t) => t.dueDate).whereType<DateTime>().toList()
      ..sort();
    final overdue = dues.any((d) => DateUtils.dateOnly(d).isBefore(today));
    final next = dues.isEmpty ? null : dues.first;
    final text = '${open.length} open task${open.length == 1 ? '' : 's'}'
        '${next == null ? '' : overdue ? ' · overdue since ${DateFormat('d MMM').format(next)}' : ' · next due ${DateFormat('d MMM').format(next)}'}';
    return ProLiveLine(
      text: text,
      color: overdue ? const Color(0xFFF2B347) : null,
    );
  }

  ProHeroTag _locationTag(Customer c) {
    switch ((c.locationStatus ?? '').toUpperCase()) {
      case 'VERIFIED':
        return const ProHeroTag('Location verified',
            tone: ProTagTone.ok, icon: Icons.verified_rounded);
      case 'NEEDS_CORRECTION':
        return const ProHeroTag('Pin under review',
            tone: ProTagTone.warn, icon: Icons.place_outlined);
      case 'REJECTED':
        return const ProHeroTag('Pin rejected',
            tone: ProTagTone.bad, icon: Icons.location_off_outlined);
    }
    return c.hasLocation
        ? const ProHeroTag('Location pinned', icon: Icons.place_outlined)
        : const ProHeroTag('No location',
            tone: ProTagTone.warn, icon: Icons.location_off_outlined);
  }

  /// KPI strip: loan / outstanding / dues read from the customer's own
  /// fields when the deployment has them, topped up with task counts.
  List<ProKpi> _kpis(Customer c, AsyncValue<List<Task>> tasksAsync) {
    final cells = <ProKpi>[];
    final used = <String>{};
    final patterns = <RegExp>[
      RegExp(r'loan.*(amount|amt)|disburs|sanction'),
      RegExp(r'outstanding|(^|_)pos(_|$)|balance'),
      RegExp(r'overdue|(^|_)dues?(_|$)|emi|dpd'),
    ];
    for (final p in patterns) {
      for (final e in c.customFields.entries) {
        final k = e.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
        if (used.contains(e.key) || !p.hasMatch(k)) continue;
        final raw = e.value?.toString().trim() ?? '';
        if (raw.isEmpty) continue;
        used.add(e.key);
        final isDays = k.contains('dpd') || k.contains('day');
        cells.add(ProKpi(
          value: isDays ? raw : _money(raw),
          label: _CustomFieldsCard.humanizeKey(e.key),
          valueColor: p == patterns[2] && !isDays ? AppColors.danger : null,
        ));
        break;
      }
    }
    final tasks = tasksAsync.valueOrNull;
    String n(bool Function(Task) test) =>
        tasks == null ? '—' : '${tasks.where(test).length}';
    final taskCells = [
      ProKpi(
        value: n((t) =>
            t.status == TaskStatuses.todo ||
            t.status == TaskStatuses.inProgress ||
            t.status == TaskStatuses.inReview),
        label: 'Open tasks',
      ),
      ProKpi(
        value: n((t) => t.status == TaskStatuses.done),
        label: 'Completed',
        valueColor: AppColors.success,
      ),
      ProKpi(value: tasks == null ? '—' : '${tasks.length}', label: 'Total tasks'),
    ];
    for (final t in taskCells) {
      if (cells.length >= 3) break;
      cells.add(t);
    }
    return cells;
  }

  static final _inr = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);

  /// Formats a numeric field value as rupees; anything else is shown as is.
  static String _money(String raw) {
    final n = num.tryParse(raw.replaceAll(RegExp(r'[₹,\s]'), ''));
    if (n == null) return raw;
    return '₹ ${_inr.format(n)}';
  }

  static String _sentence(String raw) {
    final s = raw.replaceAll('_', ' ').trim().toLowerCase();
    if (s.isEmpty) return raw;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ─────────────────────────────── Contact ──────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final rows = <MapEntry<String, String>>[
      if (c.mobileNumber != null && c.mobileNumber!.isNotEmpty)
        MapEntry('Mobile', c.mobileNumber!),
      if (c.email != null && c.email!.isNotEmpty) MapEntry('Email', c.email!),
      if (c.address != null && c.address!.isNotEmpty)
        MapEntry('Address', c.address!),
      if (c.branchName != null && c.branchName!.isNotEmpty)
        MapEntry(Branding.current.term('branch'), c.branchName!),
      if (c.assignedEmployeeName != null && c.assignedEmployeeName!.isNotEmpty)
        MapEntry('Account owner', c.assignedEmployeeName!),
      if (c.createdBy != null && c.createdBy!.isNotEmpty)
        MapEntry(
            'Created by',
            c.createdAt != null
                ? '${c.createdBy} · ${DateFormat('d MMM y').format(c.createdAt!)}'
                : c.createdBy!),
      if (c.updatedBy != null && c.updatedBy!.isNotEmpty)
        MapEntry(
            'Last updated',
            c.updatedAt != null
                ? '${c.updatedBy} · ${DateFormat('d MMM y').format(c.updatedAt!)}'
                : c.updatedBy!),
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Contact and ownership'),
          const SizedBox(height: 4),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No contact details on file.', style: AppText.caption),
            )
          else
            ProKeyValue(rows: rows),
        ],
      ),
    );
  }
}

// ─────────────────────────── Custom fields ────────────────────────────────

/// Renders every dynamic custom field from the customer response as a
/// label/value table (insertion order preserved).
class _CustomFieldsCard extends StatelessWidget {
  const _CustomFieldsCard({required this.fields});
  final Map<String, dynamic> fields;

  static String humanizeKey(String key) {
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

  /// Reads a "lat, long" pair out of a value (fields like LatLong are plain
  /// text). Both halves must carry decimals and sit in geographic range, so
  /// ordinary numbers never become a map link by accident.
  static ({double lat, double lng})? _latLng(dynamic v) {
    if (v == null) return null;
    final cleaned = v.toString().trim().replaceAll(RegExp(r'^[(\[]|[)\]]$'), '').trim();
    final m = RegExp(r'^(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)$').firstMatch(cleaned);
    if (m == null) return null;
    final lat = double.parse(m.group(1)!);
    final lng = double.parse(m.group(2)!);
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return (lat: lat, lng: lng);
  }

  static Future<void> _openMap(double lat, double lng) async {
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = fields.entries.toList();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Details'),
          const SizedBox(height: 4),
          for (var i = 0; i < entries.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: AppColors.hairlineSoft)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      humanizeKey(entries[i].key),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Builder(builder: (_) {
                      final coords = _latLng(entries[i].value);
                      final text = Text(
                        _formatValue(entries[i].value),
                        textAlign: TextAlign.right,
                        style: AppText.number.copyWith(
                          fontSize: 14,
                          color: coords == null ? AppColors.ink : AppColors.primary,
                          fontWeight: FontWeight.w500,
                          decoration: coords == null ? null : TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                      );
                      if (coords == null) return text;
                      // Coordinates open the location in Google Maps.
                      return InkWell(
                        onTap: () => _openMap(coords.lat, coords.lng),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(child: text),
                            const SizedBox(width: 4),
                            Icon(Icons.place_outlined,
                                size: 15, color: AppColors.primary),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
        ],
      ),
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
      return const ProEmpty(
        icon: Icons.fact_check_outlined,
        title: 'No tasks yet for this customer',
        message: 'Tap “Perform task” to start one.',
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }

  Widget _group(String label, String status, List<Task> group) {
    final color = statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          ProListGroup(
            children: [
              for (final t in group) _taskRow(t, color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taskRow(Task task, Color color) {
    final due = task.dueDate == null
        ? null
        : DateFormat('d MMM y').format(task.dueDate!);
    final sub = [
      if (task.taskCode != null && task.taskCode!.isNotEmpty) task.taskCode!,
      if (due != null) 'Due $due',
    ].join(' · ');
    return ProListRow(
      leading: ProIconWell(icon: Icons.assignment_outlined, color: color),
      title: task.title,
      titleMaxLines: 2,
      subtitle: sub.isEmpty ? null : sub,
      pill: TaskStatusPill(status: task.status),
      onTap: () => onOpen(task),
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
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFC6D3D6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose a task',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick the task you want to perform for this customer.',
                  style: AppText.caption,
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
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
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
            ProChipBar(
              labels: const ['All', ..._kTemplateFilters],
              selected: _filter == null ? 0 : _kTemplateFilters.indexOf(_filter!) + 1,
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
            const Divider(height: 1, color: AppColors.hairline),
            // ── Template list ───────────────────────────────────────────
            Expanded(
              child: ColoredBox(
                color: AppColors.bg,
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: ProNote('Could not load tasks: $e', tone: ProNoteTone.bad),
                  ),
                  data: (all) {
                    if (all.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: ProEmpty(
                          icon: Icons.assignment_outlined,
                          title: 'No task templates',
                          message:
                              'No customer task templates are available. Ask your admin to publish one.',
                        ),
                      );
                    }
                    final templates = _visible(all);
                    if (templates.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: ProEmpty(
                          icon: Icons.search_off_rounded,
                          title: 'No matches',
                          message: 'No templates match your search.',
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
                          16, 14, 16, mq.padding.bottom + 24),
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
            ),
          ],
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
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            // Arrow + icon stay vertically centred against the (variable-height)
            // text block.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProIconWell(icon: Icons.assignment_outlined, color: accent, size: 40),
              const SizedBox(width: 12),
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
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                        height: 1.3,
                      ),
                    ),
                    if (t.description != null && t.description!.isNotEmpty) ...[
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
