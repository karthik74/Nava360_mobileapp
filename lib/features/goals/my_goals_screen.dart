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
import '../../core/pro_ui.dart';
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
      appBar: AppBar(title: const Text('My goals')),
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

/// Amber used for "awaiting approval" accents.
const _amber = Color(0xFFB45309); // amber-700

/// Segment colours for the weightage-by-KPA bar on the deep hero.
const _kpaColors = [
  AppColors.live,
  Color(0xFF7FC8D8),
  Color(0xFFF2B347),
  Color(0xFFB9A4F0),
  Color(0xFFE5E9EA),
];

class _GoalsBody extends ConsumerWidget {
  const _GoalsBody({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myGoalsProvider(employeeId));
    final goals = async.valueOrNull;

    // Group by cycle, preserving the order the server returned.
    final byCycle = <int, List<EmployeeGoal>>{};
    for (final g in goals ?? const <EmployeeGoal>[]) {
      byCycle.putIfAbsent(g.cycleId, () => []).add(g);
    }
    final pending = goals?.where((g) => g.hasPendingChange).length ?? 0;
    final single = byCycle.length == 1 ? byCycle.values.first : null;
    final totalWeight =
        single?.fold<double>(0, (sum, g) => sum + g.weightage) ?? 0;

    // Weightage split by KPA (single-cycle view only).
    final byKpa = <String, double>{};
    for (final g in single ?? const <EmployeeGoal>[]) {
      final k = g.kpaName.isEmpty ? 'Other' : g.kpaName;
      byKpa[k] = (byKpa[k] ?? 0) + g.weightage;
    }
    final kpas = byKpa.entries.toList();

    final String subtitle;
    if (goals == null) {
      subtitle = 'Your targets for the performance cycle';
    } else if (single != null) {
      subtitle = 'Performance cycle · ${single.first.cycleName}';
    } else if (byCycle.isEmpty) {
      subtitle = 'No goals assigned yet';
    } else {
      subtitle = '${byCycle.length} performance cycles';
    }

    return ProPage(
      onRefresh: () async => ref.invalidate(myGoalsProvider(employeeId)),
      hero: ProHero(
        title: 'My goals',
        subtitle: subtitle,
        overlap: ProKpiStrip(
          cells: [
            ProKpi(
              value: goals == null ? '—' : '${goals.length}',
              label: 'Goals assigned',
            ),
            ProKpi(
              value: goals == null ? '—' : '$pending',
              label: 'Awaiting approval',
              valueColor: pending > 0 ? _amber : null,
            ),
            if (single != null)
              ProKpi(
                value: '${totalWeight.toStringAsFixed(0)}%',
                label: 'Total weightage',
                progress: (totalWeight / 100).clamp(0.0, 1.0),
              )
            else
              ProKpi(
                value: goals == null ? '—' : '${byCycle.length}',
                label: 'Cycles',
              ),
          ],
        ),
        children: [
          if (kpas.length > 1) ...[
            ProStackBar(parts: [
              for (var i = 0; i < kpas.length; i++)
                MapEntry(kpas[i].value, _kpaColors[i % _kpaColors.length]),
            ]),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (var i = 0; i < kpas.length; i++)
                  _KpaLegend(
                    color: _kpaColors[i % _kpaColors.length],
                    label: kpas[i].key,
                    pct: '${kpas[i].value.toStringAsFixed(0)}%',
                  ),
              ],
            ),
          ],
        ],
      ),
      children: async.when(
        loading: () => const [AppLoadingBlock(), AppLoadingBlock()],
        error: (e, _) => [
          AppErrorPanel(
            message: e is ApiException ? e.message : 'Failed to load your goals.',
            onRetry: () => ref.invalidate(myGoalsProvider(employeeId)),
          ),
        ],
        data: (goals) {
          if (goals.isEmpty) {
            return const [
              SizedBox(height: 8),
              AppEmptyState(
                icon: Icons.flag_rounded,
                message:
                    'No goals assigned yet.\nPlease contact HR or your manager.',
              ),
            ];
          }
          return [
            for (final entry in byCycle.entries) ...[
              _CycleHeader(
                name: entry.value.first.cycleName,
                count: entry.value.length,
                totalWeightage:
                    entry.value.fold<double>(0, (sum, g) => sum + g.weightage),
              ),
              for (final goal in entry.value)
                _GoalCard(goal: goal, employeeId: employeeId),
            ],
          ];
        },
      ),
    );
  }
}

class _KpaLegend extends StatelessWidget {
  const _KpaLegend({required this.color, required this.label, required this.pct});
  final Color color;
  final String label;
  final String pct;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          pct,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              'Performance cycle',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
          ProSectionHeader(
            title: name,
            subtitle: '$count goal${count == 1 ? '' : 's'} · '
                '${totalWeightage.toStringAsFixed(0)}% total weightage',
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

    return GlassCard(
      padding: const EdgeInsets.all(14),
      border: pending
          ? Border.all(color: const Color(0xFFFCD34D)) // amber-300
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(
                icon: Icons.flag_rounded,
                color: pending ? _amber : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${goal.kpaName} / ${goal.kraName}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      goal.kpiName,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ProPill.neutral(goal.measurementType.label),
              ProPill.neutral(frequencyLabel(goal.frequency)),
              ProPill.neutral('${goal.weightage.toStringAsFixed(0)}% weightage'),
              if (pending) ProPill.warn('Change requested'),
            ],
          ),
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
          ),
          if (pending) ...[
            const SizedBox(height: 10),
            const ProNote(
              'Awaiting your supervisor’s approval.',
              tone: ProNoteTone.warn,
              icon: Icons.schedule_rounded,
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
              fontSize: strong ? 20 : 18,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: amber ? _amber : AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6D3D6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Request change',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                goal.kpiName,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Approved target ${formatTarget(goal.targetValue)} · '
                '${goal.measurementType.label}',
                style: AppText.caption,
              ),
              const SizedBox(height: 18),

              if (isRating && goal.ratingOptions.isNotEmpty)
                ProField(
                  label: 'Requested rating',
                  child: DropdownButtonFormField<double>(
                    initialValue: _selectedRating,
                    isExpanded: true,
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
                  ),
                )
              else
                ProField(
                  label: 'Requested target',
                  child: TextField(
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
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      prefixText: goal.measurementType == MeasurementType.amount
                          ? '₹ '
                          : null,
                      suffixText:
                          goal.measurementType == MeasurementType.percentage
                              ? '%'
                              : null,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),

              const SizedBox(height: 8),
              Text(
                _error ?? riskNote ?? goal.measurementType.hint,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: _error != null || riskNote != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: _error != null
                      ? AppColors.danger
                      : riskNote != null
                          ? _amber
                          : AppColors.muted,
                ),
              ),
              const SizedBox(height: 14),
              const ProNote(
                'Your supervisor approves the change before it becomes the target '
                'you are measured against.',
                tone: ProNoteTone.info,
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
            ],
          ),
        ),
      ),
    );
  }
}
