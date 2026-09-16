import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'mail_models.dart';
import 'mail_repository.dart';
import 'mail_status_ui.dart';

final mailBranchesProvider = FutureProvider.autoDispose<List<MailBranchOption>>((ref) {
  return ref.watch(mailRepositoryProvider).listBranches();
});

final mailRecordsProvider =
    FutureProvider.autoDispose.family<List<MailRecord>, String?>((ref, mailType) {
  return ref.watch(mailRepositoryProvider).listRecords(mailType: mailType, size: 100);
});

final mailAuditMonthsProvider =
    FutureProvider.autoDispose.family<List<MailAuditBranchMonth>, String>((ref, month) {
  return ref.watch(mailRepositoryProvider).listAuditMonths(month);
});

final mailStockForBranchProvider =
    FutureProvider.autoDispose.family<List<MailStockEntry>, int>((ref, branchId) {
  return ref.watch(mailRepositoryProvider).listStockForBranch(branchId);
});

final mailShipmentsProvider = FutureProvider.autoDispose<List<MailShipment>>((ref) {
  return ref.watch(mailRepositoryProvider).listShipments();
});

final mailComplaintsProvider = FutureProvider.autoDispose<List<MailComplaint>>((ref) {
  return ref.watch(mailRepositoryProvider).listComplaints(size: 100);
});

final mailComplaintDeptsProvider =
    FutureProvider.autoDispose.family<List<MailComplaintDept>, bool>((ref, activeOnly) {
  return ref.watch(mailRepositoryProvider).listComplaintDepartments(activeOnly: activeOnly);
});

final mailAuditTrailProvider = FutureProvider.autoDispose<List<MailAuditLog>>((ref) {
  return ref.watch(mailRepositoryProvider).auditTrail();
});

DateTime _thisMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
}

enum _MailTab { records, audits, stock, complaints, departments, trail }

/// Admin Tools · Mail Record — mail register / branch-month audits /
/// stationery stock & inter-branch shipments / complaints / complaint
/// departments / audit trail, mirroring `AdminMailPage.tsx`'s six tabs. The
/// biggest and most complex of the four ported Admin Tools screens.
class MailListScreen extends ConsumerStatefulWidget {
  const MailListScreen({super.key});

  @override
  ConsumerState<MailListScreen> createState() => _MailListScreenState();
}

class _MailListScreenState extends ConsumerState<MailListScreen> {
  _MailTab _tab = _MailTab.records;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canManageRecord = user?.hasPermission('ADMIN_MAIL_RECORD_MANAGE') ?? false;
    final canRaiseComplaint = user?.hasPermission('ADMIN_MAIL_COMPLAINT_RAISE') ?? false;
    final canConfigDept = user?.hasPermission('ADMIN_MAIL_COMPLAINT_CONFIG') ?? false;
    final canViewAuditTrail = user?.hasPermission('ADMIN_MAIL_AUDIT_LOG_VIEW') ?? false;
    final mq = MediaQuery.of(context);

    final tabs = <_MailTab, String>{
      _MailTab.records: 'Register',
      _MailTab.audits: 'Branch Audits',
      _MailTab.stock: 'Stock & Shipments',
      _MailTab.complaints: 'Complaints',
      if (canConfigDept) _MailTab.departments: 'Departments',
      if (canViewAuditTrail) _MailTab.trail: 'Audit Trail',
    };
    if (!tabs.containsKey(_tab)) _tab = _MailTab.records;

    Future<void> Function()? fab;
    String? fabLabel;
    IconData? fabIcon;
    switch (_tab) {
      case _MailTab.records:
        if (canManageRecord) {
          fabLabel = 'New entry';
          fabIcon = Icons.add_rounded;
          fab = () async {
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
            if (ok == true) ref.invalidate(mailComplaintsProvider);
          };
        }
        break;
      case _MailTab.departments:
        if (canConfigDept) {
          fabLabel = 'Add department';
          fabIcon = Icons.add_rounded;
          fab = () async {
            final ok = await context.push<bool>('/admin/mail/complaint-departments/new');
            if (ok == true) {
              ref.invalidate(mailComplaintDeptsProvider(false));
              ref.invalidate(mailComplaintDeptsProvider(true));
            }
          };
        }
        break;
      case _MailTab.audits:
      case _MailTab.stock:
      case _MailTab.trail:
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
                _MailTab.records => _RecordsTab(
                    canManage: canManageRecord,
                    canDelete: user?.hasPermission('ADMIN_MAIL_RECORD_DELETE') ?? false,
                    bottomPadding: mq.padding.bottom + 90,
                  ),
                _MailTab.audits => _AuditsTab(
                    canManage: user?.hasPermission('ADMIN_MAIL_AUDIT_MANAGE') ?? false,
                    bottomPadding: mq.padding.bottom + 24,
                  ),
                _MailTab.stock => _StockTab(
                    canManage: user?.hasPermission('ADMIN_MAIL_STOCK_MANAGE') ?? false,
                    bottomPadding: mq.padding.bottom + 24,
                  ),
                _MailTab.complaints => _ComplaintsTab(
                    canManage: user?.hasPermission('ADMIN_MAIL_COMPLAINT_MANAGE') ?? false,
                    bottomPadding: mq.padding.bottom + 90,
                  ),
                _MailTab.departments => _DepartmentsTab(bottomPadding: mq.padding.bottom + 90),
                _MailTab.trail => _AuditTrailTab(bottomPadding: mq.padding.bottom + 24),
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
  const _RecordsTab({required this.canManage, required this.canDelete, required this.bottomPadding});
  final bool canManage;
  final bool canDelete;
  final double bottomPadding;

  @override
  ConsumerState<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends ConsumerState<_RecordsTab> {
  String? _typeFilter;

  Future<void> _open(MailRecord r) async {
    final ok = await context.push<bool>('/admin/mail/records/${r.id}');
    if (ok == true) ref.invalidate(mailRecordsProvider(_typeFilter));
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
      ref.invalidate(mailRecordsProvider(_typeFilter));
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
    final async = ref.watch(mailRecordsProvider(_typeFilter));
    final df = DateFormat('d MMM yyyy');
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(mailRecordsProvider(_typeFilter)),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _typeFilter == null, onTap: () => setState(() => _typeFilter = null)),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Inward',
                  selected: _typeFilter == MailType.inward,
                  onTap: () => setState(() => _typeFilter = MailType.inward),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Outward',
                  selected: _typeFilter == MailType.outward,
                  onTap: () => setState(() => _typeFilter = MailType.outward),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: mailRecordIcon,
                  message: 'No mail records yet. Tap "New entry" to log one.',
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
              onRetry: () => ref.invalidate(mailRecordsProvider(_typeFilter)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.14) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: selected ? AppColors.primary.withOpacity(0.4) : AppColors.hairline),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.primary : AppColors.muted)),
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

// ── Branch audits tab ───────────────────────────────────────────────────────

class _AuditsTab extends ConsumerStatefulWidget {
  const _AuditsTab({required this.canManage, required this.bottomPadding});
  final bool canManage;
  final double bottomPadding;

  @override
  ConsumerState<_AuditsTab> createState() => _AuditsTabState();
}

class _AuditsTabState extends ConsumerState<_AuditsTab> {
  DateTime _month = _thisMonth();
  int? _branchId;
  bool _starting = false;
  int? _busyId;

  String get _monthIso => isoMonth(_month);

  Future<void> _pickMonth() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (d != null) setState(() => _month = DateTime(d.year, d.month, 1));
  }

  Future<void> _start() async {
    if (_branchId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a branch first.')));
      return;
    }
    setState(() => _starting = true);
    try {
      await ref.read(mailRepositoryProvider).startAuditMonth(_monthIso, _branchId!);
      ref.invalidate(mailAuditMonthsProvider(_monthIso));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _complete(int id) async {
    setState(() => _busyId = id);
    try {
      await ref.read(mailRepositoryProvider).completeAuditMonth(id);
      ref.invalidate(mailAuditMonthsProvider(_monthIso));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mailAuditMonthsProvider(_monthIso));
    final branchesAsync = ref.watch(mailBranchesProvider);
    final dfMonth = DateFormat('MMMM yyyy');

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(mailAuditMonthsProvider(_monthIso)),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          InkWell(
            onTap: _pickMonth,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_rounded, size: 15, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(dfMonth.format(_month), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 12),
            branchesAsync.when(
              data: (branches) => Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _branchId,
                      decoration: const InputDecoration(labelText: 'Branch to start'),
                      items: [
                        for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.label)),
                      ],
                      onChanged: (v) => setState(() => _branchId = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _starting ? null : _start,
                    child: Text(_starting ? 'Starting…' : 'Start'),
                  ),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
          const SizedBox(height: 12),
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.fact_check_rounded,
                  message: 'No audits started for this month.',
                );
              }
              return Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AuditCard(
                        row: r,
                        busy: _busyId == r.id,
                        canManage: widget.canManage,
                        onComplete: () => _complete(r.id),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(mailAuditMonthsProvider(_monthIso)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.row, required this.busy, required this.canManage, required this.onComplete});
  final MailAuditBranchMonth row;
  final bool busy;
  final bool canManage;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final tone = mailAuditStatusTone(row.status);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.branchLabel,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          const SizedBox(height: 8),
          if (row.startedBy != null)
            Text('Started by ${row.startedBy}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (row.completedBy != null)
            Text('Completed by ${row.completedBy}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (canManage && row.status == MailAuditStatus.inProgress) ...[
            const Divider(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 32,
                child: FilledButton(
                  onPressed: busy ? null : onComplete,
                  child: Text(busy ? 'Completing…' : 'Complete'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stock & shipments tab ───────────────────────────────────────────────────

class _StockTab extends ConsumerStatefulWidget {
  const _StockTab({required this.canManage, required this.bottomPadding});
  final bool canManage;
  final double bottomPadding;

  @override
  ConsumerState<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends ConsumerState<_StockTab> {
  int? _branchId;
  final Map<int, String> _receiveQty = {};

  Future<void> _setStock() async {
    if (_branchId == null) return;
    final item = TextEditingController();
    final qty = TextEditingController(text: '0');
    final unit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: item, decoration: const InputDecoration(labelText: 'Item name *')),
            const SizedBox(height: 10),
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity *'),
            ),
            const SizedBox(height: 10),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || item.text.trim().isEmpty) return;
    try {
      await ref.read(mailRepositoryProvider).setStock(
            branchId: _branchId!,
            itemName: item.text.trim(),
            quantity: num.tryParse(qty.text) ?? 0,
            unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
          );
      ref.invalidate(mailStockForBranchProvider(_branchId!));
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
    final shipmentsAsync = ref.watch(mailShipmentsProvider);

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
          const AppSectionHeader(title: 'Branch stock'),
          const SizedBox(height: 8),
          branchesAsync.when(
            data: (branches) => Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _branchId,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [
                      for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.label)),
                    ],
                    onChanged: (v) => setState(() => _branchId = v),
                  ),
                ),
                if (widget.canManage && _branchId != null) ...[
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: _setStock,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Set stock',
                  ),
                ],
              ],
            ),
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
                                  child: Text(rows[i].itemName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                ),
                                Text('${rows[i].quantity}${rows[i].unit != null ? ' ${rows[i].unit}' : ''}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
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
          const SizedBox(height: 20),
          AppSectionHeader(
            title: 'Shipments',
            trailing: widget.canManage
                ? TextButton.icon(
                    onPressed: _dispatch,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Dispatch'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          shipmentsAsync.when(
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
                        canManage: widget.canManage,
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
      ),
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

class _ComplaintsTab extends ConsumerWidget {
  const _ComplaintsTab({required this.canManage, required this.bottomPadding});
  final bool canManage;
  final double bottomPadding;

  Future<void> _open(BuildContext context, WidgetRef ref, MailComplaint c) async {
    final ok = await context.push<bool>('/admin/mail/complaints/${c.id}');
    if (ok == true) ref.invalidate(mailComplaintsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mailComplaintsProvider);
    final df = DateFormat('d MMM yyyy');
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(mailComplaintsProvider),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: mailComplaintIcon,
                  message: 'No complaints raised yet.',
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
                        onTap: () => _open(context, ref, c),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(mailComplaintsProvider),
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
            Text('${complaint.branchLabel} · ${complaint.deptName ?? 'No department'}',
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

// ── Departments tab ──────────────────────────────────────────────────────────

class _DepartmentsTab extends ConsumerWidget {
  const _DepartmentsTab({required this.bottomPadding});
  final double bottomPadding;

  Future<void> _open(BuildContext context, WidgetRef ref, MailComplaintDept d) async {
    final ok = await context.push<bool>('/admin/mail/complaint-departments/${d.id}');
    if (ok == true) {
      ref.invalidate(mailComplaintDeptsProvider(false));
      ref.invalidate(mailComplaintDeptsProvider(true));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, MailComplaintDept d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete department?'),
        content: Text('Delete department "${d.name}"?'),
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
      await ref.read(mailRepositoryProvider).deleteComplaintDepartment(d.id);
      ref.invalidate(mailComplaintDeptsProvider(false));
      ref.invalidate(mailComplaintDeptsProvider(true));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mailComplaintDeptsProvider(false));
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(mailComplaintDeptsProvider(false)),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.apartment_rounded,
                  message: 'No departments configured.',
                );
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
                                  Text(rows[i].name,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(rows[i].deptKey,
                                      style: const TextStyle(fontSize: 11, color: AppColors.muted, fontFamily: 'monospace')),
                                ],
                              ),
                            ),
                            if (!rows[i].active)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: StatusPill(label: 'Inactive', color: AppColors.muted),
                              ),
                            IconButton(
                              onPressed: () => _open(context, ref, rows[i]),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                            IconButton(
                              onPressed: () => _delete(context, ref, rows[i]),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
            loading: () => const AppLoadingBlock(height: 200),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(mailComplaintDeptsProvider(false)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Audit trail tab ──────────────────────────────────────────────────────────

class _AuditTrailTab extends ConsumerWidget {
  const _AuditTrailTab({required this.bottomPadding});
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mailAuditTrailProvider);
    final df = DateFormat('d MMM yyyy, HH:mm');
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(mailAuditTrailProvider),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.history_rounded,
                  message: 'No audit activity yet.',
                );
              }
              return GlassCard(
                padding: EdgeInsets.zero,
                shadow: AppShadows.soft,
                child: Column(
                  children: [
                    for (int i = 0; i < rows.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AuditRow(entry: rows[i], df: df),
                    ],
                  ],
                ),
              );
            },
            loading: () => const AppLoadingBlock(height: 200),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(mailAuditTrailProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry, required this.df});
  final MailAuditLog entry;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final tone = mailAuditActionTone(entry.action);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          StatusPill(label: tone.label, color: tone.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.entityType} #${entry.entityId ?? '—'}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.createdAt == null
                      ? (entry.actorName ?? 'system')
                      : '${df.format(entry.createdAt!)} · ${entry.actorName ?? 'system'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
