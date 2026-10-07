import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/report_download.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'rent_dashboard_tab.dart';
import 'rent_gst_dialog.dart';
import 'rent_models.dart';
import 'rent_rate_options_card.dart';
import 'rent_reports_tab.dart';
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

final rentRateOptionsProvider = FutureProvider.autoDispose<RentRateOptions>((ref) async {
  try {
    return await ref.watch(rentRepositoryProvider).getRateOptions();
  } catch (_) {
    return RentRateOptions.fallback;
  }
});

enum _RentTab { dashboard, branches, payable, notices, utility, reports, audit }

/// Admin Tools · Rent Management — branches / monthly payable workflow /
/// notices / utility bills / audit trail, mirroring `AdminRentPage.tsx`'s
/// five tabs.
class RentListScreen extends ConsumerStatefulWidget {
  const RentListScreen({super.key});

  @override
  ConsumerState<RentListScreen> createState() => _RentListScreenState();
}

class _RentListScreenState extends ConsumerState<RentListScreen> {
  _RentTab _tab = _RentTab.dashboard;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canManageBranch = user?.hasPermission('ADMIN_RENT_BRANCH_MANAGE') ?? false;
    final canManageNotice = user?.hasPermission('ADMIN_RENT_NOTICE_MANAGE') ?? false;
    final canManageUtility = user?.hasPermission('ADMIN_RENT_UTILITY_MANAGE') ?? false;
    final canViewAudit = user?.hasPermission('ADMIN_RENT_AUDIT_VIEW') ?? false;

    final tabs = <_RentTab, String>{
      _RentTab.dashboard: 'Dashboard',
      _RentTab.branches: 'Branches',
      _RentTab.payable: 'Payables',
      _RentTab.notices: 'Notices',
      _RentTab.utility: 'Utility bills',
      _RentTab.reports: 'Reports',
      if (canViewAudit) _RentTab.audit: 'Audit trail',
    };
    if (!tabs.containsKey(_tab)) _tab = _RentTab.dashboard;
    final isFullAccess = user?.hasPermission('DATA_SCOPE_ALL') ?? false;

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
      case _RentTab.dashboard:
      case _RentTab.reports:
      case _RentTab.payable:
      case _RentTab.audit:
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
      appBar: AppBar(title: const Text('Rent management')),
      floatingActionButton: fab != null
          ? FloatingActionButton.extended(
              onPressed: () => fab!(),
              icon: Icon(fabIcon),
              label: Text(fabLabel!),
            )
          : null,
      body: switch (_tab) {
        _RentTab.dashboard => RentDashboardTab(bottomPadding: 24, nav: nav),
        _RentTab.reports => RentReportsTab(bottomPadding: 24, nav: nav),
        _RentTab.branches => _BranchesTab(
            canManage: canManageBranch,
            isFullAccess: isFullAccess,
            bottomPadding: 90,
            nav: nav,
          ),
        _RentTab.payable => _PayableTab(bottomPadding: 24, nav: nav),
        _RentTab.notices => _NoticesTab(bottomPadding: 90, nav: nav),
        _RentTab.utility => _UtilityTab(bottomPadding: 90, nav: nav),
        _RentTab.audit => _AuditTab(bottomPadding: 24, nav: nav),
      },
    );
  }
}

/// Page padding for a tab: [extra] clears the FAB (system inset is added by
/// [ProPage]).
EdgeInsets _pagePadding(double extra) => EdgeInsets.fromLTRB(16, 16, 16, extra);

/// Month picker row: previous / next month arrows around a tappable month
/// label (opens the same date picker as before).
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.period,
    required this.onPick,
    required this.onChanged,
    this.trailing,
  });
  final DateTime period;
  final VoidCallback onPick;
  final ValueChanged<DateTime> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final prev = DateTime(period.year, period.month - 1, 1);
    final next = DateTime(period.year, period.month + 1, 1);
    final canPrev = !prev.isBefore(DateTime(2015));
    final canNext = next.isBefore(DateTime(2036));
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: canPrev ? () => onChanged(prev) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: InkWell(
                    onTap: onPick,
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 40,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_month_rounded,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              // Shorter month name when an action shares the row.
                              DateFormat(trailing == null ? 'MMMM yyyy' : 'MMM yyyy').format(period),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: canNext ? () => onChanged(next) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

/// Small action button used on rent cards.
Widget _cardButton(String label, VoidCallback? onTap,
    {bool primary = false, bool danger = false}) {
  const size = Size(0, 36);
  const pad = EdgeInsets.symmetric(horizontal: 14);
  const text = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  final child = Text(label);
  if (danger) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: size,
        padding: pad,
        textStyle: text,
        backgroundColor: AppColors.dangerTint,
        foregroundColor: AppColors.danger,
      ),
      child: child,
    );
  }
  if (primary) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(minimumSize: size, padding: pad, textStyle: text),
      child: child,
    );
  }
  return OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(minimumSize: size, padding: pad, textStyle: text),
    child: child,
  );
}

// ── Branches tab ─────────────────────────────────────────────────────────────

class _BranchesTab extends ConsumerWidget {
  const _BranchesTab({
    required this.canManage,
    required this.isFullAccess,
    required this.bottomPadding,
    required this.nav,
  });
  final bool canManage;
  final bool isFullAccess;
  final double bottomPadding;
  final Widget nav;

  Future<void> _open(BuildContext context, WidgetRef ref, RentBranch b) async {
    final ok = await context.push<bool>('/admin/rent/branches/${b.id}');
    if (ok == true) ref.invalidate(rentBranchesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rentBranchesProvider);
    final rows = async.valueOrNull ?? const <RentBranch>[];
    final active = rows.where((b) => b.active).toList();
    final monthly = active.fold<double>(0, (s, b) => s + (b.rent ?? 0));
    return ProPage(
      onRefresh: () async => ref.invalidate(rentBranchesProvider),
      padding: _pagePadding(bottomPadding),
      hero: ProHero(
        title: 'Branches',
        subtitle: async.hasValue
            ? '${rows.length} rent branch${rows.length == 1 ? '' : 'es'} · landlord records'
            : 'Landlord records',
        children: [
          ProHeroStats(stats: [
            ProStat(
              label: 'Active',
              value: async.hasValue ? '${active.length}' : '—',
              sub: 'of ${rows.length}',
              dot: AppColors.live,
            ),
            ProStat(
              label: 'Inactive',
              value: async.hasValue ? '${rows.length - active.length}' : '—',
              sub: 'closed leases',
              dot: const Color(0xFFB3C0C3),
            ),
            ProStat(
              label: 'Monthly rent',
              value: async.hasValue ? rentMoney(monthly).split('.').first : '—',
              sub: 'active branches',
              dot: const Color(0xFFF2B347),
            ),
          ]),
        ],
      ),
      children: [
        nav,
        if (isFullAccess)
          ref.watch(rentRateOptionsProvider).maybeWhen(
                data: (opts) => RentRateOptionsCard(
                  repo: ref.read(rentRepositoryProvider),
                  options: opts,
                  onChanged: (_) => ref.invalidate(rentRateOptionsProvider),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
        async.when(
          data: (rows) {
            if (rows.isEmpty) {
              return const ProEmpty(
                icon: Icons.home_work_rounded,
                title: 'No rent branches yet',
                message: 'Tap "Add branch" to create one.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(title: 'All branches · ${rows.length}', small: true),
                const SizedBox(height: 8),
                ProListGroup(
                  children: [
                    for (final b in rows)
                      _BranchRow(
                        branch: b,
                        onTap: canManage ? () => _open(context, ref, b) : null,
                      ),
                  ],
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
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.branch, this.onTap});
  final RentBranch branch;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final title = branch.branchCode != null && branch.branchCode!.isNotEmpty
        ? '${branch.branchName} (${branch.branchCode})'
        : branch.branchName;
    final gst = branch.gstApplicable == null ? '—' : (branch.gstApplicable! ? 'Yes' : 'No');
    return ProListRow(
      leading: ProIconWell(
        icon: rentBranchIcon,
        color: branch.active ? AppColors.primary : AppColors.muted,
      ),
      title: title,
      subtitle: '${branch.ownerName ?? 'No owner on file'} · '
          '${branch.startDate == null ? 'Start date —' : 'Since ${df.format(branch.startDate!)}'}',
      meta: 'Advance ${rentMoney(branch.rentAdvance)} · GST $gst',
      value: rentMoney(branch.rent),
      pill: branch.active ? ProPill.ok('Active') : ProPill.neutral('Inactive'),
      onTap: onTap,
    );
  }
}

// ── Payable tab ──────────────────────────────────────────────────────────────

DateTime _thisMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
}

class _PayableTab extends ConsumerStatefulWidget {
  const _PayableTab({required this.bottomPadding, required this.nav});
  final double bottomPadding;
  final Widget nav;

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
    final all = async.valueOrNull ?? const <RentPayable>[];
    int count(bool Function(RentPayable) t) => all.where(t).length;
    final net = all.fold<double>(0, (s, r) => s + (r.netAmount ?? r.rentAmount));
    final awaiting = count((r) =>
        r.status == RentPayableStatus.pending || r.status == RentPayableStatus.submitted);
    final approved = count((r) => r.status == RentPayableStatus.approved);
    final paid = count((r) => r.status == RentPayableStatus.paid);
    final held = count((r) => r.status == RentPayableStatus.held);
    String v(int n) => async.hasValue ? '$n' : '—';

    return ProPage(
      onRefresh: () async => ref.invalidate(rentPayableProvider(_periodIso)),
      padding: _pagePadding(widget.bottomPadding),
      hero: ProHero(
        title: 'Payables',
        subtitle: async.hasValue
            ? '${DateFormat('MMMM yyyy').format(_period)} · ${rentMoney(net)} net'
            : 'Monthly rent payable · ${DateFormat('MMMM yyyy').format(_period)}',
        children: [
          ProHeroStats(stats: [
            ProStat(label: 'Awaiting', value: v(awaiting), sub: 'pending · submitted', dot: const Color(0xFFF2B347)),
            ProStat(label: 'Approved', value: v(approved), sub: 'ready to pay', dot: const Color(0xFF9FCBD5)),
            ProStat(
              label: 'Paid',
              value: v(paid),
              sub: held > 0 ? '$held on hold' : 'this month',
              dot: AppColors.live,
            ),
          ]),
        ],
      ),
      children: [
        widget.nav,
        _PeriodBar(
          period: _period,
          onPick: _pickPeriod,
          onChanged: (p) => setState(() => _period = p),
          trailing: canManage
              ? FilledButton.tonalIcon(
                  onPressed: _generating ? null : _generate,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: Text(_generating ? 'Generating…' : 'Generate'),
                )
              : null,
        ),
        async.when(
          data: (rows) {
            final swipeable = rows.any((p) =>
                (canApprove && p.status == RentPayableStatus.submitted) ||
                (canManage &&
                    p.status != RentPayableStatus.held &&
                    p.status != RentPayableStatus.paid));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(
                  title: 'Rent payable · ${rows.length}',
                  small: true,
                  trailing: TextButton.icon(
                    onPressed: () => downloadExcelReport(
                      context,
                      () => ref.read(rentRepositoryProvider).downloadPayableReport(_periodIso),
                      'rent-payable-${_periodIso.substring(0, 7)}.xlsx',
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download report'),
                  ),
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const ProEmpty(
                    icon: Icons.receipt_long_rounded,
                    title: 'No rent-payable rows for this period',
                    message: 'Generate this month’s rows to get started.',
                  )
                else ...[
                  if (swipeable) ...[
                    const ProSwipeHint(text: 'Swipe right to approve, left to hold'),
                    const SizedBox(height: 10),
                  ],
                  for (final p in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _swipeable(
                        p,
                        canApprove: canApprove,
                        canManage: canManage,
                        child: _PayableCard(
                          payable: p,
                          busy: _busyId == p.id,
                          canSubmit: canSubmit,
                          canApprove: canApprove,
                          canPay: canPay,
                          canManage: canManage,
                          onTap: () => _open(p),
                          onSubmit: () => _submit(p),
                          onApprove: () => _approve(p),
                          onMarkPaid: () => _markPaid(p),
                          onHold: () => _hold(p),
                          onReleaseHold: () =>
                              _act(p.id, () => ref.read(rentRepositoryProvider).releasePayableHold(p.id)),
                        ),
                      ),
                    ),
                ],
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
    );
  }

  Future<void> _submit(RentPayable p) => _act(p.id, () async {
        final repo = ref.read(rentRepositoryProvider);
        if (!await confirmGstBeforeSubmit(context, repo, p.branchId)) return;
        await repo.submitPayable(p.id);
      });

  Future<void> _approve(RentPayable p) =>
      _act(p.id, () => ref.read(rentRepositoryProvider).approvePayable(p.id));

  /// Swipe right = approve (submitted rows), swipe left = hold — the same
  /// handlers as the card's buttons, gated the same way.
  Widget _swipeable(RentPayable p,
      {required bool canApprove, required bool canManage, required Widget child}) {
    final busy = _busyId == p.id;
    final approve = !busy && canApprove && p.status == RentPayableStatus.submitted;
    final hold = !busy &&
        canManage &&
        p.status != RentPayableStatus.held &&
        p.status != RentPayableStatus.paid;
    if (!approve && !hold) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: ProSwipeDecision(
        onApprove: approve ? () => _approve(p) : null,
        onReject: hold ? () => _hold(p) : null,
        rejectLabel: 'Hold',
        rejectIcon: Icons.pause_circle_outline_rounded,
        child: child,
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
        _cardButton('Submit', busy ? null : onSubmit),
      if (canApprove && payable.status == RentPayableStatus.submitted)
        _cardButton('Approve', busy ? null : onApprove, primary: true),
      if (canPay && payable.status == RentPayableStatus.approved)
        _cardButton('Mark paid', busy ? null : onMarkPaid, primary: true),
      if (canManage && payable.status == RentPayableStatus.held)
        _cardButton('Release hold', busy ? null : onReleaseHold),
      if (canManage &&
          payable.status != RentPayableStatus.held &&
          payable.status != RentPayableStatus.paid)
        _cardButton('Hold', busy ? null : onHold, danger: true),
    ];

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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProIconWell(icon: Icons.receipt_long_rounded, color: tone.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(payable.branchName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.15,
                                color: AppColors.ink)),
                        Text(
                          payable.netAmount != null && payable.netAmount != payable.rentAmount
                              ? 'Rent ${rentMoney(payable.rentAmount)} · net ${rentMoney(payable.netAmount)}'
                              : 'Monthly rent',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.merge(AppText.number),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(rentMoney(payable.rentAmount),
                          style: AppText.number.copyWith(
                              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      rentTonePill(tone),
                    ],
                  ),
                ],
              ),
              if (payable.status == RentPayableStatus.held && payable.holdReason != null) ...[
                const SizedBox(height: 10),
                ProNote('Hold: ${payable.holdReason}', tone: ProNoteTone.bad),
              ],
              if (payable.status == RentPayableStatus.paid && payable.paidUtr != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Text('UTR: ${payable.paidUtr}',
                      style: AppText.caption.merge(AppText.number)),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Notices tab ──────────────────────────────────────────────────────────────

class _NoticesTab extends ConsumerWidget {
  const _NoticesTab({required this.bottomPadding, required this.nav});
  final double bottomPadding;
  final Widget nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rentNoticesProvider);
    final df = DateFormat('d MMM yyyy');
    final all = async.valueOrNull ?? const <RentNotice>[];
    final now = DateTime.now();
    final thisMonth = all
        .where((n) => n.issuedOn != null && n.issuedOn!.year == now.year && n.issuedOn!.month == now.month)
        .length;
    final holds = all.where((n) => n.holdRent).length;
    String v(int n) => async.hasValue ? '$n' : '—';
    return ProPage(
      onRefresh: () async => ref.invalidate(rentNoticesProvider),
      padding: _pagePadding(bottomPadding),
      hero: ProHero(
        title: 'Notices',
        subtitle: 'Notices issued to branches',
        children: [
          ProHeroStats(stats: [
            ProStat(label: 'Issued', value: v(all.length), sub: 'all time', dot: Colors.white),
            ProStat(label: 'This month', value: v(thisMonth), sub: DateFormat('MMM yyyy').format(now), dot: AppColors.live),
            ProStat(label: 'Hold rent', value: v(holds), sub: 'rent withheld', dot: const Color(0xFFE5484D)),
          ]),
        ],
      ),
      children: [
        nav,
        async.when(
          data: (rows) {
            if (rows.isEmpty) {
              return const ProEmpty(
                icon: Icons.campaign_rounded,
                title: 'No notices issued yet',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(title: 'All notices · ${rows.length}', small: true),
                const SizedBox(height: 8),
                ProListGroup(
                  children: [
                    for (final n in rows)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProIconWell(
                              icon: Icons.campaign_rounded,
                              color: n.holdRent ? AppColors.danger : AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(n.subject,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                height: 1.33,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.ink)),
                                      ),
                                      if (n.holdRent) ...[
                                        const SizedBox(width: 8),
                                        ProPill.bad('Holds rent'),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '${n.branchName} · ${n.issuedOn == null ? '—' : df.format(n.issuedOn!)} · ${n.issuedBy ?? 'system'}',
                                    style: AppText.caption,
                                  ),
                                  if (n.body != null && n.body!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(n.body!,
                                        style: const TextStyle(
                                            fontSize: 13.5, height: 1.45, color: AppColors.inkSoft)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
          loading: () => const AppLoadingBlock(height: 200),
          error: (e, _) => AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(rentNoticesProvider),
          ),
        ),
      ],
    );
  }
}

// ── Utility bills tab ────────────────────────────────────────────────────────

class _UtilityTab extends ConsumerStatefulWidget {
  const _UtilityTab({required this.bottomPadding, required this.nav});
  final double bottomPadding;
  final Widget nav;

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

  Future<void> _open(RentUtilityBill bill) async {
    final ok = await context.push<bool>('/admin/rent/utility-bills/new', extra: bill);
    if (ok == true) ref.invalidate(rentUtilityBillsProvider(_periodIso));
  }

  Future<void> _approve(RentUtilityBill bill) async {
    try {
      await ref.read(rentRepositoryProvider).approveUtilityBill(bill.id);
      ref.invalidate(rentUtilityBillsProvider(_periodIso));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reject(RentUtilityBill bill) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject bill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: 'Reason for rejecting ${bill.branchName} — ${rentUtilityKindLabel(bill.kind)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Reject')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await ref.read(rentRepositoryProvider).rejectUtilityBill(bill.id, reason);
      ref.invalidate(rentUtilityBillsProvider(_periodIso));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _markUnpaid(RentUtilityBill bill) async {
    try {
      await ref.read(rentRepositoryProvider).markUtilityBillUnpaid(bill.id);
      ref.invalidate(rentUtilityBillsProvider(_periodIso));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
    final isFullAccess = user?.hasPermission('DATA_SCOPE_ALL') ?? false;
    final async = ref.watch(rentUtilityBillsProvider(_periodIso));
    final dfDay = DateFormat('d MMM');
    final all = async.valueOrNull ?? const <RentUtilityBill>[];
    final pending = all.where((b) => b.status == 'PENDING').length;
    final approvedUnpaid = all.where((b) => b.status == 'APPROVED' && b.paidAt == null).length;
    final paid = all.where((b) => b.status == 'APPROVED' && b.paidAt != null).length;
    final total = all.fold<double>(0, (s, b) => s + (b.amount ?? 0));
    String v(int n) => async.hasValue ? '$n' : '—';

    return ProPage(
      onRefresh: () async => ref.invalidate(rentUtilityBillsProvider(_periodIso)),
      padding: _pagePadding(widget.bottomPadding),
      hero: ProHero(
        title: 'Utility bills',
        subtitle: async.hasValue
            ? '${DateFormat('MMMM yyyy').format(_period)} · ${rentMoney(total)} billed'
            : 'Electricity and internet bills by branch',
        children: [
          ProHeroStats(stats: [
            ProStat(label: 'Pending', value: v(pending), sub: 'awaiting review', dot: const Color(0xFFF2B347)),
            ProStat(label: 'Approved', value: v(approvedUnpaid), sub: 'not yet paid', dot: const Color(0xFF9FCBD5)),
            ProStat(label: 'Paid', value: v(paid), sub: 'this period', dot: AppColors.live),
          ]),
        ],
      ),
      children: [
        widget.nav,
        _PeriodBar(
          period: _period,
          onPick: _pickPeriod,
          onChanged: (p) => setState(() => _period = p),
        ),
        async.when(
          data: (rows) {
            final swipeable = isFullAccess && rows.any((b) => b.status == 'PENDING');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(
                  title: 'Bills · ${rows.length}',
                  small: true,
                  trailing: TextButton.icon(
                    onPressed: () {
                      final last = DateTime(_period.year, _period.month + 1, 0);
                      downloadExcelReport(
                        context,
                        () => ref.read(rentRepositoryProvider).downloadUtilityReport(isoPeriod(_period), isoPeriod(last)),
                        'utility-bills-${_periodIso.substring(0, 7)}.xlsx',
                      );
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download report'),
                  ),
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const ProEmpty(
                    icon: Icons.bolt_rounded,
                    title: 'No utility bills for this period',
                    message: 'Bills filed for this month show up here.',
                  )
                else ...[
                  if (swipeable) ...[
                    const ProSwipeHint(),
                    const SizedBox(height: 10),
                  ],
                  for (final b in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _swipeBill(
                        b,
                        enabled: isFullAccess && b.status == 'PENDING',
                        child: _billCard(b, isFullAccess, dfDay),
                      ),
                    ),
                ],
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
    );
  }

  Widget _swipeBill(RentUtilityBill b, {required bool enabled, required Widget child}) {
    if (!enabled) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: ProSwipeDecision(
        onApprove: () => _approve(b),
        onReject: () => _reject(b),
        child: child,
      ),
    );
  }

  Widget _billCard(RentUtilityBill b, bool isFullAccess, DateFormat dfDay) {
    final StatusTone tone = b.status == 'APPROVED'
        ? StatusTone(AppColors.success, b.paidAt != null ? 'Paid' : 'Approved')
        : b.status == 'REJECTED'
            ? const StatusTone(AppColors.danger, 'Rejected')
            : const StatusTone(AppColors.muted, 'Pending');
    final meta = [
      b.dueDate == null ? 'No due date' : 'Due ${dfDay.format(b.dueDate!)}',
      if (b.uploadedBy != null) 'filed by ${b.uploadedBy}',
    ].join(' · ');
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(b),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProIconWell(
                    icon: rentUtilityKindIcon(b.kind),
                    color: b.kind == RentUtilityKind.internet ? AppColors.info : const Color(0xFF9A5B00),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b.branchName} · ${rentUtilityKindLabel(b.kind)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15,
                                height: 1.33,
                                fontWeight: FontWeight.w500,
                                color: AppColors.ink)),
                        Text(meta, style: AppText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(rentMoney(b.amount),
                          style: AppText.number.copyWith(
                              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      rentTonePill(tone),
                    ],
                  ),
                ],
              ),
              if (b.kind == RentUtilityKind.internet && b.periodEnd != null && isoPeriod(b.periodEnd!) != b.period) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Text(
                      'Covers ${DateFormat('MMM yyyy').format(DateTime.tryParse(b.period) ?? _period)} – ${DateFormat('MMM yyyy').format(b.periodEnd!)}',
                      style: AppText.caption),
                ),
              ],
              if (b.status == 'REJECTED' && (b.rejectionReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                ProNote('Rejected: ${b.rejectionReason}', tone: ProNoteTone.bad),
              ],
              if (isFullAccess && b.status == 'PENDING') ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _open(b),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('View / edit'),
                    ),
                    const Spacer(),
                    _cardButton('Reject', () => _reject(b), danger: true),
                    const SizedBox(width: 8),
                    _cardButton('Approve', () => _approve(b), primary: true),
                  ],
                ),
              ] else if (isFullAccess && b.status == 'APPROVED') ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _open(b),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('View / edit'),
                    ),
                    const Spacer(),
                    b.paidAt == null
                        ? _cardButton('Mark paid', () => _markPaid(b), primary: true)
                        : TextButton(
                            onPressed: () => _markUnpaid(b),
                            child: const Text('Mark unpaid'),
                          ),
                  ],
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _open(b),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('View / edit'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Audit trail tab ──────────────────────────────────────────────────────────

class _AuditTab extends ConsumerWidget {
  const _AuditTab({required this.bottomPadding, required this.nav});
  final double bottomPadding;
  final Widget nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rentAuditTrailProvider);
    final df = DateFormat('d MMM yyyy, HH:mm');
    final all = async.valueOrNull ?? const <RentAuditLog>[];
    int count(String label) => all.where((e) => rentAuditActionTone(e.action).label == label).length;
    String v(int n) => async.hasValue ? '$n' : '—';
    return ProPage(
      onRefresh: () async => ref.invalidate(rentAuditTrailProvider),
      padding: _pagePadding(bottomPadding),
      hero: ProHero(
        title: 'Audit trail',
        subtitle: 'Every change, with who and when',
        children: [
          ProHeroStats(stats: [
            ProStat(label: 'Created', value: v(count('Created')), dot: AppColors.live),
            ProStat(label: 'Updated', value: v(count('Updated')), dot: const Color(0xFF9FCBD5)),
            ProStat(label: 'Deleted', value: v(count('Deleted')), dot: const Color(0xFFE5484D)),
          ]),
        ],
      ),
      children: [
        nav,
        async.when(
          data: (rows) {
            if (rows.isEmpty) {
              return const ProEmpty(
                icon: Icons.history_rounded,
                title: 'No audit activity yet',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(title: 'Recent activity · ${rows.length}', small: true),
                const SizedBox(height: 8),
                ProListGroup(
                  children: [for (final e in rows) _AuditRow(entry: e, df: df)],
                ),
              ],
            );
          },
          loading: () => const AppLoadingBlock(height: 200),
          error: (e, _) => AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(rentAuditTrailProvider),
          ),
        ),
      ],
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
    final icon = switch (tone.label) {
      'Created' => Icons.add_circle_outline_rounded,
      'Updated' => Icons.edit_outlined,
      'Deleted' => Icons.delete_outline_rounded,
      _ => Icons.history_rounded,
    };
    return ProListRow(
      dense: true,
      leading: ProIconWell(icon: icon, color: tone.color),
      title: '${entry.entityType} #${entry.entityId ?? '—'}',
      subtitle: entry.createdAt == null
          ? (entry.actorName ?? 'system')
          : '${df.format(entry.createdAt!)} · ${entry.actorName ?? 'system'}',
      pill: rentTonePill(tone),
      chevron: false,
    );
  }
}
