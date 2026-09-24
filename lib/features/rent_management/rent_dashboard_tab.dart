import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'rent_list_screen.dart';
import 'rent_models.dart';
import 'rent_repository.dart';
import 'rent_status_ui.dart';

/// Rent dashboard - mirrors web `RentDashboardTab`: KPIs and short lists for the current month's
/// payable rows (`GET /api/admin/rent/payable?period=`).
class RentDashboardTab extends ConsumerWidget {
  const RentDashboardTab({super.key, required this.bottomPadding});
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final period = isoPeriod(now);
    final async = ref.watch(rentPayableProvider(period));
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(rentPayableProvider(period)),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          async.when(
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(rentPayableProvider(period))),
            data: (rows) {
              double net(RentPayable r) => r.netAmount ?? r.rentAmount;
              final total = rows.fold<double>(0, (s, r) => s + net(r));
              final awaiting = rows
                  .where((r) =>
                      r.status == RentPayableStatus.pending ||
                      r.status == RentPayableStatus.submitted ||
                      r.status == RentPayableStatus.approved)
                  .toList();
              final pendingCount = rows
                  .where((r) => r.status == RentPayableStatus.pending || r.status == RentPayableStatus.submitted)
                  .length;
              final held = rows.where((r) => r.status == RentPayableStatus.held).toList();
              final paid = rows.where((r) => r.status == RentPayableStatus.paid).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _kpi('Net payable (${DateFormat('MMM yyyy').format(now)})', rentMoney(total), AppColors.ink),
                    const SizedBox(width: 10),
                    _kpi('Awaiting action', '$pendingCount', AppColors.warning),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _kpi('On hold', '${held.length}', AppColors.danger),
                    const SizedBox(width: 10),
                    _kpi('Paid this month', '$paid', AppColors.success),
                  ]),
                  const SizedBox(height: 16),
                  _list('Awaiting action', awaiting, 'Nothing awaiting action this month.', net),
                  const SizedBox(height: 12),
                  _list('On hold', held, 'Nothing on hold this month.', net, showReason: true),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
        ),
      );

  Widget _list(String title, List<RentPayable> rows, String empty, double Function(RentPayable) net,
      {bool showReason = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(child: Text(empty, style: const TextStyle(fontSize: 12.5, color: AppColors.muted))),
            ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.branchName,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (showReason && (r.holdReason ?? '').isNotEmpty)
                          Text(r.holdReason!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(rentMoney(net(r)), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
