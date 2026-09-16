// ─────────────────────────────────────────────────────────────────────────────
//  My Goals — self-service screen (route: /my-goals).
//
//  Mirrors the web My Goals page: goals grouped by performance cycle, each
//  showing its approved target, any pending change, and a control to propose a
//  new target. The employee never edits the approved target directly — a
//  proposal is queued for supervisor approval.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'goal_models.dart';
import 'goal_repository.dart';

class MyGoalsScreen extends ConsumerWidget {
  const MyGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empId = ref.watch(authUserProvider)?.employeeId;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('My Goals')),
      body: empId == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: AppEmptyState(
                icon: Icons.flag_rounded,
                message:
                    "Your account isn't linked to an employee record, so there are no goals to show.",
              ),
            )
          : _GoalsBody(employeeId: empId),
    );
  }
}

class _GoalsBody extends ConsumerWidget {
  const _GoalsBody({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myGoalsProvider(employeeId));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myGoalsProvider(employeeId)),
      child: async.when(
        loading: () => const AppLoadingBlock(),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppErrorPanel(
              message: e is ApiException ? e.message : 'Failed to load your goals.',
              onRetry: () => ref.invalidate(myGoalsProvider(employeeId)),
            ),
          ],
        ),
        data: (goals) {
          if (goals.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 48),
                AppEmptyState(
                  icon: Icons.flag_rounded,
                  message:
                      'No goals assigned yet.\nPlease contact HR or your manager.',
                ),
              ],
            );
          }
          return _GoalsList(goals: goals, employeeId: employeeId);
        },
      ),
    );
  }
}

class _GoalsList extends StatelessWidget {
  const _GoalsList({required this.goals, required this.employeeId});
  final List<EmployeeGoal> goals;
  final int employeeId;

  @override
  Widget build(BuildContext context) {
    // Group by cycle, preserving the order the server returned.
    final byCycle = <int, List<EmployeeGoal>>{};
    for (final g in goals) {
      byCycle.putIfAbsent(g.cycleId, () => []).add(g);
    }
    final pending = goals.where((g) => g.hasPendingChange).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _SummaryRow(total: goals.length, pending: pending),
        const SizedBox(height: 16),
        for (final entry in byCycle.entries) ...[
          _CycleHeader(
            name: entry.value.first.cycleName,
            count: entry.value.length,
            totalWeightage:
                entry.value.fold<double>(0, (sum, g) => sum + g.weightage),
          ),
          const SizedBox(height: 8),
          for (final goal in entry.value) ...[
            _GoalCard(goal: goal, employeeId: employeeId),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.total, required this.pending});
  final int total;
  final int pending;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            icon: Icons.checklist_rounded,
            label: 'Assigned',
            value: '$total',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            icon: Icons.schedule_rounded,
            label: 'Awaiting approval',
            value: '$pending',
            color: const Color(0xFFB45309), // amber-700
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
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

class _CycleHeader extends StatelessWidget {
  const _CycleHeader({
    required this.name,
    required this.count,
    required this.totalWeightage,
  });
  final String name;
  final int count;
  final double totalWeightage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERFORMANCE CYCLE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          Text(
            '$count goal${count == 1 ? '' : 's'} · '
            '${totalWeightage.toStringAsFixed(0)}% total weightage',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends ConsumerStatefulWidget {
  const _GoalCard({required this.goal, required this.employeeId});
  final EmployeeGoal goal;
  final int employeeId;

  @override
  ConsumerState<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<_GoalCard> {
  bool _busy = false;

  Future<void> _requestChange() async {
    final goal = widget.goal;
    final value = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TargetSheet(goal: goal),
    );
    if (value == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(goalRepositoryProvider).updateMyTarget(goal.id, value);
      ref.invalidate(myGoalsProvider(widget.employeeId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Target sent to your supervisor for approval.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'Could not update the target.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final pending = goal.hasPendingChange;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pending
              ? const Color(0xFFFCD34D) // amber-300
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${goal.kpaName} / ${goal.kraName}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            goal.kpiName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(text: goal.measurementType.label),
              _Chip(text: frequencyLabel(goal.frequency)),
              _Chip(text: '${goal.weightage.toStringAsFixed(0)}% weightage'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TargetBlock(
                  label: 'Approved target',
                  value: formatTarget(goal.targetValue),
                  strong: true,
                ),
              ),
              Expanded(
                child: _TargetBlock(
                  label: 'Requested',
                  value: pending ? formatTarget(goal.pendingTargetValue) : '—',
                  amber: pending,
                ),
              ),
            ],
          ),
          if (pending) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 14, color: Color(0xFFB45309)),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Awaiting your supervisor’s approval.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _requestChange,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_rounded, size: 16),
              label: Text(pending ? 'Edit request' : 'Request change'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _TargetBlock extends StatelessWidget {
  const _TargetBlock({
    required this.label,
    required this.value,
    this.strong = false,
    this.amber = false,
  });
  final String label;
  final String value;
  final bool strong;
  final bool amber;

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
            fontSize: strong ? 19 : 17,
            fontWeight: FontWeight.w800,
            color: amber ? const Color(0xFFB45309) : AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet that captures the proposed target. Returns the value, or null
/// if dismissed. Validation mirrors the backend's validateTarget so the
/// employee is corrected before a round-trip rather than after a rejection.
class _TargetSheet extends StatefulWidget {
  const _TargetSheet({required this.goal});
  final EmployeeGoal goal;

  @override
  State<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<_TargetSheet> {
  late final TextEditingController _controller;
  double? _selectedRating;
  String? _error;

  @override
  void initState() {
    super.initState();
    final start = widget.goal.pendingTargetValue ?? widget.goal.targetValue;
    _controller = TextEditingController(
      text: start == null ? '' : formatTarget(start),
    );
    if (widget.goal.measurementType == MeasurementType.rating) {
      _selectedRating = start;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Returns an error message, or null when the value is acceptable.
  String? _validate(double? v) {
    if (v == null || !v.isFinite || v <= 0) {
      return 'Target must be greater than zero.';
    }
    switch (widget.goal.measurementType) {
      case MeasurementType.percentage:
        if (v > 100) return 'Percentage target cannot exceed 100.';
      case MeasurementType.count:
        if (v % 1 != 0) return 'Count target must be a whole number.';
      case MeasurementType.rating:
        final ok = widget.goal.ratingOptions.any((o) => o.score == v);
        if (!ok) return 'Select one of the configured ratings.';
      case MeasurementType.amount:
        break;
    }
    return null;
  }

  void _submit() {
    final raw = widget.goal.measurementType == MeasurementType.rating
        ? _selectedRating
        : double.tryParse(_controller.text.trim());
    final err = _validate(raw);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final isRating = goal.measurementType == MeasurementType.rating;

    // Flags a rating that increases risk: on a LOWER_IS_BETTER KPI anything
    // above the smallest configured score is a weaker commitment.
    String? riskNote;
    if (isRating &&
        goal.targetType == TargetType.lowerIsBetter &&
        _selectedRating != null &&
        goal.ratingOptions.isNotEmpty) {
      final lowest = goal.ratingOptions
          .map((o) => o.score)
          .reduce((a, b) => a < b ? a : b);
      if (_selectedRating! > lowest) {
        final name = goal.ratingOptions
            .firstWhere((o) => o.score == _selectedRating)
            .name;
        riskNote = '$name is a higher-risk target because lower is better.';
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              goal.kpiName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Approved target ${formatTarget(goal.targetValue)} · '
              '${goal.measurementType.label}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),

            if (isRating && goal.ratingOptions.isNotEmpty)
              DropdownButtonFormField<double>(
                initialValue: _selectedRating,
                decoration: const InputDecoration(
                  labelText: 'Requested rating',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final o in goal.ratingOptions)
                    DropdownMenuItem(
                      value: o.score,
                      child: Text('${o.name} (${formatTarget(o.score)})'),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _selectedRating = v;
                  _error = null;
                }),
              )
            else
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: goal.measurementType != MeasurementType.count,
                ),
                inputFormatters: [
                  if (goal.measurementType == MeasurementType.count)
                    FilteringTextInputFormatter.digitsOnly
                  else
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Requested target',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),

            const SizedBox(height: 8),
            Text(
              _error ?? riskNote ?? goal.measurementType.hint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: _error != null || riskNote != null
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: _error != null
                    ? Colors.red.shade700
                    : riskNote != null
                        ? const Color(0xFFB45309)
                        : AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Send for approval'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Your supervisor approves the change before it becomes the target '
              'you are measured against.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
