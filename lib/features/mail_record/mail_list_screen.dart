import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/report_download.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../team/employee_detail_repository.dart';
import 'mail_dashboard_tab.dart';
import 'mail_models.dart';
import 'mail_repository.dart';
import 'mail_status_ui.dart';

final mailBranchesProvider = FutureProvider.autoDispose<List<MailBranchOption>>((ref) {
  return ref.watch(mailRepositoryProvider).listBranches();
});

/// The signed-in user's own branch id — a branch employee's assigned branch, or an admin's home branch (matched by
/// name from their employee record) — so every branch dropdown in Mail Record can start on where they work.
final mailMyBranchIdProvider = FutureProvider.autoDispose<int?>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user == null) return null;
  if (user.branchIds.isNotEmpty) return user.branchIds.first;
  if (user.employeeId == null) return null;
  try {
    final branches = await ref.watch(mailBranchesProvider.future);
    final e = await ref.read(employeeDetailRepositoryProvider).getById(user.employeeId!);
    return branches.where((b) => b.label == e.branchLabel).map((b) => b.id).firstOrNull;
  } catch (_) {
    return null;
  }
});

/// What the Outward / Inward register lists are filtered by.
class MailRecordsQuery {
  const MailRecordsQuery({required this.mailType, this.branchId, this.range});
  final String mailType;
  final int? branchId;
  final DateTimeRange? range;

  @override
  bool operator ==(Object other) =>
      other is MailRecordsQuery &&
      other.mailType == mailType &&
      other.branchId == branchId &&
      other.range == range;

  @override
  int get hashCode => Object.hash(mailType, branchId, range);
}

final mailRecordsProvider =
    FutureProvider.autoDispose.family<List<MailRecord>, MailRecordsQuery>((ref, q) {
  final f = DateFormat('yyyy-MM-dd');
  return ref.watch(mailRepositoryProvider).listRecords(
        mailType: q.mailType,
        branchId: q.branchId,
        from: q.range == null ? null : f.format(q.range!.start),
        to: q.range == null ? null : f.format(q.range!.end),
        size: 200,
      );
});

/// Set by the Outward / Inward tab just before opening the entry form so it starts on that type.
final mailNewRecordTypeProvider = StateProvider<String?>((ref) => null);

final mailLowStockProvider = FutureProvider.autoDispose<List<MailLowStockRow>>((ref) {
  return ref.watch(mailRepositoryProvider).lowStock();
});

final mailStockForBranchProvider =
    FutureProvider.autoDispose.family<List<MailStockEntry>, int>((ref, branchId) {
  return ref.watch(mailRepositoryProvider).listStockForBranch(branchId);
});

final mailShipmentsProvider = FutureProvider.autoDispose<List<MailShipment>>((ref) {
  return ref.watch(mailRepositoryProvider).listShipments();
});

/// The complaints the caller may see (all of them for a full-access admin, otherwise only their own), optionally
/// limited to the dates they were raised on ([range], inclusive).
final mailComplaintsProvider =
    FutureProvider.autoDispose.family<List<MailComplaint>, DateTimeRange?>((ref, range) {
  return ref.watch(mailRepositoryProvider).listComplaints(size: 100, from: range?.start, to: range?.end);
});

/// Every day that has complaints, so the date filter can show where the data is.
final mailComplaintDatesProvider = FutureProvider.autoDispose<List<MailComplaintDate>>((ref) {
  return ref.watch(mailRepositoryProvider).complaintDates();
});

enum _MailTab { dashboard, outward, inward, stock, complaints }

/// Admin Tools · Mail Record — mail register /
/// stationery stock & inter-branch shipments / complaints / complaint
/// departments / audit trail, mirroring `AdminMailPage.tsx`'s six tabs. The
/// biggest and most complex of the four ported Admin Tools screens.
class MailListScreen extends ConsumerStatefulWidget {
  const MailListScreen({super.key});

  @override
  ConsumerState<MailListScreen> createState() => _MailListScreenState();
}

class _MailListScreenState extends ConsumerState<MailListScreen> {
  _MailTab _tab = _MailTab.dashboard;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canManageRecord = user?.hasPermission('ADMIN_MAIL_RECORD_MANAGE') ?? false;
    final canRaiseComplaint = user?.hasPermission('ADMIN_MAIL_COMPLAINT_RAISE') ?? false;
    final mq = MediaQuery.of(context);

    final tabs = <_MailTab, String>{
      _MailTab.dashboard: 'Dashboard',
      _MailTab.outward: 'Outward',
      _MailTab.inward: 'Inward',
      _MailTab.stock: 'Stock & Shipments',
      _MailTab.complaints: 'Complaints',
    };
    if (!tabs.containsKey(_tab)) _tab = _MailTab.dashboard;

    Future<void> Function()? fab;
    String? fabLabel;
    IconData? fabIcon;
    switch (_tab) {
      case _MailTab.outward:
      case _MailTab.inward:
        if (canManageRecord) {
          fabLabel = _tab == _MailTab.outward ? 'New outward' : 'New inward';
          fabIcon = Icons.add_rounded;
          fab = () async {
            ref.read(mailNewRecordTypeProvider.notifier).state =
                _tab == _MailTab.outward ? MailType.outward : MailType.inward;
            final ok = await context.push<bool>('/admin/mail/records/new');
            if (ok == true) ref.invalidate(mailRecordsProvider);
          };
        }
        break;
      case _MailTab.complaints:
        if (canRaiseComplaint) {
          fabLabel = 'Raise complaint';
          fabIcon = Icons.add_rounded;
          fab = () async {
            final ok = await context.push<bool>('/admin/mail/complaints/new');
            if (ok == true) {
              ref.invalidate(mailComplaintsProvider);
              ref.invalidate(mailComplaintDatesProvider);
            }
          };
        }
        break;
      case _MailTab.stock:
      case _MailTab.dashboard:
        break;
    }

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Mail Record'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        floatingActionButton: fab != null
            ? FloatingActionButton.extended(
                onPressed: () => fab!(),
                icon: Icon(fabIcon),
                label: Text(fabLabel!),
              )
            : null,
        body: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  for (final entry in tabs.entries)
                    _TabChip(
                      label: entry.value,
                      selected: _tab == entry.key,
                      onTap: () => setState(() => _tab = entry.key),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                _MailTab.dashboard => MailDashboardTab(bottomPadding: mq.padding.bottom + 24),
                _MailTab.outward || _MailTab.inward => _RecordsTab(
                    key: ValueKey(_tab),
                    mailType: _tab == _MailTab.outward ? MailType.outward : MailType.inward,
                    canManage: canManageRecord,
                    canDelete: user?.hasPermission('ADMIN_MAIL_RECORD_DELETE') ?? false,
                    bottomPadding: mq.padding.bottom + 90,
                  ),
                _MailTab.stock => _StockTab(
                    canManage: user?.hasPermission('ADMIN_MAIL_STOCK_MANAGE') ?? false,
                    isFullAccess: user?.hasPermission('DATA_SCOPE_ALL') ?? false,
                    bottomPadding: mq.padding.bottom + 24,
                  ),
                _MailTab.complaints => _ComplaintsTab(
                    canManage: user?.hasPermission('ADMIN_MAIL_COMPLAINT_MANAGE') ?? false,
                    bottomPadding: mq.padding.bottom + 90,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withOpacity(0.14) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
                color: selected ? AppColors.primary.withOpacity(0.4) : AppColors.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Register tab ────────────────────────────────────────────────────────────

class _RecordsTab extends ConsumerStatefulWidget {
  const _RecordsTab({super.key, required this.mailType, required this.canManage, required this.canDelete, required this.bottomPadding});
  final String mailType;
  final bool canManage;
  final bool canDelete;
  final double bottomPadding;

  @override
  ConsumerState<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends ConsumerState<_RecordsTab> {
  int? _branchId;
  bool _seeded = false;
  DateTimeRange? _range;

  String get _typeFilter => widget.mailType;

  MailRecordsQuery get _query => MailRecordsQuery(mailType: widget.mailType, branchId: _branchId, range: _range);

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _open(MailRecord r) async {
    final ok = await context.push<bool>('/admin/mail/records/${r.id}');
    if (ok == true) ref.invalidate(mailRecordsProvider(_query));
  }

  Future<void> _delete(MailRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete mail record?'),
        content: Text('Delete "${r.particular ?? r.docketNumber ?? '#${r.id}'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(mailRepositoryProvider).deleteRecord(r.id);
      ref.invalidate(mailRecordsProvider(_query));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Mail record deleted')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _history(MailRecord r) async {
    List<MailEditLog>? history;
    String? error;
    try {
      history = await ref.read(mailRepositoryProvider).recordEditHistory(r.id);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    final df = DateFormat('d MMM yyyy, HH:mm');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit history'),
        content: SizedBox(
          width: double.maxFinite,
          child: error != null
              ? Text(error, style: const TextStyle(color: AppColors.danger))
              : (history == null || history.isEmpty)
                  ? const Text('No edits recorded.', style: TextStyle(color: AppColors.muted))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (_, i) {
                        final h = history![i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '${h.fieldName}: ',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: '${h.oldValue ?? '—'} → ${h.newValue ?? '—'}'),
                            ])),
                            const SizedBox(height: 2),
                            Text(
                              '${h.editedBy ?? 'system'} · ${h.editedAt == null ? '—' : df.format(h.editedAt!)}',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ],
                        );
                      },
                    ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final my = ref.watch(mailMyBranchIdProvider);
    if (!_seeded && my.hasValue) {
      _branchId = my.value;
      _seeded = true;
    }
    final async = ref.watch(mailRecordsProvider(_query));
    final df = DateFormat('d MMM yyyy');
    // Which days have records (from the rows loaded for the current filter) - newest first.
    final dayCounts = <DateTime, int>{};
    for (final r in async.valueOrNull ?? const <MailRecord>[]) {
      if (r.date == null) continue;
      final day = DateTime(r.date!.year, r.date!.month, r.date!.day);
      dayCounts[day] = (dayCounts[day] ?? 0) + 1;
    }
    final orderedDays = dayCounts.keys.toList()..sort((a, b) => b.compareTo(a));
    final sortedCounts = {for (final k in orderedDays) k: dayCounts[k]!};
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(mailRecordsProvider(_query)),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          MailBranchSelector(
            value: _branchId,
            allowAll: true,
            onChanged: (v) => setState(() => _branchId = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(
                    _range == null ? 'All dates' : '${df.format(_range!.start)} – ${df.format(_range!.end)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_range != null)
                IconButton(
                  tooltip: 'Clear dates',
                  onPressed: () => setState(() => _range = null),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          if (sortedCounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Days with records',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in sortedCounts.entries.take(14))
                  ChoiceChip(
                    label: Text('${DateFormat('d MMM').format(e.key)} · ${e.value}'),
                    selected: _range != null &&
                        DateUtils.isSameDay(_range!.start, e.key) &&
                        DateUtils.isSameDay(_range!.end, e.key),
                    onSelected: (_) => setState(() => _range = DateTimeRange(start: e.key, end: e.key)),
                  ),
              ],
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => downloadExcelReport(
                context,
                () => ref.read(mailRepositoryProvider).exportRecords(mailType: _typeFilter),
                'mail-${widget.mailType.toLowerCase()}-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx',
              ),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download report'),
            ),
          ),
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: mailRecordIcon,
                  message: 'No mail records found. Tap the button below to log one.',
                );
              }
              return Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RecordCard(
                        record: r,
                        canManage: widget.canManage,
                        canDelete: widget.canDelete,
                        df: df,
                        onTap: widget.canManage ? () => _open(r) : null,
                        onHistory: () => _history(r),
                        onDelete: () => _delete(r),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(mailRecordsProvider(_query)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.canManage,
    required this.canDelete,
    required this.df,
    required this.onTap,
    required this.onHistory,
    required this.onDelete,
  });

  final MailRecord record;
  final bool canManage;
  final bool canDelete;
  final DateFormat df;
  final VoidCallback? onTap;
  final VoidCallback onHistory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tone = mailTypeTone(record.mailType);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.primary.withOpacity(0.22)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(mailRecordIcon, color: AppColors.primary, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    record.particular ?? record.docketNumber ?? 'Mail record #${record.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                ),
                StatusPill(label: tone.label, color: tone.color),
              ],
            ),
            const SizedBox(height: 10),
            _row(Icons.event_rounded, record.date == null ? '—' : df.format(record.date!)),
            const SizedBox(height: 6),
            _row(Icons.store_mall_directory_rounded, record.branchLabel ?? 'No branch'),
            if (record.docketNumber != null && record.docketNumber!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _row(Icons.confirmation_number_rounded, 'Docket: ${record.docketNumber}'),
            ],
            if (record.courierStatus != null && record.courierStatus!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _row(Icons.local_shipping_outlined, record.courierStatus!),
            ],
            if (record.amount != null) ...[
              const SizedBox(height: 6),
              _row(Icons.currency_rupee_rounded, 'Amount: ₹ ${record.amount!.toStringAsFixed(2)}'),
            ],
            const Divider(height: 20),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onHistory,
                  icon: const Icon(Icons.history_rounded, size: 15),
                  label: const Text('History'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                ),
                const Spacer(),
                if (canDelete)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                    tooltip: 'Delete',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}

// ── Stock & shipments tab ───────────────────────────────────────────────────

class _StockTab extends ConsumerStatefulWidget {
  const _StockTab({required this.canManage, required this.isFullAccess, required this.bottomPadding});
  final bool canManage;
  /// Full-access admin (`DATA_SCOPE_ALL`): the only one who can add items and who may pick any branch.
  final bool isFullAccess;
  final double bottomPadding;

  @override
  ConsumerState<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends ConsumerState<_StockTab> {
  int? _branchId;
  final Map<int, String> _receiveQty = {};

  @override
  void initState() {
    super.initState();
    // Start on the signed-in user's own branch. Only ever fills in an empty selection.
    ref.read(mailMyBranchIdProvider.future).then((id) {
      if (mounted && id != null) setState(() => _branchId ??= id);
    });
  }

  /// Full-access admins only (the server enforces it too). Adds an item at 0 — no quantity here; stock
  /// only changes through Stock in / Stock out.
  Future<void> _addItem() async {
    if (_branchId == null) return;
    final item = TextEditingController();
    final invoice = TextEditingController();
    final threshold = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: item, decoration: const InputDecoration(labelText: 'Item name *')),
            const SizedBox(height: 10),
            TextField(controller: invoice, decoration: const InputDecoration(labelText: 'Invoice')),
            const SizedBox(height: 10),
            TextField(
              controller: threshold,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Low stock threshold', hintText: 'Optional'),
            ),
            const SizedBox(height: 10),
            const Text('Shared by every branch. Each branch starts at 0 and uses Stock in / Stock out for its own quantity.',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final name = item.text.trim();
    if (ok != true || name.isEmpty) return;
    try {
      // The server treats an existing name as an edit; adding must never overwrite one. The branch list is the
      // shared item list, so it tells us whether the name is taken.
      final existing = await ref.read(mailStockForBranchProvider(_branchId!).future);
      if (existing.any((e) => e.itemName.toLowerCase() == name.toLowerCase())) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('"$name" is already in the item list.')));
        }
        return;
      }
      await ref.read(mailRepositoryProvider).addItem(
            itemName: name,
            invoice: invoice.text.trim().isEmpty ? null : invoice.text.trim(),
            lowStockThreshold: int.tryParse(threshold.text.trim()),
          );
      ref.invalidate(mailStockForBranchProvider(_branchId!));
      ref.invalidate(mailLowStockProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Stock in / out ([type] `IN` or `OUT`): pick an existing item, enter a quantity.
  Future<void> _adjust(String type) async {
    if (_branchId == null) return;
    final rows = await ref.read(mailStockForBranchProvider(_branchId!).future);
    final isOut = type == 'OUT';
    final eligible = isOut ? rows.where((r) => r.quantity > 0).toList() : rows;
    if (!mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isOut
              ? 'No items with available stock to remove.'
              : widget.isFullAccess
                  ? 'No items yet — add one first.'
                  : 'No items yet — ask an admin to add them.')));
      return;
    }
    MailStockEntry? picked;
    final qty = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isOut ? 'Stock out' : 'Stock in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<MailStockEntry>(
                isExpanded: true,
                value: picked,
                decoration: const InputDecoration(labelText: 'Item *'),
                items: [
                  for (final r in eligible)
                    DropdownMenuItem(
                      value: r,
                      child: Text('${r.itemName} — ${r.quantity} available', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setLocal(() => picked = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity *'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final amount = int.tryParse(qty.text.trim());
    if (ok != true) return;
    if (picked == null || amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pick an item and enter a quantity above 0.')));
      }
      return;
    }
    try {
      await ref.read(mailRepositoryProvider).adjustStock(
            branchId: _branchId!, itemName: picked!.itemName, type: type, quantity: amount);
      ref.invalidate(mailStockForBranchProvider(_branchId!));
      ref.invalidate(mailLowStockProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _dispatch() async {
    final ok = await context.push<bool>('/admin/mail/shipments/new');
    if (ok == true) {
      ref.invalidate(mailShipmentsProvider);
      if (_branchId != null) ref.invalidate(mailStockForBranchProvider(_branchId!));
    }
  }

  Future<void> _receive(MailShipment s) async {
    final qty = num.tryParse(_receiveQty[s.id] ?? '');
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a quantity to receive.')));
      return;
    }
    try {
      await ref.read(mailRepositoryProvider).receiveShipment(s.id, qty);
      setState(() => _receiveQty.remove(s.id));
      ref.invalidate(mailShipmentsProvider);
      if (_branchId != null) ref.invalidate(mailStockForBranchProvider(_branchId!));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(mailBranchesProvider);
    final shipmentsAsync = widget.isFullAccess ? ref.watch(mailShipmentsProvider) : null;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(mailShipmentsProvider);
        if (_branchId != null) ref.invalidate(mailStockForBranchProvider(_branchId!));
      },
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          if (widget.isFullAccess) ...[
            _LowStockPanel(onOpenBranch: (id) => setState(() => _branchId = id)),
            const SizedBox(height: 16),
          ],
          const AppSectionHeader(title: 'Branch stock'),
          const SizedBox(height: 8),
          branchesAsync.when(
            data: (allBranches) {
              // A branch-scoped user only ever sees their own branches.
              final assigned = ref.watch(authUserProvider)?.branchIds ?? const <int>{};
              final branches = widget.isFullAccess || assigned.isEmpty
                  ? allBranches
                  : allBranches.where((b) => assigned.contains(b.id)).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: branches.any((b) => b.id == _branchId) ? _branchId : null,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [
                      for (final b in branches)
                        DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _branchId = v),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => downloadExcelReport(
                        context,
                        () => ref.read(mailRepositoryProvider).exportStock(branchId: _branchId),
                        'stock-report-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx',
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download stock report'),
                    ),
                  ),
                  if (widget.canManage && _branchId != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.isFullAccess)
                          OutlinedButton.icon(
                            onPressed: _addItem,
                            icon: const Icon(Icons.add_box_outlined, size: 18),
                            label: const Text('Add item'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _adjust('IN'),
                          icon: const Icon(Icons.south_west_rounded, size: 18),
                          label: const Text('Stock in'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _adjust('OUT'),
                          icon: const Icon(Icons.north_east_rounded, size: 18),
                          label: const Text('Stock out'),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          if (_branchId != null) ...[
            const SizedBox(height: 10),
            Consumer(builder: (context, ref, __) {
              final stockAsync = ref.watch(mailStockForBranchProvider(_branchId!));
              return stockAsync.when(
                data: (rows) {
                  if (rows.isEmpty) {
                    return const AppEmptyState(icon: Icons.inventory_2_rounded, message: 'No stock recorded for this branch.');
                  }
                  return GlassCard(
                    padding: EdgeInsets.zero,
                    shadow: AppShadows.soft,
                    child: Column(
                      children: [
                        for (int i = 0; i < rows.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(rows[i].itemName,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                      if (rows[i].invoice != null && rows[i].invoice!.isNotEmpty)
                                        Text('Invoice: ${rows[i].invoice}',
                                            style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
                                    ],
                                  ),
                                ),
                                Text('${rows[i].quantity}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: rows[i].lowStock ? AppColors.danger : null)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const AppLoadingBlock(height: 100),
                error: (e, _) => AppErrorPanel(message: '$e'),
              );
            }),
          ],
          // Shipments are a full-access-admin feature; branch users only record stock in/out.
          if (widget.isFullAccess) ...[
          const SizedBox(height: 20),
          AppSectionHeader(
            title: 'Shipments',
            trailing: widget.canManage && widget.isFullAccess
                ? TextButton.icon(
                    onPressed: _dispatch,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Dispatch'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          shipmentsAsync!.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(icon: mailShipmentIcon, message: 'No shipments yet.');
              }
              return Column(
                children: [
                  for (final s in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ShipmentCard(
                        shipment: s,
                        canManage: widget.canManage && widget.isFullAccess,
                        qtyText: _receiveQty[s.id] ?? '',
                        onQtyChanged: (v) => setState(() => _receiveQty[s.id] = v),
                        onReceive: () => _receive(s),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(mailShipmentsProvider),
            ),
          ),
          ],
        ],
      ),
    );
  }
}

/// Full-access admins: which branches have hit an item's low-stock level, and on what. Tapping a branch
/// opens its stock below so it can be topped up.
class _LowStockPanel extends ConsumerWidget {
  const _LowStockPanel({required this.onOpenBranch});
  final void Function(int branchId) onOpenBranch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mailLowStockProvider);
    return async.when(
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        final byBranch = <int, List<MailLowStockRow>>{};
        for (final r in rows) {
          byBranch.putIfAbsent(r.branchId, () => []).add(r);
        }
        return GlassCard(
          padding: const EdgeInsets.all(14),
          shadow: AppShadows.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Low stock — ${byBranch.length} branch(es), ${rows.length} item(s)',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final entry in byBranch.entries)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${entry.value.first.branchLabel} (${entry.value.length})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  trailing: TextButton(
                    onPressed: () => onOpenBranch(entry.key),
                    child: const Text('Open'),
                  ),
                  children: [
                    for (final r in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(r.itemName, style: const TextStyle(fontSize: 12.5))),
                            Text('${r.quantity} / ${r.lowStockThreshold}',
                                style: const TextStyle(
                                    fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.danger)),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.shipment,
    required this.canManage,
    required this.qtyText,
    required this.onQtyChanged,
    required this.onReceive,
  });

  final MailShipment shipment;
  final bool canManage;
  final String qtyText;
  final ValueChanged<String> onQtyChanged;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final tone = mailShipmentStatusTone(shipment.status);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.primary.withOpacity(0.22)),
                ),
                alignment: Alignment.center,
                child: Icon(mailShipmentIcon, color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${shipment.fromBranchLabel} → ${shipment.toBranchLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          const SizedBox(height: 8),
          Text(shipment.itemName, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
          const SizedBox(height: 4),
          Text('${shipment.receivedQuantity} / ${shipment.quantity} received',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (canManage && shipment.status != MailShipmentStatus.received) ...[
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qty received', isDense: true),
                    controller: TextEditingController(text: qtyText)
                      ..selection = TextSelection.collapsed(offset: qtyText.length),
                    onChanged: onQtyChanged,
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(onPressed: onReceive, child: const Text('Receive')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Complaints tab ──────────────────────────────────────────────────────────

class _ComplaintsTab extends ConsumerStatefulWidget {
  const _ComplaintsTab({required this.canManage, required this.bottomPadding});
  final bool canManage;
  final double bottomPadding;

  @override
  ConsumerState<_ComplaintsTab> createState() => _ComplaintsTabState();
}

class _ComplaintsTabState extends ConsumerState<_ComplaintsTab> {
  /// Calendar filter on the day a complaint was raised; null = every date.
  DateTimeRange? _range;
  String? _status; // client-side status filter (null = all)

  Future<void> _open(MailComplaint c) async {
    final ok = await context.push<bool>('/admin/mail/complaints/${c.id}');
    if (ok == true) {
      ref.invalidate(mailComplaintsProvider);
      ref.invalidate(mailComplaintDatesProvider);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mailComplaintsProvider(_range));
    final dates = ref.watch(mailComplaintDatesProvider).valueOrNull ?? const <MailComplaintDate>[];
    final df = DateFormat('d MMM yyyy');
    final dayFmt = DateFormat('d MMM');
    bool isDay(MailComplaintDate d) =>
        _range != null && DateUtils.isSameDay(_range!.start, d.date) && DateUtils.isSameDay(_range!.end, d.date);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(mailComplaintsProvider);
        ref.invalidate(mailComplaintDatesProvider);
      },
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(
                    _range == null ? 'All dates' : '${df.format(_range!.start)} – ${df.format(_range!.end)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_range != null)
                IconButton(
                  tooltip: 'Clear dates',
                  onPressed: () => setState(() => _range = null),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          if (dates.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Dates with complaints',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final d in dates.take(14))
                  ChoiceChip(
                    label: Text('${dayFmt.format(d.date)} · ${d.count}'),
                    selected: isDay(d),
                    onSelected: (_) => setState(() => _range = DateTimeRange(start: d.date, end: d.date)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (async.hasValue)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final s in <String?>[null, ...MailComplaintStatus.values])
                  ChoiceChip(
                    label: Text(
                        '${s == null ? 'All' : mailComplaintStatusTone(s).label} (${s == null ? async.value!.length : async.value!.where((c) => c.status == s).length})'),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          async.when(
            data: (all) {
              final rows = _status == null ? all : all.where((c) => c.status == _status).toList();
              if (rows.isEmpty) {
                return AppEmptyState(
                  icon: mailComplaintIcon,
                  message: _range != null && dates.isNotEmpty
                      ? 'No complaints in this date range — pick one of the dates above.'
                      : 'No complaints found.',
                );
              }
              return Column(
                children: [
                  for (final c in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ComplaintCard(
                        complaint: c,
                        df: df,
                        onTap: () => _open(c),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(mailComplaintsProvider(_range)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint, required this.df, required this.onTap});
  final MailComplaint complaint;
  final DateFormat df;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = mailComplaintStatusTone(complaint.status);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.primary.withOpacity(0.22)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(mailComplaintIcon, color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(complaint.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                StatusPill(label: tone.label, color: tone.color),
              ],
            ),
            const SizedBox(height: 8),
            Text('${complaint.branchLabel} · ${complaint.department ?? 'No department'}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
            const SizedBox(height: 4),
            Text(complaint.date == null ? '—' : df.format(complaint.date!),
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
