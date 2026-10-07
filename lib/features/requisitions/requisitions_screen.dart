import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'requisition_models.dart';
import 'requisition_repository.dart';

/// Job requisitions — a **Summary** dashboard (status / positions / pipeline /
/// per-branch rollup for the manager's hierarchy) and a **List** of requisitions,
/// with a button to raise a new one. Gated to users with REQUISITION_CREATE.
class RequisitionsScreen extends ConsumerStatefulWidget {
  const RequisitionsScreen({super.key});

  @override
  ConsumerState<RequisitionsScreen> createState() => _RequisitionsScreenState();
}

class _RequisitionsScreenState extends ConsumerState<RequisitionsScreen> {
  int _tab = 0; // 0 = Summary, 1 = List

  @override
  Widget build(BuildContext context) {
    // Both views stay live (as with the old IndexedStack), so both load.
    final dashAsync = ref.watch(requisitionDashboardProvider);
    final listAsync = ref.watch(myRequisitionsProvider);
    final d = dashAsync.asData?.value;

    String n(int? v) => v == null ? '—' : '$v';

    return Scaffold(
      appBar: AppBar(title: const Text('Job requisitions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>('/requisitions/new');
          if (created == true) {
            ref.invalidate(myRequisitionsProvider);
            ref.invalidate(requisitionDashboardProvider);
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New requisition'),
      ),
      body: ProPage(
        onRefresh: () async => _tab == 0
            ? ref.invalidate(requisitionDashboardProvider)
            : ref.invalidate(myRequisitionsProvider),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        hero: ProHero(
          title: 'Job requisitions',
          subtitle: d == null
              ? null
              : '${d.scopeLabel} · ${d.totalRequisitions} '
                  'requisition${d.totalRequisitions == 1 ? '' : 's'}',
          children: [
            ProHeroSegmented(
              labels: const ['Summary', 'List'],
              icons: const [Icons.insights_rounded, Icons.view_list_rounded],
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
            ProHeroStats(stats: [
              ProStat(label: 'Open pos.', value: n(d?.openPositions), dot: AppColors.live),
              ProStat(
                  label: 'Filled',
                  value: n(d?.filledPositions),
                  dot: const Color(0xFF7FB0EC)),
              ProStat(
                  label: 'Remaining',
                  value: n(d?.remainingPositions),
                  dot: const Color(0xFFF2B347)),
              ProStat(
                  label: 'Overdue',
                  value: n(d?.overdueCount),
                  dot: const Color(0xFFE5484D)),
            ]),
          ],
        ),
        children: _tab == 0
            ? _summaryChildren(dashAsync)
            : _listChildren(listAsync),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // List tab
  // ─────────────────────────────────────────────────────────────────────

  List<Widget> _listChildren(AsyncValue<List<RequisitionSummary>> async) {
    return [
      async.when(
        loading: () => const AppLoadingBlock(height: 160),
        error: (e, _) => AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(myRequisitionsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const ProEmpty(
              icon: Icons.work_outline_rounded,
              title: 'No requisitions yet',
              message: 'Tap "New requisition" to raise one.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(title: 'Your requisitions · ${items.length}', small: true),
              const SizedBox(height: 10),
              ProListGroup(
                children: [for (final r in items) _RequisitionRow(item: r)],
              ),
            ],
          );
        },
      ),
    ];
  }

  // ─────────────────────────────────────────────────────────────────────
  // Summary tab
  // ─────────────────────────────────────────────────────────────────────

  List<Widget> _summaryChildren(AsyncValue<RequisitionDashboard> async) {
    return async.when(
      loading: () => const [AppLoadingBlock(height: 160)],
      error: (e, _) => [
        AppErrorPanel(
          message: e.toString(),
          onRetry: () => ref.invalidate(requisitionDashboardProvider),
        ),
      ],
      data: (d) {
        if (d.totalRequisitions == 0) {
          return const [
            ProEmpty(
              icon: Icons.insights_rounded,
              title: 'No requisitions to summarise yet.',
            ),
          ];
        }
        return [
          _Section(
            title: 'By status',
            trailing: '${d.totalRequisitions} total',
            child: _StatusStrip(d: d),
          ),
          _Section(title: 'Hiring pipeline', child: _PipelineCard(d: d)),
          if (d.priorityCounts.values.any((v) => v > 0))
            _Section(title: 'By priority', child: _PriorityCard(d: d)),
          if (d.byDesignation.isNotEmpty)
            _Section(
              title: 'By designation',
              trailing: '${d.byDesignation.length}',
              child: ProListGroup(
                children: [for (final g in d.byDesignation) _DesignationRow(g: g)],
              ),
            ),
          if (d.byBranch.isNotEmpty)
            _Section(
              title: 'By branch',
              trailing: '${d.byBranch.length}',
              child: ProListGroup(
                children: [for (final b in d.byBranch) _BranchRow(b: b)],
              ),
            ),
          if (d.attention.isNotEmpty)
            _Section(
              title: 'Needs attention',
              trailing: '${d.attention.length}',
              child: ProListGroup(
                children: [for (final r in d.attention) _RequisitionRow(item: r)],
              ),
            ),
        ];
      },
    );
  }
}

/// Section title (with an optional count on the right) above its content.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(
          title: title,
          trailing: trailing == null
              ? null
              : Text(trailing!,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// One requisition: status-tinted icon, title, meta, priority / experience /
/// target-date chips and the status pill.
class _RequisitionRow extends StatelessWidget {
  const _RequisitionRow({required this.item});
  final RequisitionSummary item;

  @override
  Widget build(BuildContext context) {
    final tone = item.statusTone;
    final meta = <String>[
      if (item.designation != null && item.designation!.isNotEmpty)
        item.designation!,
      if (item.department != null && item.department!.isNotEmpty)
        item.department!,
      '${item.numberOfPositions} '
          '${item.numberOfPositions == 1 ? 'position' : 'positions'}',
      if (item.branchLabel != null && item.branchLabel!.isNotEmpty)
        item.branchLabel!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProIconWell(icon: Icons.work_outline_rounded, color: tone.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
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
                if (meta.isNotEmpty)
                  Text(meta,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption),
                if (item.priority != null ||
                    item.experienceLevel != null ||
                    item.targetDate != null) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (item.priority != null)
                        ProPill(item.priority!.label, color: item.priority!.color, dot: true),
                      if (item.experienceLevel != null)
                        ProPill(item.experienceLevel!.label, color: AppColors.accent),
                      if (item.targetDate != null)
                        ProPill.neutral('Target ${item.targetDate}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ProPill(tone.label, color: tone.color),
        ],
      ),
    );
  }
}

/// Status counts (Open / On hold / Draft / Closed) as a KPI strip.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.d});
  final RequisitionDashboard d;

  static const _statuses = [
    ('OPEN', 'Open', AppColors.success),
    ('ON_HOLD', 'On hold', AppColors.warning),
    ('DRAFT', 'Draft', AppColors.info),
    ('CLOSED', 'Closed', AppColors.muted),
  ];

  @override
  Widget build(BuildContext context) {
    return ProKpiStrip(cells: [
      for (final s in _statuses)
        ProKpi(
          value: '${d.statusCounts[s.$1] ?? 0}',
          label: s.$2,
          valueColor: s.$3,
        ),
    ]);
  }
}

/// Candidate pipeline card — headline + per-stage breakdown.
class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.d});
  final RequisitionDashboard d;

  // Pipeline stages in flow order, with friendly labels.
  static const _stages = [
    ('APPLIED', 'Applied'),
    ('INTERVIEW', 'Interview'),
    ('SELECTED', 'Selected'),
    ('OFFER_SENT', 'Offer sent'),
    ('OFFER_ACCEPTED', 'Accepted'),
    ('DOCUMENTS_SUBMITTED', 'Docs submitted'),
    ('PENDING_HIRE', 'Pending hire'),
    ('HIRED', 'Hired'),
    ('REJECTED', 'Rejected'),
    ('OFFER_DECLINED', 'Declined'),
  ];

  @override
  Widget build(BuildContext context) {
    final stages =
        _stages.where((s) => (d.pipeline[s.$1] ?? 0) > 0).toList();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _InlineStat(
                  icon: Icons.people_alt_rounded,
                  label: 'In pipeline',
                  value: d.candidatesInPipeline,
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: _InlineStat(
                  icon: Icons.verified_rounded,
                  label: 'Hired',
                  value: d.hiredCount,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          if (stages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in stages)
                  ProPill.neutral('${s.$2}  ${d.pipeline[s.$1]}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProIconWell(icon: icon, color: color),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(label, style: AppText.caption),
          ],
        ),
      ],
    );
  }
}

/// Priority breakdown as labelled bars.
class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.d});
  final RequisitionDashboard d;

  static const _order = ['URGENT', 'HIGH', 'MEDIUM', 'LOW'];

  @override
  Widget build(BuildContext context) {
    final total = d.priorityCounts.values.fold<int>(0, (a, b) => a + b);
    return GlassCard(
      child: Column(
        children: [
          for (var i = 0; i < _order.length; i++) ...[
            if (i != 0) const SizedBox(height: 12),
            _PriorityBar(
              wire: _order[i],
              count: d.priorityCounts[_order[i]] ?? 0,
              total: total,
            ),
          ],
        ],
      ),
    );
  }
}

class _PriorityBar extends StatelessWidget {
  const _PriorityBar({
    required this.wire,
    required this.count,
    required this.total,
  });
  final String wire;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = RequisitionPriority.fromWire(wire);
    final color = p?.color ?? AppColors.muted;
    final label = p?.label ?? wire;
    final fraction = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        Expanded(child: ProBar(value: fraction, color: color, height: 8)),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// One designation row in the per-designation rollup.
class _DesignationRow extends StatelessWidget {
  const _DesignationRow({required this.g});
  final DesignationBreakdown g;

  @override
  Widget build(BuildContext context) {
    return ProListRow(
      leading: ProIconWell(icon: Icons.badge_outlined, color: AppColors.primary),
      title: g.designation,
      value: '${g.requisitions} req${g.requisitions == 1 ? '' : 's'}',
      pill: ProPill.neutral('${g.openPositions} open pos.'),
    );
  }
}

/// One branch row in the per-branch rollup.
class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.b});
  final BranchBreakdown b;

  @override
  Widget build(BuildContext context) {
    return ProListRow(
      leading: ProIconWell(icon: Icons.apartment_rounded, color: AppColors.primary),
      title: b.name,
      subtitle: b.hierarchy.isNotEmpty ? b.hierarchy : null,
      value: '${b.requisitions} req${b.requisitions == 1 ? '' : 's'}',
      pill: ProPill.neutral('${b.openPositions} open pos.'),
    );
  }
}
