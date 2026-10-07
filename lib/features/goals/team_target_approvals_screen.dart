// ─────────────────────────────────────────────────────────────────────────────
//  Target Approvals — supervisor screen (route: /team-target-approvals).
//
//  Mirrors the web Team Review page: target changes requested by direct reports,
//  scoped to one performance cycle, each approvable in place. Unlike the web
//  page — which starts with no cycle selected — this defaults to the ACTIVE
//  cycle so the queue is visible without a first tap.
//
//  Approve-only by design: the backend exposes no reject endpoint. A supervisor
//  who disagrees leaves the request pending and settles it with the employee,
//  who can then amend their own request.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'goal_models.dart';
import 'goal_repository.dart';

class TeamTargetApprovalsScreen extends ConsumerStatefulWidget {
  const TeamTargetApprovalsScreen({super.key});

  @override
  ConsumerState<TeamTargetApprovalsScreen> createState() =>
      _TeamTargetApprovalsScreenState();
}

class _TeamTargetApprovalsScreenState
    extends ConsumerState<TeamTargetApprovalsScreen> {
  /// Explicit pick; null ⇒ fall back to the ACTIVE cycle.
  int? _cycleId;

  @override
  Widget build(BuildContext context) {
    final empId = ref.watch(authUserProvider)?.employeeId;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Target approvals')),
      body: empId == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: AppEmptyState(
                icon: Icons.fact_check_rounded,
                message:
                    "Your account isn't linked to an employee record, so there is nothing to approve.",
              ),
            )
          : _body(empId),
    );
  }

  Widget _body(int managerEmployeeId) {
    final cyclesAsync = ref.watch(performanceCyclesProvider);

    ProPage simplePage(Widget child) => ProPage(
          hero: const ProHero(
            kicker: 'My team',
            title: 'Target approvals',
            subtitle: 'Target changes your reports have asked for',
          ),
          children: [child],
        );

    return cyclesAsync.when(
      loading: () => simplePage(const AppLoadingBlock()),
      error: (e, _) => simplePage(
        AppErrorPanel(
          message: e is ApiException
              ? e.message
              : 'Failed to load performance cycles.',
          onRetry: () => ref.invalidate(performanceCyclesProvider),
        ),
      ),
      data: (cycles) {
        if (cycles.isEmpty) {
          return simplePage(
            const AppEmptyState(
              icon: Icons.event_busy_rounded,
              message: 'No performance cycles have been set up yet.',
            ),
          );
        }

        // Default to the active cycle, else the first one the server returned.
        final selectedId = _cycleId ??
            cycles.firstWhere((c) => c.isActive, orElse: () => cycles.first).id;
        final selected = cycles.firstWhere(
          (c) => c.id == selectedId,
          orElse: () => cycles.first,
        );

        return _PendingList(
          managerEmployeeId: managerEmployeeId,
          cycleId: selectedId,
          cycleName: selected.name,
          picker: _CyclePicker(
            cycles: cycles,
            selectedId: selectedId,
            onChanged: (id) => setState(() => _cycleId = id),
          ),
        );
      },
    );
  }
}

/// Raised cycle selector that straddles the hero.
class _CyclePicker extends StatelessWidget {
  const _CyclePicker({
    required this.cycles,
    required this.selectedId,
    required this.onChanged,
  });
  final List<PerformanceCycle> cycles;
  final int selectedId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.lifted,
      ),
      child: Row(
        children: [
          Icon(Icons.event_note_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Performance cycle',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: cycles.any((c) => c.id == selectedId)
                        ? selectedId
                        : null,
                    isExpanded: true,
                    isDense: true,
                    borderRadius: BorderRadius.circular(14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.muted),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                    items: [
                      for (final c in cycles)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            c.isActive ? '${c.name} · Active' : c.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) onChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingList extends ConsumerWidget {
  const _PendingList({
    required this.managerEmployeeId,
    required this.cycleId,
    required this.cycleName,
    required this.picker,
  });
  final int managerEmployeeId;
  final int cycleId;
  final String cycleName;
  final Widget picker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = TeamTargetQuery(
      managerEmployeeId: managerEmployeeId,
      cycleId: cycleId,
    );
    final async = ref.watch(teamTargetChangesProvider(query));
    final n = async.valueOrNull?.length;

    return ProPage(
      onRefresh: () async => ref.invalidate(teamTargetChangesProvider(query)),
      hero: ProHero(
        kicker: 'My team',
        title: 'Target approvals',
        subtitle: n == null
            ? cycleName
            : (n == 0
                ? 'All caught up · $cycleName'
                : '$n pending change${n == 1 ? '' : 's'} · $cycleName'),
        overlap: picker,
      ),
      children: async.when(
        loading: () => const [AppLoadingBlock()],
        error: (e, _) => [
          AppErrorPanel(
            message: e is ApiException
                ? e.message
                : 'Failed to load pending target changes.',
            onRetry: () => ref.invalidate(teamTargetChangesProvider(query)),
          ),
        ],
        data: (changes) {
          if (changes.isEmpty) {
            return const [
              SizedBox(height: 8),
              AppEmptyState(
                icon: Icons.check_circle_outline_rounded,
                message: 'No pending target changes for this cycle.',
              ),
            ];
          }
          return [
            const ProNote(
              'Changes can only be approved here. If you disagree, leave it '
              'pending and talk it through — they can amend their own request.',
              tone: ProNoteTone.info,
            ),
            const ProSwipeHint(text: 'Swipe right to approve'),
            for (final c in changes) _ChangeCard(change: c, query: query),
          ];
        },
      ),
    );
  }
}

class _ChangeCard extends ConsumerStatefulWidget {
  const _ChangeCard({required this.change, required this.query});
  final EmployeeGoal change;
  final TeamTargetQuery query;

  @override
  ConsumerState<_ChangeCard> createState() => _ChangeCardState();
}

class _ChangeCardState extends ConsumerState<_ChangeCard> {
  bool _busy = false;

  Future<void> _approve() async {
    final c = widget.change;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve target change?'),
        content: Text(
          '${c.employeeName}\n${c.kpiName}\n\n'
          'Target becomes ${formatTarget(c.pendingTargetValue)} '
          '(was ${formatTarget(c.targetValue)}). '
          'This is the figure their achievement will be measured against.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(goalRepositoryProvider).approveTargetChange(c.id);
      ref.invalidate(teamTargetChangesProvider(widget.query));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target change approved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'Could not approve the change.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final name = c.employeeName.isEmpty ? 'Employee' : c.employeeName;

    final card = GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProAvatar(name: name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (c.employeeCode.isNotEmpty)
                      Text(c.employeeCode, style: AppText.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ProPill.neutral(c.measurementType.label),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            c.kpiName,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 1),
          Text('${c.kpaName} → ${c.kraName}', style: AppText.caption),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Current',
                    value: formatTarget(c.targetValue),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: _Figure(
                    label: 'Requested',
                    value: formatTarget(c.pendingTargetValue),
                    highlight: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _approve,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_busy ? 'Approving…' : 'Approve'),
            ),
          ),
        ],
      ),
    );

    // Swipe right to approve — runs the same confirm + approve flow.
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: ProSwipeDecision(
        onApprove: () async {
          if (!_busy) await _approve();
        },
        child: card,
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: highlight ? AppColors.primary : AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
