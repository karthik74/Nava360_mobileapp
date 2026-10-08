import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'po_models.dart';
import 'po_pdf.dart';
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

  /// In-memory search + sort over the loaded order list.
  final _q = TextEditingController();
  bool _byValue = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

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

    final tabs = <_PoTab, String>{
      _PoTab.orders: 'Orders',
      if (canViewReport) _PoTab.dashboard: 'Dashboard',
      if (canViewAudit) _PoTab.audit: 'Audit trail',
    };
    if (!tabs.containsKey(_tab)) _tab = _PoTab.orders;
    final tabKeys = tabs.keys.toList();

    // Hero figures come from the order list (the Orders tab's own data).
    final orders = ref.watch(poListProvider).asData?.value;
    final now = DateTime.now();
    final thisMonth = orders
        ?.where((p) =>
            p.poDate != null && p.poDate!.year == now.year && p.poDate!.month == now.month)
        .toList();
    double total(Iterable<PurchaseOrder> rows) =>
        rows.fold<double>(0, (a, p) => a + p.grandTotal);

    final provider = switch (_tab) {
      _PoTab.orders => poListProvider,
      _PoTab.dashboard => poDashboardProvider,
      _PoTab.audit => poAuditTrailProvider,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Purchase orders')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New order'),
            )
          : null,
      body: ProPage(
        onRefresh: () async => ref.invalidate(provider),
        padding: EdgeInsets.fromLTRB(16, 16, 16, canManage ? 96 : 24),
        hero: ProHero(
          title: 'Purchase orders',
          subtitle: orders == null
              ? 'Admin tools'
              : 'Admin tools · ${orders.length} order${orders.length == 1 ? '' : 's'}',
          overlap: _tab == _PoTab.orders
              ? ProSearchField(
                  raised: true,
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  hint: 'PO number, supplier or GSTIN',
                )
              : null,
          children: [
            if (tabs.length > 1)
              ProHeroSegmented(
                labels: tabs.values.toList(),
                selected: tabKeys.indexOf(_tab),
                onChanged: (i) => setState(() => _tab = tabKeys[i]),
              ),
            ProHeroStats(stats: [
              ProStat(
                label: 'Orders',
                value: orders == null ? '—' : '${orders.length}',
                sub: orders == null ? null : _inr0.format(total(orders)),
                dot: AppColors.live,
              ),
              ProStat(
                label: 'This month',
                value: thisMonth == null ? '—' : '${thisMonth.length}',
                sub: thisMonth == null ? null : _inr0.format(total(thisMonth)),
                dot: const Color(0xFF7FB0EC),
              ),
            ]),
          ],
        ),
        children: [
          switch (_tab) {
            _PoTab.orders => _OrdersTab(
                canDelete: canDelete,
                onOpen: _open,
                onDelete: _delete,
                query: _q.text,
                byValue: _byValue,
                onToggleSort: () => setState(() => _byValue = !_byValue),
              ),
            _PoTab.dashboard => const _DashboardTab(),
            _PoTab.audit => const _AuditTab(),
          },
        ],
      ),
    );
  }
}

/// Rounded rupee amount for the hero figures ("₹ 1,24,500").
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

// ── Orders tab ──────────────────────────────────────────────────────────────

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({
    required this.canDelete,
    required this.onOpen,
    required this.onDelete,
    required this.query,
    required this.byValue,
    required this.onToggleSort,
  });

  final bool canDelete;
  final void Function(PurchaseOrder) onOpen;
  final void Function(PurchaseOrder) onDelete;

  /// Search text (PO number / supplier / GSTIN / creator), in-memory filter.
  final String query;

  /// Sort by grand total (highest first) instead of the server's order.
  final bool byValue;
  final VoidCallback onToggleSort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poListProvider);
    return async.when(
      data: (rows) {
        if (rows.isEmpty) {
          return const ProEmpty(
            icon: Icons.receipt_long_rounded,
            title: 'No purchase orders yet',
            message: 'Tap "New order" to create one.',
          );
        }
        final term = query.trim().toLowerCase();
        final shown = rows.where((po) {
          if (term.isEmpty) return true;
          return po.poNumber.toLowerCase().contains(term) ||
              (po.supplierName ?? '').toLowerCase().contains(term) ||
              (po.supplierGstin ?? '').toLowerCase().contains(term) ||
              (po.createdByUsername ?? '').toLowerCase().contains(term);
        }).toList();
        if (byValue) shown.sort((a, b) => b.grandTotal.compareTo(a.grandTotal));
        if (shown.isEmpty) {
          return ProEmpty(
            icon: Icons.search_off_rounded,
            title: 'No orders match “${query.trim()}”',
            message: 'Search by PO number, supplier, GSTIN or creator.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(
              title: '${term.isEmpty ? 'All orders' : 'Matching orders'} · ${shown.length}',
              small: true,
              trailing: TextButton.icon(
                onPressed: onToggleSort,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.swap_vert_rounded, size: 17),
                label: Text(byValue ? 'Highest value' : 'Recent'),
              ),
            ),
            const SizedBox(height: 8),
            ProListGroup(
              children: [
                for (final po in shown)
                  _PoRow(
                    po: po,
                    canDelete: canDelete,
                    onTap: () => onOpen(po),
                    onDelete: () => onDelete(po),
                  ),
              ],
            ),
          ],
        );
      },
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(poListProvider),
      ),
    );
  }
}

class _PoRow extends StatelessWidget {
  const _PoRow({
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
    final sub = [
      po.poNumber,
      po.poDate == null ? '—' : df.format(po.poDate!),
      if (po.createdByUsername != null) 'by ${po.createdByUsername}',
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(icon: poDocumentIcon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            po.supplierName ?? 'No supplier',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.33,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.15,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          poMoney(po.grandTotal),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    Text(sub,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption),
                    if (po.supplierGstin != null && po.supplierGstin!.isNotEmpty)
                      Text('GSTIN: ${po.supplierGstin}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ProPill.neutral('Sub ${poMoney(po.subtotal)}'),
                              ProPill.info('GST ${poMoney(po.gstTotal)}'),
                            ],
                          ),
                        ),
                        Consumer(
                          builder: (ctx, ref, _) => IconButton(
                            onPressed: () => downloadPoPdf(
                                ctx, () => ref.read(poRepositoryProvider).get(po.id)),
                            icon: Icon(Icons.picture_as_pdf_rounded,
                                size: 19, color: AppColors.primary),
                            tooltip: 'Download PDF',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                          ),
                        ),
                        if (canDelete)
                          IconButton(
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 19, color: AppColors.danger),
                            tooltip: 'Delete',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashboard tab ────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poDashboardProvider);
    return async.when(
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Overview'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
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
          const SizedBox(height: 22),
          const ProSectionHeader(title: 'By user', subtitle: 'Order value'),
          const SizedBox(height: 10),
          if (data.byUser.isEmpty)
            const ProEmpty(
              icon: Icons.groups_rounded,
              title: 'No data yet.',
            )
          else
            ProListGroup(
              children: [
                for (final u in data.byUser)
                  ProListRow(
                    leading: ProAvatar(name: u.username, size: 36),
                    title: u.username,
                    subtitle: '${u.orderCount} order(s)',
                    value: poMoney(u.totalValue),
                  ),
              ],
            ),
        ],
      ),
      loading: () => const AppLoadingBlock(height: 200),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(poDashboardProvider),
      ),
    );
  }
}

// ── Audit trail tab ──────────────────────────────────────────────────────────

class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poAuditTrailProvider);
    final df = DateFormat('d MMM yyyy, HH:mm');
    return async.when(
      data: (rows) {
        if (rows.isEmpty) {
          return const ProEmpty(
            icon: Icons.history_rounded,
            title: 'No audit activity yet.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(title: 'Activity · ${rows.length}', small: true),
            const SizedBox(height: 8),
            ProListGroup(
              children: [for (final r in rows) _AuditRow(entry: r, df: df)],
            ),
          ],
        );
      },
      loading: () => const AppLoadingBlock(height: 200),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(poAuditTrailProvider),
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry, required this.df});
  final PoAuditLog entry;
  final DateFormat df;

  IconData get _icon {
    switch (entry.action.toUpperCase()) {
      case 'CREATE':
      case 'CREATED':
        return Icons.add_rounded;
      case 'UPDATE':
      case 'UPDATED':
        return Icons.edit_rounded;
      case 'DELETE':
      case 'DELETED':
        return Icons.delete_outline_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = poAuditActionTone(entry.action);
    return ProListRow(
      leading: ProIconWell(icon: _icon, color: tone.color),
      title: '${entry.entityType} #${entry.entityId ?? '—'}',
      subtitle: entry.createdAt == null
          ? (entry.actorName ?? 'system')
          : '${df.format(entry.createdAt!)} · ${entry.actorName ?? 'system'}',
      pill: ProPill(tone.label, color: tone.color),
    );
  }
}
