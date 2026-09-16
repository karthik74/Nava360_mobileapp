import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'po_models.dart';
import 'po_repository.dart';
import 'po_status_ui.dart';

final poListProvider = FutureProvider.autoDispose<List<PurchaseOrder>>((ref) {
  return ref.watch(poRepositoryProvider).list(size: 100);
});

final poDashboardProvider = FutureProvider.autoDispose<PoDashboard>((ref) {
  return ref.watch(poRepositoryProvider).dashboard();
});

final poAuditTrailProvider = FutureProvider.autoDispose<List<PoAuditLog>>((ref) {
  return ref.watch(poRepositoryProvider).auditTrail();
});

/// Admin Tools · Purchase Orders — list + dashboard summary + audit trail,
/// mirroring `AdminPurchaseOrdersPage.tsx`'s three tabs.
class PoListScreen extends ConsumerStatefulWidget {
  const PoListScreen({super.key});

  @override
  ConsumerState<PoListScreen> createState() => _PoListScreenState();
}

enum _PoTab { orders, dashboard, audit }

class _PoListScreenState extends ConsumerState<PoListScreen> {
  _PoTab _tab = _PoTab.orders;

  Future<void> _create() async {
    final ok = await context.push<bool>('/admin/purchase-orders/new');
    if (ok == true) {
      ref.invalidate(poListProvider);
      ref.invalidate(poDashboardProvider);
      ref.invalidate(poAuditTrailProvider);
    }
  }

  Future<void> _open(PurchaseOrder po) async {
    final ok = await context.push<bool>('/admin/purchase-orders/${po.id}');
    if (ok == true) {
      ref.invalidate(poListProvider);
      ref.invalidate(poDashboardProvider);
      ref.invalidate(poAuditTrailProvider);
    }
  }

  Future<void> _delete(PurchaseOrder po) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase order?'),
        content: Text('Delete purchase order ${po.poNumber}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
      await ref.read(poRepositoryProvider).delete(po.id);
      ref.invalidate(poListProvider);
      ref.invalidate(poDashboardProvider);
      ref.invalidate(poAuditTrailProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Purchase order deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canManage = user?.hasPermission('ADMIN_PO_MANAGE') ?? false;
    final canDelete = user?.hasPermission('ADMIN_PO_DELETE') ?? false;
    final canViewReport = user?.hasPermission('ADMIN_PO_REPORT_VIEW') ?? false;
    final canViewAudit = user?.hasPermission('ADMIN_PO_AUDIT_VIEW') ?? false;
    final mq = MediaQuery.of(context);

    final tabs = <_PoTab, String>{
      _PoTab.orders: 'Orders',
      if (canViewReport) _PoTab.dashboard: 'Dashboard',
      if (canViewAudit) _PoTab.audit: 'Audit trail',
    };
    if (!tabs.containsKey(_tab)) _tab = _PoTab.orders;

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Purchase Orders'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        floatingActionButton: canManage
            ? FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New order'),
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
                _PoTab.orders => _OrdersTab(
                    canDelete: canDelete,
                    onOpen: _open,
                    onDelete: _delete,
                    bottomPadding: mq.padding.bottom + 90,
                  ),
                _PoTab.dashboard => _DashboardTab(bottomPadding: mq.padding.bottom + 24),
                _PoTab.audit => _AuditTab(bottomPadding: mq.padding.bottom + 24),
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

// ── Orders tab ──────────────────────────────────────────────────────────────

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({
    required this.canDelete,
    required this.onOpen,
    required this.onDelete,
    required this.bottomPadding,
  });

  final bool canDelete;
  final void Function(PurchaseOrder) onOpen;
  final void Function(PurchaseOrder) onDelete;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poListProvider);
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white.withOpacity(0.92),
      onRefresh: () async => ref.invalidate(poListProvider),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.receipt_long_rounded,
                  message: 'No purchase orders yet. Tap "New order" to create one.',
                );
              }
              return Column(
                children: [
                  for (final po in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PoCard(
                        po: po,
                        canDelete: canDelete,
                        onTap: () => onOpen(po),
                        onDelete: () => onDelete(po),
                      ),
                    ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(poListProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _PoCard extends StatelessWidget {
  const _PoCard({
    required this.po,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  final PurchaseOrder po;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
                  child: Icon(poDocumentIcon, color: AppColors.primary, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        po.poNumber,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                      if (po.createdByUsername != null)
                        Text(
                          'by ${po.createdByUsername}',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
                if (canDelete)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 19, color: AppColors.danger),
                    tooltip: 'Delete',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _row(Icons.store_mall_directory_rounded, po.supplierName ?? 'No supplier'),
            if (po.supplierGstin != null && po.supplierGstin!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _row(Icons.badge_rounded, 'GSTIN: ${po.supplierGstin}'),
            ],
            const SizedBox(height: 6),
            _row(Icons.event_rounded, po.poDate == null ? '—' : df.format(po.poDate!)),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _totalCol('Subtotal', po.subtotal),
                _totalCol('GST', po.gstTotal),
                _totalCol('Total', po.grandTotal, bold: true),
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

  Widget _totalCol(String label, double value, {bool bold = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(
            poMoney(value),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      );
}

// ── Dashboard tab ────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab({required this.bottomPadding});
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poDashboardProvider);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(poDashboardProvider),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            data: (data) => Column(
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    StatTileV2(
                      label: 'Total orders',
                      value: '${data.totalOrders}',
                      icon: Icons.receipt_long_rounded,
                      color: AppColors.primary,
                    ),
                    StatTileV2(
                      label: 'Total value',
                      value: poMoney(data.totalValue),
                      icon: Icons.payments_rounded,
                      color: AppColors.success,
                    ),
                    StatTileV2(
                      label: "This month's orders",
                      value: '${data.thisMonthOrders}',
                      icon: Icons.calendar_month_rounded,
                      color: AppColors.info,
                    ),
                    StatTileV2(
                      label: "This month's value",
                      value: poMoney(data.thisMonthValue),
                      icon: Icons.trending_up_rounded,
                      color: AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: AppSectionHeader(title: 'By user')),
                const SizedBox(height: 8),
                if (data.byUser.isEmpty)
                  const AppEmptyState(
                    icon: Icons.groups_rounded,
                    message: 'No data yet.',
                  )
                else
                  GlassCard(
                    padding: EdgeInsets.zero,
                    shadow: AppShadows.soft,
                    child: Column(
                      children: [
                        for (int i = 0; i < data.byUser.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    data.byUser[i].username,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  '${data.byUser[i].orderCount} order(s)',
                                  style: const TextStyle(
                                      fontSize: 11.5, color: AppColors.muted),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  poMoney(data.byUser[i].totalValue),
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            loading: () => const AppLoadingBlock(height: 200),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(poDashboardProvider),
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
    final async = ref.watch(poAuditTrailProvider);
    final df = DateFormat('d MMM yyyy, HH:mm');
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(poAuditTrailProvider),
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
              onRetry: () => ref.invalidate(poAuditTrailProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry, required this.df});
  final PoAuditLog entry;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final tone = poAuditActionTone(entry.action);
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
