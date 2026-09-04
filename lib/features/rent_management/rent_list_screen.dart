import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'rent_models.dart';
import 'rent_repository.dart';
import 'rent_status_ui.dart';

final rentBranchesProvider = FutureProvider.autoDispose<List<RentBranch>>((ref) {
  return ref.watch(rentRepositoryProvider).listBranches();
});

final rentPayableProvider =
    FutureProvider.autoDispose.family<List<RentPayable>, String>((ref, period) {
  return ref.watch(rentRepositoryProvider).listPayableForPeriod(period);
});

final rentNoticesProvider = FutureProvider.autoDispose<List<RentNotice>>((ref) {
  return ref.watch(rentRepositoryProvider).listNotices();
});

final rentUtilityBillsProvider =
    FutureProvider.autoDispose.family<List<RentUtilityBill>, String>((ref, period) {
  return ref.watch(rentRepositoryProvider).listUtilityBillsForPeriod(period);
});

final rentAuditTrailProvider = FutureProvider.autoDispose<List<RentAuditLog>>((ref) {
  return ref.watch(rentRepositoryProvider).auditTrail();
});

enum _RentTab { branches, payable, notices, utility, audit }

/// Admin Tools · Rent Management — branches / monthly payable workflow /
/// notices / utility bills / audit trail, mirroring `AdminRentPage.tsx`'s
/// five tabs.
class RentListScreen extends ConsumerStatefulWidget {
  const RentListScreen({super.key});

  @override
  ConsumerState<RentListScreen> createState() => _RentListScreenState();
}

class _RentListScreenState extends ConsumerState<RentListScreen> {
  _RentTab _tab = _RentTab.branches;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canManageBranch = user?.hasPermission('ADMIN_RENT_BRANCH_MANAGE') ?? false;
    final canManageNotice = user?.hasPermission('ADMIN_RENT_NOTICE_MANAGE') ?? false;
    final canManageUtility = user?.hasPermission('ADMIN_RENT_UTILITY_MANAGE') ?? false;
    final canViewAudit = user?.hasPermission('ADMIN_RENT_AUDIT_VIEW') ?? false;
    final mq = MediaQuery.of(context);

    final tabs = <_RentTab, String>{
      _RentTab.branches: 'Branches',
      _RentTab.payable: 'Payables',
      _RentTab.notices: 'Notices',
      _RentTab.utility: 'Utility Bills',
      if (canViewAudit) _RentTab.audit: 'Audit trail',
    };
    if (!tabs.containsKey(_tab)) _tab = _RentTab.branches;

    Future<void> Function()? fab;
    String? fabLabel;
    IconData? fabIcon;
    switch (_tab) {
      case _RentTab.branches:
        if (canManageBranch) {
          fabLabel = 'Add branch';
          fabIcon = Icons.add_rounded;
          fab = () async {
            final ok = await context.push<bool>('/admin/rent/branches/new');
            if (ok == true) ref.invalidate(rentBranchesProvider);
          };
        }
        break;
      case _RentTab.notices:
        if (canManageNotice) {
          fabLabel = 'Issue notice';
          fabIcon = Icons.campaign_rounded;
          fab = () async {
            final ok = await context.push<bool>('/admin/rent/notices/new');
            if (ok == true) ref.invalidate(rentNoticesProvider);
          };
        }
        break;
      case _RentTab.utility:
        if (canManageUtility) {
          fabLabel = 'Add / update bill';
          fabIcon = Icons.add_rounded;
          fab = () async {
            final ok = await context.push<bool>('/admin/rent/utility-bills/new');
            if (ok == true) {
              ref.invalidate(rentUtilityBillsProvider);
            }
          };
        }
        break;
      case _RentTab.payable:
      case _RentTab.audit:
        break;
    }

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Rent Management'),
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
                _RentTab.branches => _BranchesTab(
                    canManage: canManageBranch,
                    bottomPadding: mq.padding.bottom + 90,
                  ),
                _RentTab.payable => _PayableTab(bottomPadding: mq.padding.bottom + 24),
                _RentTab.notices => _NoticesTab(bottomPadding: mq.padding.bottom + 90),
                _RentTab.utility => _UtilityTab(bottomPadding: mq.padding.bottom + 90),
                _RentTab.audit => _AuditTab(bottomPadding: mq.padding.bottom + 24),
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

// ── Branches tab ─────────────────────────────────────────────────────────────

class _BranchesTab extends ConsumerWidget {
  const _BranchesTab({required this.canManage, required this.bottomPadding});
  final bool canManage;
  final double bottomPadding;

  Future<void> _open(BuildContext context, WidgetRef ref, RentBranch b) async {
    final ok = await context.push<bool>('/admin/rent/branches/${b.id}');
    if (ok == true) ref.invalidate(rentBranchesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rentBranchesProvider);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(rentBranchesProvider),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.home_work_rounded,
                  message: 'No rent branches yet. Tap "Add branch" to create one.',
                );
              }
              return Column(
                children: [
                  for (final b in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BranchCard(
                        branch: b,
                        onTap: canManage ? () => _open(context, ref, b) : null,
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(rentBranchesProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.branch, this.onTap});
  final RentBranch branch;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
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
                  child: Icon(rentBranchIcon, color: AppColors.primary, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    branch.branchCode != null && branch.branchCode!.isNotEmpty
                        ? '${branch.branchName} (${branch.branchCode})'
                        : branch.branchName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                ),
                StatusPill(
                  label: branch.active ? 'Active' : 'Inactive',
                  color: branch.active ? AppColors.success : AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _row(Icons.person_rounded, branch.ownerName ?? 'No owner on file'),
            const SizedBox(height: 6),
            _row(Icons.event_rounded,
                branch.startDate == null ? 'Start date —' : 'Since ${df.format(branch.startDate!)}'),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _totalCol('Rent', branch.rent),
                _totalCol('Advance', branch.rentAdvance),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GST',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(
                      branch.gstApplicable == null ? '—' : (branch.gstApplicable! ? 'Yes' : 'No'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ],
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

  Widget _totalCol(String label, double? value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(
            rentMoney(value),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
        ],
      );
}

// ── Payable tab ──────────────────────────────────────────────────────────────

DateTime _thisMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
}

class _PayableTab extends ConsumerStatefulWidget {
  const _PayableTab({required this.bottomPadding});
  final double bottomPadding;

  @override
  ConsumerState<_PayableTab> createState() => _PayableTabState();
}

class _PayableTabState extends ConsumerState<_PayableTab> {
  DateTime _period = _thisMonth();
  bool _generating = false;
  int? _busyId;

  String get _periodIso => isoPeriod(_period);

  Future<void> _pickPeriod() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _period,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (d != null) {
      setState(() => _period = DateTime(d.year, d.month, 1));
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      await ref.read(rentRepositoryProvider).generatePayable(_periodIso);
      ref.invalidate(rentPayableProvider(_periodIso));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Rent payable rows generated')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _act(int id, Future<void> Function() fn) async {
    setState(() => _busyId = id);
    try {
      await fn();
      ref.invalidate(rentPayableProvider(_periodIso));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _open(RentPayable p) async {
    final ok = await context.push<bool>('/admin/rent/payable/${p.id}?period=$_periodIso');
    if (ok == true) ref.invalidate(rentPayableProvider(_periodIso));
  }

  Future<void> _markPaid(RentPayable p) async {
    final utr = await _promptText(title: 'Mark "${p.branchName}" as paid', label: 'Payment reference / UTR');
    if (utr == null) return;
    await _act(p.id,
        () => ref.read(rentRepositoryProvider).markPayablePaid(p.id, paidUtr: utr.isEmpty ? null : utr));
  }

  Future<void> _hold(RentPayable p) async {
    final reason =
        await _promptText(title: 'Hold "${p.branchName}"\'s rent payable', label: 'Reason for hold');
    if (reason == null) return;
    await _act(p.id,
        () => ref.read(rentRepositoryProvider).holdPayable(p.id, holdReason: reason.isEmpty ? null : reason));
  }

  Future<String?> _promptText({required String title, required String label}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canManage = user?.hasPermission('ADMIN_RENT_PAYABLE_MANAGE') ?? false;
    final canSubmit = user?.hasPermission('ADMIN_RENT_PAYABLE_SUBMIT') ?? false;
    final canApprove = user?.hasPermission('ADMIN_RENT_PAYABLE_APPROVE') ?? false;
    final canPay = user?.hasPermission('ADMIN_RENT_PAYABLE_PAY') ?? false;
    final async = ref.watch(rentPayableProvider(_periodIso));
    final dfMonth = DateFormat('MMMM yyyy');

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(rentPayableProvider(_periodIso)),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickPeriod,
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
                        Text(dfMonth.format(_period),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: _generating ? null : _generate,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: Text(_generating ? 'Generating…' : 'Generate'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.receipt_long_rounded,
                  message: 'No rent-payable rows for this period.',
                );
              }
              return Column(
                children: [
                  for (final p in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PayableCard(
                        payable: p,
                        busy: _busyId == p.id,
                        canSubmit: canSubmit,
                        canApprove: canApprove,
                        canPay: canPay,
                        canManage: canManage,
                        onTap: () => _open(p),
                        onSubmit: () => _act(p.id, () => ref.read(rentRepositoryProvider).submitPayable(p.id)),
                        onApprove: () => _act(p.id, () => ref.read(rentRepositoryProvider).approvePayable(p.id)),
                        onMarkPaid: () => _markPaid(p),
                        onHold: () => _hold(p),
                        onReleaseHold: () =>
                            _act(p.id, () => ref.read(rentRepositoryProvider).releasePayableHold(p.id)),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(rentPayableProvider(_periodIso)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayableCard extends StatelessWidget {
  const _PayableCard({
    required this.payable,
    required this.busy,
    required this.canSubmit,
    required this.canApprove,
    required this.canPay,
    required this.canManage,
    required this.onTap,
    required this.onSubmit,
    required this.onApprove,
    required this.onMarkPaid,
    required this.onHold,
    required this.onReleaseHold,
  });

  final RentPayable payable;
  final bool busy;
  final bool canSubmit;
  final bool canApprove;
  final bool canPay;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onSubmit;
  final VoidCallback onApprove;
  final VoidCallback onMarkPaid;
  final VoidCallback onHold;
  final VoidCallback onReleaseHold;

  @override
  Widget build(BuildContext context) {
    final tone = rentPayableStatusTone(payable.status);
    final actions = <Widget>[
      if (canSubmit && payable.status == RentPayableStatus.pending)
        _chipButton('Submit', onSubmit, busy),
      if (canApprove && payable.status == RentPayableStatus.submitted)
        _chipButton('Approve', onApprove, busy),
      if (canPay && payable.status == RentPayableStatus.approved)
        _chipButton('Mark paid', onMarkPaid, busy, primary: true),
      if (canManage && payable.status == RentPayableStatus.held)
        _chipButton('Release hold', onReleaseHold, busy),
      if (canManage &&
          payable.status != RentPayableStatus.held &&
          payable.status != RentPayableStatus.paid)
        _chipButton('Hold', onHold, busy, danger: true),
    ];

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
                Expanded(
                  child: Text(payable.branchName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                ),
                StatusPill(label: tone.label, color: tone.color),
              ],
            ),
            const SizedBox(height: 6),
            Text(rentMoney(payable.rentAmount),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            if (payable.status == RentPayableStatus.held && payable.holdReason != null) ...[
              const SizedBox(height: 4),
              Text('Hold: ${payable.holdReason}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
            ],
            if (payable.status == RentPayableStatus.paid && payable.paidUtr != null) ...[
              const SizedBox(height: 4),
              Text('UTR: ${payable.paidUtr}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ],
            if (actions.isNotEmpty) ...[
              const Divider(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipButton(String label, VoidCallback onTap, bool busy,
      {bool primary = false, bool danger = false}) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: danger ? AppColors.danger : (primary ? AppColors.primary : AppColors.surface),
          foregroundColor: danger || primary ? Colors.white : AppColors.ink,
          side: danger || primary ? null : const BorderSide(color: AppColors.hairline),
          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

// ── Notices tab ──────────────────────────────────────────────────────────────

class _NoticesTab extends ConsumerWidget {
  const _NoticesTab({required this.bottomPadding});
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rentNoticesProvider);
    final df = DateFormat('d MMM yyyy');
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(rentNoticesProvider),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.campaign_rounded,
                  message: 'No notices issued yet.',
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(rows[i].subject,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                                ),
                                if (rows[i].holdRent)
                                  const StatusPill(label: 'Holds rent', color: AppColors.danger),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(rows[i].branchName,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
                            const SizedBox(height: 2),
                            Text(
                              '${rows[i].issuedOn == null ? '—' : df.format(rows[i].issuedOn!)} · ${rows[i].issuedBy ?? 'system'}',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                            if (rows[i].body != null && rows[i].body!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(rows[i].body!,
                                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                            ],
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
              onRetry: () => ref.invalidate(rentNoticesProvider),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Utility bills tab ────────────────────────────────────────────────────────

class _UtilityTab extends ConsumerStatefulWidget {
  const _UtilityTab({required this.bottomPadding});
  final double bottomPadding;

  @override
  ConsumerState<_UtilityTab> createState() => _UtilityTabState();
}

class _UtilityTabState extends ConsumerState<_UtilityTab> {
  DateTime _period = _thisMonth();

  String get _periodIso => isoPeriod(_period);

  Future<void> _pickPeriod() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _period,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (d != null) {
      setState(() => _period = DateTime(d.year, d.month, 1));
    }
  }

  Future<void> _markPaid(RentUtilityBill bill) async {
    final controller = TextEditingController();
    final utr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark bill paid'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'UTR / reference for ${bill.branchName} — ${rentUtilityKindLabel(bill.kind)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
    if (utr == null || utr.isEmpty) return;
    try {
      await ref.read(rentRepositoryProvider).markUtilityBillPaid(bill.id, utr);
      ref.invalidate(rentUtilityBillsProvider(_periodIso));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canManage = user?.hasPermission('ADMIN_RENT_UTILITY_MANAGE') ?? false;
    final async = ref.watch(rentUtilityBillsProvider(_periodIso));
    final dfMonth = DateFormat('MMMM yyyy');
    final dfDay = DateFormat('d MMM');

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(rentUtilityBillsProvider(_periodIso)),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          InkWell(
            onTap: _pickPeriod,
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
                  Text(dfMonth.format(_period), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.bolt_rounded,
                  message: 'No utility bills for this period.',
                );
              }
              return Column(
                children: [
                  for (final b in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        shadow: AppShadows.soft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(rentUtilityKindIcon(b.kind), size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('${b.branchName} · ${rentUtilityKindLabel(b.kind)}',
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                                ),
                                StatusPill(
                                  label: b.paidAt != null ? 'Paid' : 'Unpaid',
                                  color: b.paidAt != null ? AppColors.success : AppColors.muted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(rentMoney(b.amount),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                Text(b.dueDate == null ? 'No due date' : 'Due ${dfDay.format(b.dueDate!)}',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              ],
                            ),
                            if (canManage && b.paidAt == null) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  height: 32,
                                  child: FilledButton.tonal(
                                    onPressed: () => _markPaid(b),
                                    child: const Text('Mark paid', style: TextStyle(fontSize: 11.5)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(rentUtilityBillsProvider(_periodIso)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Audit trail tab ──────────────────────────────────────────────────────────

class _AuditTab extends ConsumerWidget {
  const _AuditTab({required this.bottomPadding});
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rentAuditTrailProvider);
    final df = DateFormat('d MMM yyyy, HH:mm');
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(rentAuditTrailProvider),
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
              onRetry: () => ref.invalidate(rentAuditTrailProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry, required this.df});
  final RentAuditLog entry;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final tone = rentAuditActionTone(entry.action);
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
