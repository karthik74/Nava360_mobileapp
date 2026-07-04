import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New requisition'),
      ),
      body: GlassBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _SegmentBar(
                  value: _tab,
                  labels: const ['Summary', 'List'],
                  onChanged: (v) => setState(() => _tab = v),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: const [_SummaryView(), _ListView()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill segmented control (Summary / List).
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.value,
    required this.labels,
    required this.onChanged,
  });
  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == i ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: value == i ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// List tab
// ─────────────────────────────────────────────────────────────────────

class _ListView extends ConsumerWidget {
  const _ListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRequisitionsProvider);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(myRequisitionsProvider),
      child: async.when(
        loading: () => ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(myRequisitionsProvider),
            ),
          ],
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 60),
                AppEmptyState(
                  icon: Icons.work_outline_rounded,
                  message: 'No requisitions yet.\nTap "New requisition" to '
                      'raise one.',
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _RequisitionCard(item: items[i]),
          );
        },
      ),
    );
  }
}

class _RequisitionCard extends StatelessWidget {
  const _RequisitionCard({required this.item});
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

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              meta,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (item.priority != null) ...[
                StatusPill(
                  label: item.priority!.label,
                  color: item.priority!.color,
                  icon: Icons.flag_rounded,
                ),
                const SizedBox(width: 8),
              ],
              if (item.experienceLevel != null)
                StatusPill(
                  label: item.experienceLevel!.label,
                  color: AppColors.accent,
                  icon: Icons.trending_up_rounded,
                ),
              const Spacer(),
              if (item.targetDate != null)
                Text(
                  'Target ${item.targetDate}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Summary tab
// ─────────────────────────────────────────────────────────────────────

class _SummaryView extends ConsumerWidget {
  const _SummaryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(requisitionDashboardProvider);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(requisitionDashboardProvider),
      child: async.when(
        loading: () => ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(requisitionDashboardProvider),
            ),
          ],
        ),
        data: (d) {
          if (d.totalRequisitions == 0) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 60),
                AppEmptyState(
                  icon: Icons.insights_rounded,
                  message: 'No requisitions to summarise yet.',
                ),
              ],
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _HeroCard(d: d),
              const SizedBox(height: 18),
              const _SectionTitle('By status'),
              const SizedBox(height: 10),
              _StatusGrid(d: d),
              const SizedBox(height: 18),
              const _SectionTitle('Hiring pipeline'),
              const SizedBox(height: 10),
              _PipelineCard(d: d),
              if (d.priorityCounts.values.any((v) => v > 0)) ...[
                const SizedBox(height: 18),
                const _SectionTitle('By priority'),
                const SizedBox(height: 10),
                _PriorityCard(d: d),
              ],
              if (d.byDesignation.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SectionTitle('By designation',
                    trailing: '${d.byDesignation.length}'),
                const SizedBox(height: 10),
                for (final g in d.byDesignation)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DesignationRow(g: g),
                  ),
              ],
              if (d.byBranch.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SectionTitle('By branch', trailing: '${d.byBranch.length}'),
                const SizedBox(height: 10),
                for (final b in d.byBranch)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _BranchRow(b: b),
                  ),
              ],
              if (d.attention.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SectionTitle('Needs attention',
                    trailing: '${d.attention.length}'),
                const SizedBox(height: 10),
                for (final r in d.attention)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RequisitionCard(item: r),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Hero KPI card — total requisitions + positions/overdue at a glance.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.d});
  final RequisitionDashboard d;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.32),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${d.totalRequisitions} '
              'requisition${d.totalRequisitions == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              d.scopeLabel,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    label: 'Open pos.',
                    value: d.openPositions,
                    color: const Color(0xFF34D399),
                  ),
                ),
                _heroDivider(),
                Expanded(
                  child: _HeroStat(
                    label: 'Filled',
                    value: d.filledPositions,
                    color: const Color(0xFF60A5FA),
                  ),
                ),
                _heroDivider(),
                Expanded(
                  child: _HeroStat(
                    label: 'Remaining',
                    value: d.remainingPositions,
                    color: const Color(0xFFFBBF24),
                  ),
                ),
                _heroDivider(),
                Expanded(
                  child: _HeroStat(
                    label: 'Overdue',
                    value: d.overdueCount,
                    color: const Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroDivider() =>
      Container(width: 1, height: 28, color: Colors.white.withOpacity(0.18));
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// 2×2 grid of status counts (Draft / Open / On hold / Closed).
class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.d});
  final RequisitionDashboard d;

  static const _statuses = [
    ('OPEN', 'Open', AppColors.success),
    ('ON_HOLD', 'On hold', AppColors.warning),
    ('DRAFT', 'Draft', AppColors.info),
    ('CLOSED', 'Closed', AppColors.muted),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _statuses.length; i++) ...[
          Expanded(
            child: _CountTile(
              label: _statuses[i].$2,
              value: d.statusCounts[_statuses[i].$1] ?? 0,
              color: _statuses[i].$3,
            ),
          ),
          if (i != _statuses.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in stages)
                  StatusPill(
                    label: '${s.$2}  ${d.pipeline[s.$1]}',
                    color: AppColors.inkSoft,
                  ),
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
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
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
            if (i != 0) const SizedBox(height: 10),
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
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 24,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
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
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              g.designation,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${g.requisitions} '
                'req${g.requisitions == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              Text(
                '${g.openPositions} open pos.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One branch row in the per-branch rollup.
class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.b});
  final BranchBreakdown b;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (b.hierarchy.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    b.hierarchy,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${b.requisitions} '
                'req${b.requisitions == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              Text(
                '${b.openPositions} open pos.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
