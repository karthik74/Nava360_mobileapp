import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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

    final tabs = <_MailTab, String>{
      _MailTab.dashboard: 'Dashboard',
      _MailTab.outward: 'Outward',
      _MailTab.inward: 'Inward',
      _MailTab.stock: 'Stock & shipments',
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

    // Section switcher shown under each tab's hero.
    final keys = tabs.keys.toList();
    final nav = ProChipBar(
      labels: tabs.values.toList(),
      selected: keys.indexOf(_tab),
      onSelected: (i) => setState(() => _tab = keys[i]),
      bleed: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mail record')),
      floatingActionButton: fab != null
          ? FloatingActionButton.extended(
              onPressed: () => fab!(),
              icon: Icon(fabIcon),
              label: Text(fabLabel!),
            )
          : null,
      body: switch (_tab) {
        _MailTab.dashboard => MailDashboardTab(bottomPadding: 24, nav: nav),
        _MailTab.outward || _MailTab.inward => _RecordsTab(
            key: ValueKey(_tab),
            mailType: _tab == _MailTab.outward ? MailType.outward : MailType.inward,
            canManage: canManageRecord,
            canDelete: user?.hasPermission('ADMIN_MAIL_RECORD_DELETE') ?? false,
            bottomPadding: 90,
            nav: nav,
          ),
        _MailTab.stock => _StockTab(
            canManage: user?.hasPermission('ADMIN_MAIL_STOCK_MANAGE') ?? false,
            isFullAccess: user?.hasPermission('DATA_SCOPE_ALL') ?? false,
            bottomPadding: 24,
            nav: nav,
          ),
        _MailTab.complaints => _ComplaintsTab(
            canManage: user?.hasPermission('ADMIN_MAIL_COMPLAINT_MANAGE') ?? false,
            bottomPadding: 90,
            nav: nav,
          ),
      },
    );
  }
}

/// Page padding for a tab: [extra] clears the FAB (system inset is added by
/// [ProPage]).
EdgeInsets _pagePadding(double extra) => EdgeInsets.fromLTRB(16, 16, 16, extra);

/// Date-range button row ("All dates" / "1 Oct – 5 Oct") with a clear action.
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.range, required this.onPick, required this.onClear});
  final DateTimeRange? range;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(
              range == null ? 'All dates' : '${df.format(range!.start)} – ${df.format(range!.end)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (range != null) ...[
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Clear dates',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ],
    );
  }
}

// ── Register tab ────────────────────────────────────────────────────────────

class _RecordsTab extends ConsumerStatefulWidget {
  const _RecordsTab({
    super.key,
    required this.mailType,
    required this.canManage,
    required this.canDelete,
    required this.bottomPadding,
    required this.nav,
  });
  final String mailType;
  final bool canManage;
  final bool canDelete;
  final double bottomPadding;
  final Widget nav;

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
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              TextSpan(text: '${h.oldValue ?? '—'} → ${h.newValue ?? '—'}'),
                            ])),
                            const SizedBox(height: 2),
                            Text(
                              '${h.editedBy ?? 'system'} · ${h.editedAt == null ? '—' : df.format(h.editedAt!)}',
                              style: AppText.caption,
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
    final isOutward = widget.mailType == MailType.outward;
    final all = async.valueOrNull ?? const <MailRecord>[];
    // Which days have records (from the rows loaded for the current filter) - newest first.
    final dayCounts = <DateTime, int>{};
    for (final r in all) {
      if (r.date == null) continue;
      final day = DateTime(r.date!.year, r.date!.month, r.date!.day);
      dayCounts[day] = (dayCounts[day] ?? 0) + 1;
    }
    final orderedDays = dayCounts.keys.toList()..sort((a, b) => b.compareTo(a));
    final sortedCounts = {for (final k in orderedDays) k: dayCounts[k]!};
    final dayChips = sortedCounts.entries.take(14).toList();
    final selectedDay = dayChips.indexWhere((e) =>
        _range != null && DateUtils.isSameDay(_range!.start, e.key) && DateUtils.isSameDay(_range!.end, e.key));
    final today = DateUtils.dateOnly(DateTime.now());
    final todayCount = dayCounts[today] ?? 0;
    final amount = all.fold<double>(0, (s, r) => s + (r.amount ?? 0));
    final withDocket = all.where((r) => (r.docketNumber ?? '').isNotEmpty).length;
    String v(String s) => async.hasValue ? s : '—';

    return ProPage(
      onRefresh: () async => ref.invalidate(mailRecordsProvider(_query)),
      padding: _pagePadding(widget.bottomPadding),
      hero: ProHero(
        title: isOutward ? 'Outward register' : 'Inward register',
        subtitle: isOutward ? 'Mail sent out from the branch' : 'Mail received at the branch',
        children: [
          ProHeroStats(stats: [
            ProStat(
              label: 'Records',
              value: v('${all.length}'),
              sub: _range == null ? 'all dates' : 'in range',
              dot: isOutward ? const Color(0xFFF2B347) : const Color(0xFF9FCBD5),
            ),
            ProStat(label: 'Today', value: v('$todayCount'), sub: DateFormat('d MMM').format(today), dot: AppColors.live),
            if (isOutward)
              ProStat(label: 'Amount', value: v('₹ ${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(amount)}'), sub: 'courier charges')
            else
              ProStat(label: 'With docket', value: v('$withDocket'), sub: 'tracked'),
          ]),
        ],
      ),
      children: [
        widget.nav,
        MailBranchSelector(
          value: _branchId,
          allowAll: true,
          onChanged: (v) => setState(() => _branchId = v),
        ),
        _RangeBar(
          range: _range,
          onPick: _pickRange,
          onClear: () => setState(() => _range = null),
        ),
        if (dayChips.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Days with records', small: true),
              const SizedBox(height: 8),
              ProChipBar(
                labels: [for (final e in dayChips) DateFormat('d MMM').format(e.key)],
                counts: [for (final e in dayChips) e.value],
                selected: selectedDay,
                onSelected: (i) =>
                    setState(() => _range = DateTimeRange(start: dayChips[i].key, end: dayChips[i].key)),
                bleed: 0,
              ),
            ],
          ),
        async.when(
          data: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: '${isOutward ? 'Outward' : 'Inward'} records · ${rows.length}',
                small: true,
                trailing: TextButton.icon(
                  onPressed: () => downloadExcelReport(
                    context,
                    () => ref.read(mailRepositoryProvider).exportRecords(mailType: _typeFilter),
                    'mail-${widget.mailType.toLowerCase()}-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx',
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download report'),
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const ProEmpty(
                  icon: mailRecordIcon,
                  title: 'No mail records found',
                  message: 'Tap the button below to log one.',
                )
              else ...[
                ProSwipeHint(
                  text: widget.canDelete
                      ? 'Swipe right for history, left to delete'
                      : 'Swipe right to see the edit history',
                ),
                const SizedBox(height: 10),
                ProListGroup(
                  children: [
                    for (final r in rows)
                      ProSwipeDecision(
                        onApprove: () => _history(r),
                        approveLabel: 'History',
                        approveIcon: Icons.history_rounded,
                        approveColor: AppColors.info,
                        onReject: widget.canDelete ? () => _delete(r) : null,
                        rejectLabel: 'Delete',
                        rejectIcon: Icons.delete_outline_rounded,
                        child: _RecordRow(
                          record: r,
                          canDelete: widget.canDelete,
                          df: df,
                          onTap: widget.canManage ? () => _open(r) : null,
                          onHistory: () => _history(r),
                          onDelete: () => _delete(r),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          loading: () => const AppLoadingBlock(height: 160),
          error: (e, _) => AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(mailRecordsProvider(_query)),
          ),
        ),
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.canDelete,
    required this.df,
    required this.onTap,
    required this.onHistory,
    required this.onDelete,
  });

  final MailRecord record;
  final bool canDelete;
  final DateFormat df;
  final VoidCallback? onTap;
  final VoidCallback onHistory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tone = mailTypeTone(record.mailType);
    final meta = [
      if (record.docketNumber != null && record.docketNumber!.isNotEmpty) 'Docket ${record.docketNumber}',
      if (record.courierStatus != null && record.courierStatus!.isNotEmpty) record.courierStatus!,
      if (record.amount != null) '₹ ${record.amount!.toStringAsFixed(2)}',
    ].join(' · ');
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(icon: mailRecordIcon, color: tone.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.particular ?? record.docketNumber ?? 'Mail record #${record.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, height: 1.33, fontWeight: FontWeight.w500, color: AppColors.ink),
                    ),
                    Text(
                      '${record.date == null ? '—' : df.format(record.date!)} · ${record.branchLabel ?? 'No branch'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.merge(AppText.number),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.number.copyWith(
                            fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.inkSoft),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: mailTonePill(tone),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: onHistory,
                        tooltip: 'History',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.history_rounded, size: 18, color: AppColors.muted),
                      ),
                      if (canDelete)
                        IconButton(
                          onPressed: onDelete,
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stock & shipments tab ───────────────────────────────────────────────────

class _StockTab extends ConsumerStatefulWidget {
  const _StockTab({
    required this.canManage,
    required this.isFullAccess,
    required this.bottomPadding,
    required this.nav,
  });
  final bool canManage;
  /// Full-access admin (`DATA_SCOPE_ALL`): the only one who can add items and who may pick any branch.
  final bool isFullAccess;
  final double bottomPadding;
  final Widget nav;

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
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
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
    final stockRows =
        _branchId == null ? null : ref.watch(mailStockForBranchProvider(_branchId!)).valueOrNull;
    final shipments = shipmentsAsync?.valueOrNull;
    final inTransit = shipments?.where((s) => s.status != MailShipmentStatus.received).length;

    return ProPage(
      onRefresh: () async {
        ref.invalidate(mailShipmentsProvider);
        if (_branchId != null) ref.invalidate(mailStockForBranchProvider(_branchId!));
      },
      padding: _pagePadding(widget.bottomPadding),
      hero: ProHero(
        title: 'Stock & shipments',
        subtitle: 'Stationery stock by branch',
        children: [
          ProHeroStats(stats: [
            ProStat(
              label: 'Items',
              value: stockRows == null ? '—' : '${stockRows.length}',
              sub: 'in this branch',
              dot: const Color(0xFF9FCBD5),
            ),
            ProStat(
              label: 'Low stock',
              value: stockRows == null ? '—' : '${stockRows.where((r) => r.lowStock).length}',
              sub: 'need a top-up',
              dot: const Color(0xFFE5484D),
            ),
            if (widget.isFullAccess)
              ProStat(
                label: 'On the way',
                value: inTransit == null ? '—' : '$inTransit',
                sub: 'shipments',
                dot: const Color(0xFFF2B347),
              ),
          ]),
        ],
      ),
      children: [
        widget.nav,
        if (widget.isFullAccess) _LowStockPanel(onOpenBranch: (id) => setState(() => _branchId = id)),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: 'Branch stock',
                trailing: TextButton.icon(
                  onPressed: () => downloadExcelReport(
                    context,
                    () => ref.read(mailRepositoryProvider).exportStock(branchId: _branchId),
                    'stock-report-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx',
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Stock report'),
                ),
              ),
              const SizedBox(height: 10),
              branchesAsync.when(
                data: (allBranches) {
                  // A branch-scoped user only ever sees their own branches.
                  final assigned = ref.watch(authUserProvider)?.branchIds ?? const <int>{};
                  final branches = widget.isFullAccess || assigned.isEmpty
                      ? allBranches
                      : allBranches.where((b) => assigned.contains(b.id)).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: branches.any((b) => b.id == _branchId) ? _branchId : null,
                        decoration: const InputDecoration(
                          labelText: 'Branch',
                          prefixIcon: Icon(Icons.store_mall_directory_outlined, size: 19),
                        ),
                        items: [
                          for (final b in branches)
                            DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _branchId = v),
                      ),
                      if (widget.canManage && _branchId != null) ...[
                        const SizedBox(height: 12),
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
            ],
          ),
        ),
        if (_branchId != null)
          Consumer(builder: (context, ref, __) {
            final stockAsync = ref.watch(mailStockForBranchProvider(_branchId!));
            return stockAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const ProEmpty(
                    icon: Icons.inventory_2_rounded,
                    title: 'No stock recorded for this branch.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProSectionHeader(title: 'Items · ${rows.length}', small: true),
                    const SizedBox(height: 8),
                    ProListGroup(
                      children: [
                        for (final r in rows)
                          ProListRow(
                            dense: true,
                            chevron: false,
                            leading: ProIconWell(
                              icon: Icons.inventory_2_outlined,
                              color: r.lowStock ? AppColors.danger : AppColors.primary,
                            ),
                            title: r.itemName,
                            subtitle: r.invoice != null && r.invoice!.isNotEmpty ? 'Invoice: ${r.invoice}' : null,
                            value: '${r.quantity}',
                            valueColor: r.lowStock ? AppColors.danger : null,
                            pill: r.lowStock ? ProPill.bad('Low') : null,
                          ),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const AppLoadingBlock(height: 100),
              error: (e, _) => AppErrorPanel(message: '$e'),
            );
          }),
        // Shipments are a full-access-admin feature; branch users only record stock in/out.
        if (widget.isFullAccess) ...[
          ProSectionHeader(
            title: 'Shipments',
            trailing: widget.canManage && widget.isFullAccess
                ? TextButton.icon(
                    onPressed: _dispatch,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Dispatch'),
                  )
                : null,
          ),
          shipmentsAsync!.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const ProEmpty(icon: mailShipmentIcon, title: 'No shipments yet.');
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
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ProIconWell(icon: Icons.warning_amber_rounded, color: AppColors.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Low stock — ${byBranch.length} branch(es), ${rows.length} item(s)',
                        style: AppText.title.copyWith(fontSize: 15)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final entry in byBranch.entries)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${entry.value.first.branchLabel} (${entry.value.length})',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
                              Expanded(child: Text(r.itemName, style: const TextStyle(fontSize: 13.5))),
                              Text('${r.quantity} / ${r.lowStockThreshold}',
                                  style: AppText.number.copyWith(
                                      fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.danger)),
                            ],
                          ),
                        ),
                    ],
                  ),
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
    final progress = shipment.quantity == 0 ? 0.0 : (shipment.receivedQuantity / shipment.quantity).toDouble();
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProIconWell(icon: mailShipmentIcon, color: tone.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${shipment.fromBranchLabel} → ${shipment.toBranchLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink)),
                    Text(shipment.itemName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              mailTonePill(tone),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ProBar(value: progress, color: tone.color)),
              const SizedBox(width: 10),
              Text('${shipment.receivedQuantity} / ${shipment.quantity} received',
                  style: AppText.caption.merge(AppText.number)),
            ],
          ),
          if (canManage && shipment.status != MailShipmentStatus.received) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
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
  const _ComplaintsTab({required this.canManage, required this.bottomPadding, required this.nav});
  final bool canManage;
  final double bottomPadding;
  final Widget nav;

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
    final all = async.valueOrNull ?? const <MailComplaint>[];
    int n(String s) => all.where((c) => c.status == s).length;
    String v(int x) => async.hasValue ? '$x' : '—';
    final statuses = <String?>[null, ...MailComplaintStatus.values];
    final dayChips = dates.take(14).toList();

    ProStat stat(String status, String label, Color dot, String sub) => ProStat(
          label: label,
          value: v(n(status)),
          sub: sub,
          dot: dot,
          selected: _status == status,
          onTap: () => setState(() => _status = _status == status ? null : status),
        );

    return ProPage(
      onRefresh: () async {
        ref.invalidate(mailComplaintsProvider);
        ref.invalidate(mailComplaintDatesProvider);
      },
      padding: _pagePadding(widget.bottomPadding),
      hero: ProHero(
        title: 'Complaints',
        subtitle: async.hasValue
            ? '${all.length} complaint${all.length == 1 ? '' : 's'}${_range == null ? '' : ' in range'}'
            : 'Mail and courier complaints',
        children: [
          ProHeroStats(stats: [
            stat(MailComplaintStatus.pending, 'Pending', const Color(0xFFF2B347), 'not started'),
            stat(MailComplaintStatus.inProgress, 'In progress', const Color(0xFF9FCBD5), 'being handled'),
            stat(MailComplaintStatus.resolved, 'Resolved', AppColors.live, 'closed'),
          ]),
        ],
      ),
      children: [
        widget.nav,
        _RangeBar(
          range: _range,
          onPick: _pickRange,
          onClear: () => setState(() => _range = null),
        ),
        if (dayChips.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Dates with complaints', small: true),
              const SizedBox(height: 8),
              ProChipBar(
                labels: [for (final d in dayChips) dayFmt.format(d.date)],
                counts: [for (final d in dayChips) d.count],
                selected: dayChips.indexWhere(isDay),
                onSelected: (i) =>
                    setState(() => _range = DateTimeRange(start: dayChips[i].date, end: dayChips[i].date)),
                bleed: 0,
              ),
            ],
          ),
        if (async.hasValue)
          ProChipBar(
            labels: [for (final s in statuses) s == null ? 'All' : mailComplaintStatusTone(s).label],
            counts: [for (final s in statuses) s == null ? async.value!.length : async.value!.where((c) => c.status == s).length],
            selected: statuses.indexOf(_status),
            onSelected: (i) => setState(() => _status = statuses[i]),
            bleed: 0,
          ),
        async.when(
          data: (all) {
            final rows = _status == null ? all : all.where((c) => c.status == _status).toList();
            if (rows.isEmpty) {
              return ProEmpty(
                icon: mailComplaintIcon,
                title: 'No complaints found.',
                message: _range != null && dates.isNotEmpty
                    ? 'No complaints in this date range — pick one of the dates above.'
                    : null,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(
                  title: '${_status == null ? 'All complaints' : mailComplaintStatusTone(_status!).label} · ${rows.length}',
                  small: true,
                ),
                const SizedBox(height: 8),
                ProListGroup(
                  children: [
                    for (final c in rows)
                      ProListRow(
                        onTap: () => _open(c),
                        leading: ProIconWell(
                          icon: mailComplaintIcon,
                          color: mailComplaintStatusTone(c.status).color,
                        ),
                        title: c.subject,
                        subtitle: '${c.branchLabel} · ${c.department ?? 'No department'}',
                        meta: c.date == null ? '—' : df.format(c.date!),
                        pill: mailTonePill(mailComplaintStatusTone(c.status)),
                      ),
                  ],
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
    );
  }
}
