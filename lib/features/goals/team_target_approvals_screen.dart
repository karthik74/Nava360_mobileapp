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
      appBar: AppBar(title: const Text('Target Approvals')),
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

    return cyclesAsync.when(
      loading: () => const AppLoadingBlock(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: AppErrorPanel(
          message: e is ApiException
              ? e.message
              : 'Failed to load performance cycles.',
          onRetry: () => ref.invalidate(performanceCyclesProvider),
        ),
      ),
      data: (cycles) {
        if (cycles.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: AppEmptyState(
              icon: Icons.event_busy_rounded,
              message: 'No performance cycles have been set up yet.',
            ),
          );
        }

        // Default to the active cycle, else the first one the server returned.
        final selectedId = _cycleId ??
            cycles.firstWhere((c) => c.isActive, orElse: () => cycles.first).id;

        return Column(
          children: [
            _CyclePicker(
              cycles: cycles,
              selectedId: selectedId,
              onChanged: (id) => setState(() => _cycleId = id),
            ),
            Expanded(
              child: _PendingList(
                managerEmployeeId: managerEmployeeId,
                cycleId: selectedId,
              ),
            ),
          ],
        );
      },
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: DropdownButtonFormField<int>(
        initialValue: selectedId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Performance cycle',
          border: OutlineInputBorder(),
          isDense: true,
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
    );
  }
}

class _PendingList extends ConsumerWidget {
  const _PendingList({
    required this.managerEmployeeId,
    required this.cycleId,
  });
  final int managerEmployeeId;
  final int cycleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = TeamTargetQuery(
      managerEmployeeId: managerEmployeeId,
      cycleId: cycleId,
    );
    final async = ref.watch(teamTargetChangesProvider(query));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(teamTargetChangesProvider(query)),
      child: async.when(
        loading: () => const AppLoadingBlock(),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppErrorPanel(
              message: e is ApiException
                  ? e.message
                  : 'Failed to load pending target changes.',
              onRetry: () => ref.invalidate(teamTargetChangesProvider(query)),
            ),
          ],
        ),
        data: (changes) {
          if (changes.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 48),
                AppEmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  message: 'No pending target changes for this cycle.',
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: changes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ChangeCard(
              change: changes[i],
              query: query,
            ),
          );
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.employeeName.isEmpty ? 'Employee' : c.employeeName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (c.employeeCode.isNotEmpty)
                      Text(
                        c.employeeCode,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  c.measurementType.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            c.kpiName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          Text(
            '${c.kpaName} → ${c.kraName}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Current',
                  value: formatTarget(c.targetValue),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: _Figure(
                  label: 'Requested',
                  value: formatTarget(c.pendingTargetValue),
                  highlight: true,
                ),
              ),
            ],
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
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: highlight ? AppColors.primary : AppColors.ink,
          ),
        ),
      ],
    );
  }
}
