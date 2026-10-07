import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'rent_list_screen.dart';
import 'rent_models.dart';
import 'rent_repository.dart';
import 'rent_status_ui.dart';

/// Rent dashboard - mirrors web `RentDashboardTab`: KPIs and short lists for the current month's
/// payable rows (`GET /api/admin/rent/payable?period=`).
class RentDashboardTab extends ConsumerWidget {
  const RentDashboardTab({super.key, required this.bottomPadding, this.nav});

  /// Extra space below the content (the system inset is added on top).
  final double bottomPadding;

  /// Section switcher shown right under the hero.
  final Widget? nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final period = isoPeriod(now);
    final async = ref.watch(rentPayableProvider(period));
    final rows = async.valueOrNull ?? const <RentPayable>[];
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
    String v(int n) => async.hasValue ? '$n' : '—';

    // Status mix for the hero bar (deep-surface friendly colours).
    final mix = <(String, int, Color)>[
      ('Pending', rows.where((r) => r.status == RentPayableStatus.pending).length, Colors.white54),
      ('Submitted', rows.where((r) => r.status == RentPayableStatus.submitted).length, const Color(0xFF9FCBD5)),
      ('Approved', rows.where((r) => r.status == RentPayableStatus.approved).length, const Color(0xFFF2B347)),
      ('Paid', paid, AppColors.live),
      ('Held', held.length, const Color(0xFFE5484D)),
    ];

    return ProPage(
      onRefresh: () async => ref.invalidate(rentPayableProvider(period)),
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      hero: ProHero(
        title: 'Rent management',
        subtitle: 'Admin tools · ${DateFormat('MMMM yyyy').format(now)}',
        overlap: ProKpiStrip(cells: [
          ProKpi(value: v(pendingCount), label: 'Awaiting action', valueColor: AppColors.warning),
          ProKpi(value: v(held.length), label: 'On hold', valueColor: AppColors.danger),
          ProKpi(value: v(paid), label: 'Paid this month', valueColor: AppColors.success),
        ]),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Net payable (${DateFormat('MMM yyyy').format(now)})',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white70)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  async.hasValue ? rentMoney(total) : '—',
                  style: AppText.number.copyWith(
                    fontSize: 32,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.8,
                    color: Colors.white,
                  ),
                ),
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 12),
                ProStackBar(parts: [
                  for (final m in mix) MapEntry(m.$2.toDouble(), m.$3),
                ]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final m in mix)
                      if (m.$2 > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: m.$3, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text('${m.$1} ${m.$2}',
                                style: AppText.number.copyWith(
                                    fontSize: 12, color: Colors.white70)),
                          ],
                        ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
      children: [
        if (nav != null) nav!,
        async.when(
          loading: () => const AppLoadingBlock(height: 160),
          error: (e, _) => AppErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(rentPayableProvider(period))),
          data: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _list('Awaiting action', awaiting, 'Nothing awaiting action this month.', net),
              const SizedBox(height: 18),
              _list('On hold', held, 'Nothing on hold this month.', net, showReason: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(String title, List<RentPayable> rows, String empty, double Function(RentPayable) net,
      {bool showReason = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(title: '$title · ${rows.length}', small: true),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Text(empty, textAlign: TextAlign.center, style: AppText.caption),
          )
        else
          ProListGroup(
            children: [
              for (final r in rows)
                ProListRow(
                  dense: true,
                  leading: ProIconWell(
                    icon: showReason ? Icons.pause_circle_outline_rounded : Icons.receipt_long_rounded,
                    color: rentPayableStatusTone(r.status).color,
                  ),
                  title: r.branchName,
                  subtitle: showReason && (r.holdReason ?? '').isNotEmpty ? r.holdReason : null,
                  value: rentMoney(net(r)),
                  pill: showReason ? null : rentTonePill(rentPayableStatusTone(r.status)),
                  chevron: false,
                ),
            ],
          ),
      ],
    );
  }
}
