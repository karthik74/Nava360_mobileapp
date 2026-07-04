import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'travel_models.dart';
import 'travel_repository.dart';
import 'travel_status_ui.dart';

final myTravelPlansProvider =
    FutureProvider.autoDispose<List<TravelPlan>>((ref) {
  return ref.watch(travelRepositoryProvider).myPlans(size: 100);
});

/// Employee "My travel plans": a self-service list of trips with create/edit.
class TravelPlansScreen extends ConsumerStatefulWidget {
  const TravelPlansScreen({super.key});

  @override
  ConsumerState<TravelPlansScreen> createState() => _TravelPlansScreenState();
}

class _TravelPlansScreenState extends ConsumerState<TravelPlansScreen> {
  String _status = '';

  List<TravelPlan> _filter(List<TravelPlan> rows) {
    if (_status.isEmpty) return rows;
    return rows.where((r) => r.status == _status).toList();
  }

  Future<void> _create() async {
    final ok = await context.push<bool>('/travel/plans/new');
    if (ok == true) ref.invalidate(myTravelPlansProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myTravelPlansProvider);
    final mq = MediaQuery.of(context);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('My Travel Plans'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New plan'),
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: Colors.white.withOpacity(0.92),
          onRefresh: () async => ref.invalidate(myTravelPlansProvider),
          child: ListView(
            physics:
                const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 90),
            children: [
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('All', _status.isEmpty, () => setState(() => _status = '')),
                    for (final s in TravelEnums.planStatuses)
                      _chip(TravelEnums.label(s), _status == s,
                          () => setState(() => _status = _status == s ? '' : s),
                          color: planStatusTone(s).color),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              async.when(
                data: (rows) {
                  final list = _filter(rows);
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.luggage_rounded,
                      message:
                          'No travel plans yet. Tap "New plan" to record an upcoming trip.',
                    );
                  }
                  return Column(
                    children: [
                      for (final p in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PlanCard(
                            plan: p,
                            onTap: () async {
                              final ok = await context.push<bool>(
                                '/travel/plans/edit',
                                extra: p,
                              );
                              if (ok == true) ref.invalidate(myTravelPlansProvider);
                            },
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myTravelPlansProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.withOpacity(0.14) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: selected ? c.withOpacity(0.4) : AppColors.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? c : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});
  final TravelPlan plan;
  final VoidCallback onTap;

  String _dates() {
    final df = DateFormat('d MMM');
    if (plan.startDate != null && plan.endDate != null) {
      return '${df.format(plan.startDate!)} → ${DateFormat('d MMM yyyy').format(plan.endDate!)}';
    }
    if (plan.startDate != null) {
      return DateFormat('d MMM yyyy').format(plan.startDate!);
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final tone = planStatusTone(plan.status);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.primary.withOpacity(0.22)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(travelModeIcon(plan.travelMode),
                      color: AppColors.primary, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    plan.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(label: tone.label, color: tone.color),
              ],
            ),
            const SizedBox(height: 10),
            _row(Icons.place_rounded,
                '${plan.fromLocation != null && plan.fromLocation!.isNotEmpty ? '${plan.fromLocation} → ' : ''}${plan.destination ?? '—'}'),
            const SizedBox(height: 6),
            _row(Icons.event_rounded, _dates()),
            if (plan.estimatedCost != null) ...[
              const SizedBox(height: 6),
              _row(Icons.payments_rounded, 'Est. ${money(plan.estimatedCost)}'),
            ],
            if (plan.attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              _row(Icons.attach_file_rounded,
                  '${plan.attachments.length} attachment(s)'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}
