import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';

/// Scoped helpdesk dashboard (Phase 6) — KPIs + breakdowns for team/all viewers.
class HelpdeskDashboardScreen extends ConsumerWidget {
  const HelpdeskDashboardScreen({super.key});

  static String _fmtMins(double? m) {
    if (m == null) return '—';
    if (m < 60) return '${m.round()}m';
    final h = m / 60;
    if (h < 24) return '${h.toStringAsFixed(1)}h';
    return '${(h / 24).toStringAsFixed(1)}d';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(helpdeskDashboardProvider);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          title: const Text('Helpdesk Dashboard'),
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(helpdeskDashboardProvider),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(children: [
              Padding(padding: const EdgeInsets.all(24), child: AppErrorPanel(message: '$e')),
            ]),
            data: (d) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _kpi('Total', d.total, AppColors.ink),
                    _kpi('Open', d.open, AppColors.info),
                    _kpi('In Progress', d.inProgress, AppColors.warning),
                    _kpi('Resolved', d.resolved, AppColors.success),
                    _kpi('Closed', d.closed, AppColors.muted),
                    _kpi('SLA Breached', d.slaBreached, AppColors.danger),
                  ],
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _stat('Avg 1st Response', _fmtMins(d.avgFirstResponseMins))),
                  const SizedBox(width: 10),
                  Expanded(child: _stat('Avg Resolution', _fmtMins(d.avgResolutionMins))),
                ]),
                const SizedBox(height: 16),
                _breakdown('By Status', d.byStatus),
                _breakdown('By Priority', d.byPriority),
                _breakdown('By Category', d.byCategory),
                _breakdown('By Branch', d.byBranch),
                _breakdown('Top Agents', d.byAgent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpi(String label, int value, Color color) {
    return Container(
      width: 108,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _breakdown(String title, List<HdCount> rows) {
    final max = rows.fold<int>(1, (m, r) => r.value > m ? r.value : m);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No data.', style: TextStyle(color: AppColors.muted)))
          else
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(r.label, style: const TextStyle(fontSize: 13, color: AppColors.ink))),
                          Text('${r.value}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: r.value / max,
                          minHeight: 6,
                          backgroundColor: AppColors.surfaceAlt,
                          valueColor: AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
