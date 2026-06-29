import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'travel_models.dart';
import 'travel_repository.dart';
import 'travel_status_ui.dart';

final myTravelClaimsProvider =
    FutureProvider.autoDispose<List<TravelClaimSummary>>((ref) {
  return ref.watch(travelRepositoryProvider).myClaims(size: 100);
});

/// Employee "My travel claims": status-badged list with create + drill-in.
class TravelClaimsScreen extends ConsumerStatefulWidget {
  const TravelClaimsScreen({super.key});

  @override
  ConsumerState<TravelClaimsScreen> createState() => _TravelClaimsScreenState();
}

class _TravelClaimsScreenState extends ConsumerState<TravelClaimsScreen> {
  String _status = '';

  List<TravelClaimSummary> _filter(List<TravelClaimSummary> rows) {
    if (_status.isEmpty) return rows;
    return rows.where((r) => r.status == _status).toList();
  }

  Future<void> _create() async {
    final created = await context.push<bool>('/travel/claims/new');
    if (created == true) ref.invalidate(myTravelClaimsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myTravelClaimsProvider);
    final mq = MediaQuery.of(context);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('My Travel Claims'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Raise claim'),
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: Colors.white.withOpacity(0.92),
          onRefresh: () async => ref.invalidate(myTravelClaimsProvider),
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
                    for (final s in TravelEnums.claimStatuses)
                      _chip(claimStatusTone(s).label, _status == s,
                          () => setState(() => _status = _status == s ? '' : s),
                          color: claimStatusTone(s).color),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              async.when(
                data: (rows) {
                  final list = _filter(rows);
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.receipt_long_rounded,
                      message:
                          'No travel claims yet. Tap "Raise claim" to submit your expenses.',
                    );
                  }
                  return Column(
                    children: [
                      for (final c in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ClaimCard(
                            claim: c,
                            onTap: () async {
                              await context.push('/travel/claims/${c.id}');
                              ref.invalidate(myTravelClaimsProvider);
                            },
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myTravelClaimsProvider),
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

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({required this.claim, required this.onTap});
  final TravelClaimSummary claim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = claimStatusTone(claim.status);
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        claim.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                      if (claim.claimCode != null && claim.claimCode!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(claim.claimCode!,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(label: tone.label, color: tone.color),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  money(claim.totalClaimedAmount),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const Spacer(),
                if (claim.hasPolicyViolation)
                  const StatusPill(
                    label: 'Policy flag',
                    color: AppColors.danger,
                    icon: Icons.warning_amber_rounded,
                  ),
              ],
            ),
            if (claim.submittedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Submitted ${DateFormat('d MMM yyyy, h:mm a').format(claim.submittedAt!)}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
