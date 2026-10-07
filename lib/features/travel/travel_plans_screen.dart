import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'travel_models.dart';
import 'travel_repository.dart';
import 'travel_status_ui.dart';

final myTravelPlansProvider =
    FutureProvider.autoDispose<List<TravelPlan>>((ref) {
  return ref.watch(travelRepositoryProvider).myPlans(size: 100);
});

/// Rounded rupee amount for the hero totals ("₹ 3,500").
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

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

  Future<void> _open(TravelPlan p) async {
    final ok = await context.push<bool>(
      '/travel/plans/edit',
      extra: p,
    );
    if (ok == true) ref.invalidate(myTravelPlansProvider);
  }

  double _est(Iterable<TravelPlan> rows) =>
      rows.fold<double>(0, (a, p) => a + (p.estimatedCost ?? 0));

  static Color _heroDot(String status) {
    switch (status) {
      case 'ACTIVE':
        return AppColors.live;
      case 'COMPLETED':
        return const Color(0xFF7FB0EC);
      default:
        return Colors.white54;
    }
  }

  /// The nearest ACTIVE plan that hasn't ended yet (data already in memory).
  TravelPlan? _nextTrip(List<TravelPlan> rows) {
    final today = DateUtils.dateOnly(DateTime.now());
    final upcoming = rows
        .where((p) =>
            p.status == 'ACTIVE' &&
            p.startDate != null &&
            !(p.endDate ?? p.startDate!).isBefore(today))
        .toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myTravelPlansProvider);
    final all = async.asData?.value ?? const <TravelPlan>[];
    const statuses = TravelEnums.planStatuses;
    final next = _status.isEmpty ? _nextTrip(all) : null;
    final shown = _filter(all);

    return Scaffold(
      appBar: AppBar(title: const Text('Travel plans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New plan'),
      ),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myTravelPlansProvider),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        hero: ProHero(
          title: 'My travel plans',
          subtitle: async.hasValue
              ? '${all.length} plan${all.length == 1 ? '' : 's'} · est. ${_inr0.format(_est(all))}'
              : null,
          children: [
            ProHeroStats(stats: [
              for (final s in statuses)
                ProStat(
                  label: planStatusTone(s).label,
                  value: '${all.where((p) => p.status == s).length}',
                  sub: 'Est. ${_inr0.format(_est(all.where((p) => p.status == s)))}',
                  dot: _heroDot(s),
                  selected: _status == s,
                  onTap: () => setState(() => _status = _status == s ? '' : s),
                ),
            ]),
          ],
        ),
        children: [
          if (next != null) _NextTripCard(plan: next, onTap: () => _open(next)),
          ProChipBar(
            labels: [
              'All',
              for (final s in statuses) TravelEnums.label(s),
            ],
            counts: [
              all.length,
              for (final s in statuses) all.where((p) => p.status == s).length,
            ],
            selected: _status.isEmpty ? 0 : statuses.indexOf(_status) + 1,
            onSelected: (i) => setState(() {
              if (i == 0) {
                _status = '';
              } else {
                final s = statuses[i - 1];
                _status = _status == s ? '' : s;
              }
            }),
            bleed: 0,
          ),
          async.when(
            data: (_) {
              if (shown.isEmpty) {
                return ProEmpty(
                  icon: Icons.luggage_rounded,
                  title: _status.isEmpty
                      ? 'No travel plans yet'
                      : 'No ${planStatusTone(_status).label.toLowerCase()} plans',
                  message: 'Tap "New plan" to record an upcoming trip.',
                  action: _status.isEmpty
                      ? FilledButton.icon(
                          onPressed: _create,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New plan'),
                        )
                      : null,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title:
                        '${_status.isEmpty ? 'All plans' : '${planStatusTone(_status).label} plans'} · ${shown.length}',
                    small: true,
                    trailing: Text(
                      'Est. ${_inr0.format(_est(shown))}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProListGroup(
                    children: [
                      for (final p in shown) _PlanRow(plan: p, onTap: () => _open(p)),
                    ],
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
    );
  }
}

String _planDates(TravelPlan plan) {
  final df = DateFormat('d MMM');
  if (plan.startDate != null && plan.endDate != null) {
    return '${df.format(plan.startDate!)} → ${DateFormat('d MMM yyyy').format(plan.endDate!)}';
  }
  if (plan.startDate != null) {
    return DateFormat('d MMM yyyy').format(plan.startDate!);
  }
  return '—';
}

String _planRoute(TravelPlan plan) =>
    '${plan.fromLocation != null && plan.fromLocation!.isNotEmpty ? '${plan.fromLocation} → ' : ''}${plan.destination ?? '—'}';

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.onTap});
  final TravelPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = planStatusTone(plan.status);
    return ProListRow(
      leading: ProIconWell(icon: travelModeIcon(plan.travelMode), color: AppColors.primary),
      title: plan.title,
      titleMaxLines: 2,
      subtitle: _planRoute(plan),
      meta: [
        _planDates(plan),
        if (plan.attachments.isNotEmpty) '${plan.attachments.length} attachment(s)',
      ].join(' · '),
      value: plan.estimatedCost != null ? 'Est. ${money(plan.estimatedCost)}' : null,
      pill: ProPill(tone.label, color: tone.color),
      onTap: onTap,
    );
  }
}

/// Featured "next trip" card (nearest active plan) with a from → to route.
class _NextTripCard extends StatelessWidget {
  const _NextTripCard({required this.plan, required this.onTap});
  final TravelPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = DateUtils.dateOnly(plan.startDate!);
    final inDays = start.difference(today).inDays;
    final when = inDays <= 0
        ? 'On the road now'
        : (inDays == 1 ? 'Tomorrow' : 'In $inDays days');
    final df = DateFormat('EEE, d MMM');
    final days = plan.endDate == null
        ? null
        : DateUtils.dateOnly(plan.endDate!).difference(start).inDays + 1;
    final tone = planStatusTone(plan.status);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Next trip · $when',
                        style: AppText.caption.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  ProPill(tone.label, color: tone.color, dot: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(plan.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _RouteEnd(
                      place: (plan.fromLocation ?? '').isEmpty ? '—' : plan.fromLocation!,
                      date: df.format(plan.startDate!),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(travelModeIcon(plan.travelMode),
                        size: 20, color: AppColors.primary),
                  ),
                  Expanded(
                    child: _RouteEnd(
                      place: plan.destination ?? '—',
                      date: plan.endDate == null ? '' : df.format(plan.endDate!),
                      end: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (plan.travelMode != null)
                    ProPill.neutral(TravelEnums.label(plan.travelMode)),
                  if (days != null) ProPill.neutral('$days day${days == 1 ? '' : 's'}'),
                  if (plan.estimatedCost != null)
                    ProPill.neutral('Est. ${money(plan.estimatedCost)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteEnd extends StatelessWidget {
  const _RouteEnd({required this.place, required this.date, this.end = false});
  final String place;
  final String date;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(place,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
        if (date.isNotEmpty) Text(date, style: AppText.caption),
      ],
    );
  }
}
