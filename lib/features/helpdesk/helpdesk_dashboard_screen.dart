import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
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

  static const _cOpen = Color(0xFF5AA9F0);
  static const _cProgress = Color(0xFFF2B347);
  static const _cClosed = Color(0x8CFFFFFF);
  static const _cOther = Color(0x40FFFFFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(helpdeskDashboardProvider);
    Future<void> refresh() async => ref.invalidate(helpdeskDashboardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Helpdesk dashboard')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ProPage(
          onRefresh: refresh,
          children: [AppErrorPanel(message: '$e', onRetry: refresh)],
        ),
        data: (d) {
          final done = d.resolved + d.closed;
          final pct = d.total == 0 ? 0 : (done * 100 / d.total).round();
          final other = (d.total - d.open - d.inProgress - d.resolved - d.closed)
              .clamp(0, d.total);
          return ProPage(
            onRefresh: refresh,
            hero: ProHero(
              title: 'Helpdesk',
              subtitle: 'Tickets in your scope',
              overlap: ProKpiStrip(cells: [
                ProKpi(value: _fmtMins(d.avgFirstResponseMins), label: 'Avg 1st response'),
                ProKpi(value: _fmtMins(d.avgResolutionMins), label: 'Avg resolution'),
                ProKpi(
                  value: '${d.slaBreached}',
                  label: 'SLA breached',
                  valueColor: d.slaBreached > 0 ? AppColors.danger : null,
                ),
              ]),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${d.total}',
                      style: const TextStyle(
                        fontSize: 40,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.2,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'tickets in total',
                        style: TextStyle(fontSize: 13.5, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('$done resolved or closed',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white70,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                        ),
                        Text('$pct%',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ProStackBar(parts: [
                      MapEntry(d.open.toDouble(), _cOpen),
                      MapEntry(d.inProgress.toDouble(), _cProgress),
                      MapEntry(d.resolved.toDouble(), AppColors.live),
                      MapEntry(d.closed.toDouble(), _cClosed),
                      MapEntry(other.toDouble(), _cOther),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        _legend('Open', d.open, _cOpen),
                        _legend('In progress', d.inProgress, _cProgress),
                        _legend('Resolved', d.resolved, AppColors.live),
                        _legend('Closed', d.closed, _cClosed),
                        if (other > 0) _legend('Other', other, _cOther),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            children: [
              const ProSectionHeader(title: 'Breakdown', small: true),
              _breakdown('By status', d.byStatus),
              _breakdown('By priority', d.byPriority),
              _breakdown('By category', d.byCategory),
              _breakdown('By branch', d.byBranch),
              _breakdown('Top agents', d.byAgent),
            ],
          );
        },
      ),
    );
  }

  Widget _legend(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
        const SizedBox(width: 5),
        Text('$value',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }

  Widget _breakdown(String title, List<HdCount> rows) {
    final max = rows.fold<int>(1, (m, r) => r.value > m ? r.value : m);
    final sum = rows.fold<int>(0, (a, r) => a + r.value);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: title,
            trailing: rows.isEmpty
                ? null
                : Text('$sum',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()])),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('No data.', style: AppText.caption),
            )
          else
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(rows[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.inkSoft)),
                        ),
                        const SizedBox(width: 10),
                        Text('${rows[i].value}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ProBar(value: rows[i].value / max, height: 6),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
