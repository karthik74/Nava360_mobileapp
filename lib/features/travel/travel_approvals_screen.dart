import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'travel_models.dart';
import 'travel_repository.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Shared helpers (status tone + money) reused by the review screen too.
// ════════════════════════════════════════════════════════════════════════════

/// (colour, label) for any `TravelClaimStatus` constant.
StatusTone travelClaimTone(String s) {
  switch (s) {
    case 'DRAFT':
      return const StatusTone(AppColors.muted, 'Draft');
    case 'SUBMITTED':
      return const StatusTone(AppColors.warning, 'Submitted');
    case 'LEVEL_1_APPROVED':
      return const StatusTone(AppColors.info, 'L1 Approved');
    case 'LEVEL_2_APPROVED':
      return const StatusTone(AppColors.info, 'L2 Approved');
    case 'LEVEL_3_APPROVED':
      return const StatusTone(AppColors.info, 'L3 Approved');
    case 'APPROVED':
      return const StatusTone(AppColors.success, 'Approved');
    case 'REJECTED':
      return const StatusTone(AppColors.danger, 'Rejected');
    case 'SENT_BACK':
      return const StatusTone(AppColors.warning, 'Sent Back');
    case 'SETTLED':
      return const StatusTone(AppColors.primary, 'Settled');
    default:
      return StatusTone(AppColors.muted, TravelEnums.label(s));
  }
}

/// (colour, label) for an approval-step status (`TravelApprovalStepStatus`).
StatusTone travelStepTone(String s) {
  switch (s) {
    case 'APPROVED':
      return const StatusTone(AppColors.success, 'Approved');
    case 'REJECTED':
      return const StatusTone(AppColors.danger, 'Rejected');
    case 'SENT_BACK':
      return const StatusTone(AppColors.warning, 'Sent Back');
    case 'PENDING':
      return const StatusTone(AppColors.warning, 'Pending');
    case 'SKIPPED':
      return const StatusTone(AppColors.muted, 'Skipped');
    default:
      return const StatusTone(AppColors.muted, 'Waiting');
  }
}

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String travelMoney(double? v) => _money.format(v ?? 0);

String travelDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

String travelDateTime(DateTime? d) =>
    d == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(d);

// ════════════════════════════════════════════════════════════════════════════
//  Providers
// ════════════════════════════════════════════════════════════════════════════

/// Claims whose current PENDING approval step is assigned to the signed-in user.
final travelInboxProvider =
    FutureProvider.autoDispose<List<TravelClaimSummary>>((ref) {
  return ref.watch(travelRepositoryProvider).inbox();
});

/// Fully APPROVED claims awaiting finance/admin settlement.
final travelSettlementQueueProvider =
    FutureProvider.autoDispose<List<TravelClaimSummary>>((ref) {
  return ref.watch(travelRepositoryProvider).settlementQueue();
});

// ════════════════════════════════════════════════════════════════════════════
//  Screen — Travel Approvals (approver inbox + finance settlement queue)
// ════════════════════════════════════════════════════════════════════════════

class TravelApprovalsScreen extends ConsumerWidget {
  const TravelApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final canApprove = user?.hasPermission('TRAVEL_CLAIM_APPROVE') ?? false;
    final canSettle = user?.hasPermission('TRAVEL_CLAIM_SETTLE') ?? false;

    // Build the visible tabs from what the user is allowed to do. If neither
    // permission is present we still show the inbox tab (it will simply be
    // empty / surface the server's 403 — the drawer already gates entry).
    final tabs = <_ApprovalTab>[
      if (canApprove || !canSettle)
        const _ApprovalTab(
          label: 'My Inbox',
          icon: Icons.inbox_rounded,
          settlement: false,
        ),
      if (canSettle)
        const _ApprovalTab(
          label: 'To Settle',
          icon: Icons.account_balance_wallet_rounded,
          settlement: true,
        ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: GlassBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Travel Approvals'),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            elevation: 0.5,
            bottom: tabs.length > 1
                ? TabBar(
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.muted,
                    indicatorColor: AppColors.primary,
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    tabs: [
                      for (final t in tabs)
                        Tab(
                          height: 44,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(t.icon, size: 16),
                              const SizedBox(width: 6),
                              Text(t.label),
                            ],
                          ),
                        ),
                    ],
                  )
                : null,
          ),
          body: TabBarView(
            children: [
              for (final t in tabs)
                _ClaimQueueList(settlement: t.settlement),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalTab {
  const _ApprovalTab({
    required this.label,
    required this.icon,
    required this.settlement,
  });
  final String label;
  final IconData icon;
  final bool settlement;
}

/// A pull-to-refresh list of claim summary cards backed by either the approval
/// inbox or the settlement queue.
class _ClaimQueueList extends ConsumerWidget {
  const _ClaimQueueList({required this.settlement});

  /// true → settlement queue (APPROVED claims); false → approval inbox.
  final bool settlement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        settlement ? travelSettlementQueueProvider : travelInboxProvider;
    final async = ref.watch(provider);
    final mq = MediaQuery.of(context);

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white,
      onRefresh: () async => ref.invalidate(provider),
      child: async.when(
        loading: () => ListView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.all(16),
          children: const [AppLoadingBlock(height: 160)],
        ),
        error: (e, _) => ListView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.all(16),
          children: [
            AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(provider),
            ),
          ],
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.all(16),
              children: [
                AppEmptyState(
                  icon: settlement
                      ? Icons.account_balance_wallet_outlined
                      : Icons.inbox_outlined,
                  message: settlement
                      ? 'No approved claims awaiting settlement.'
                      : 'Nothing pending your approval right now.',
                ),
              ],
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 20),
            itemCount: rows.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TravelClaimQueueCard(
                claim: rows[i],
                settlement: settlement,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compact claim row used in the approval inbox and settlement queue. Tapping
/// opens the review screen, which carries the role-aware action bar.
class TravelClaimQueueCard extends StatelessWidget {
  const TravelClaimQueueCard({
    super.key,
    required this.claim,
    this.settlement = false,
  });

  final TravelClaimSummary claim;
  final bool settlement;

  @override
  Widget build(BuildContext context) {
    final tone = travelClaimTone(claim.status);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: () => context.push('/travel/review/${claim.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    claim.title.isEmpty ? 'Travel claim' : claim.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 14, color: AppColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    claim.employeeName ?? 'Employee',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                if (claim.claimCode != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    claim.claimCode!,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  travelMoney(claim.totalClaimedAmount),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                if (claim.hasPolicyViolation)
                  const StatusPill(
                    label: 'Violation',
                    color: AppColors.danger,
                    icon: Icons.report_gmailerrorred_rounded,
                  )
                else if (!settlement && claim.currentLevel != null)
                  StatusPill(
                    label: 'Level ${claim.currentLevel}',
                    color: AppColors.info,
                  ),
              ],
            ),
            if (claim.submittedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Submitted ${travelDateTime(claim.submittedAt)}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
