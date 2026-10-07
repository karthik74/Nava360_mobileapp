import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'travel_claim_review_screen.dart';
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
      return StatusTone(AppColors.primary, 'Settled');
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

class TravelApprovalsScreen extends ConsumerStatefulWidget {
  const TravelApprovalsScreen({super.key});

  @override
  ConsumerState<TravelApprovalsScreen> createState() => _TravelApprovalsScreenState();
}

class _TravelApprovalsScreenState extends ConsumerState<TravelApprovalsScreen> {
  int _tab = 0;

  double _sum(List<TravelClaimSummary> rows) =>
      rows.fold<double>(0, (a, c) => a + (c.totalClaimedAmount ?? 0));

  String _plural(int n) => '$n ${n == 1 ? 'claim' : 'claims'}';

  @override
  Widget build(BuildContext context) {
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
    if (_tab >= tabs.length) _tab = 0;
    final current = tabs[_tab];
    final hasInbox = tabs.any((t) => !t.settlement);

    final inbox = hasInbox
        ? ref.watch(travelInboxProvider).asData?.value
        : null;
    final settle = canSettle
        ? ref.watch(travelSettlementQueueProvider).asData?.value
        : null;

    int? countOf(_ApprovalTab t) => (t.settlement ? settle : inbox)?.length;

    final stats = <ProStat>[
      if (hasInbox) ...[
        ProStat(
          label: 'Waiting on you',
          value: inbox == null ? '—' : travelMoney(_sum(inbox)),
          sub: inbox == null ? null : _plural(inbox.length),
          dot: const Color(0xFFF2B347),
        ),
        ProStat(
          label: 'With violation',
          value: inbox == null ? '—' : '${inbox.where((c) => c.hasPolicyViolation).length}',
          sub: 'policy flags',
          dot: const Color(0xFFE5484D),
        ),
      ],
      if (canSettle)
        ProStat(
          label: 'To settle',
          value: settle == null ? '—' : travelMoney(_sum(settle)),
          sub: settle == null ? null : _plural(settle.length),
          dot: AppColors.live,
        ),
    ];

    final provider =
        current.settlement ? travelSettlementQueueProvider : travelInboxProvider;

    return Scaffold(
      appBar: AppBar(title: const Text('Travel approvals')),
      body: ProPage(
        onRefresh: () async => ref.invalidate(provider),
        hero: ProHero(
          title: 'Travel approvals',
          subtitle: hasInbox
              ? (inbox == null ? null : '${_plural(inbox.length)} waiting from your team')
              : (settle == null ? null : '${_plural(settle.length)} awaiting settlement'),
          children: [
            if (tabs.length > 1)
              ProHeroSegmented(
                labels: [
                  for (final t in tabs)
                    countOf(t) == null ? t.label : '${t.label} · ${countOf(t)}',
                ],
                icons: [for (final t in tabs) t.icon],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ProHeroStats(stats: stats),
          ],
        ),
        children: [
          _ClaimQueueList(settlement: current.settlement),
        ],
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

/// The claim summaries backed by either the approval inbox or the settlement
/// queue (laid out inside the page's scroll view; the page refreshes it).
class _ClaimQueueList extends ConsumerWidget {
  const _ClaimQueueList({required this.settlement});

  /// true → settlement queue (APPROVED claims); false → approval inbox.
  final bool settlement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        settlement ? travelSettlementQueueProvider : travelInboxProvider;
    final async = ref.watch(provider);

    return async.when(
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(provider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return ProEmpty(
            icon: settlement
                ? Icons.account_balance_wallet_outlined
                : Icons.inbox_outlined,
            title: settlement ? 'Nothing to settle' : 'All caught up',
            message: settlement
                ? 'No approved claims awaiting settlement.'
                : 'Nothing pending your approval right now.',
          );
        }
        final total = rows.fold<double>(0, (a, c) => a + (c.totalClaimedAmount ?? 0));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(
              title: '${settlement ? 'To settle' : 'My inbox'} · ${rows.length}',
              small: true,
              trailing: Text(
                travelMoney(total),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (!settlement) ...[
              const ProSwipeHint(),
              const SizedBox(height: 10),
            ],
            for (final c in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: settlement
                    ? TravelClaimQueueCard(claim: c, settlement: true)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        child: ProSwipeDecision(
                          onApprove: () =>
                              travelQuickDecision(context, ref, c.id, approve: true),
                          onReject: () =>
                              travelQuickDecision(context, ref, c.id, approve: false),
                          child: TravelClaimQueueCard(
                            claim: c,
                            onApprove: () =>
                                travelQuickDecision(context, ref, c.id, approve: true),
                            onReject: () =>
                                travelQuickDecision(context, ref, c.id, approve: false),
                          ),
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }
}

/// Compact claim row used in the approval inbox and settlement queue. Tapping
/// opens the review screen, which carries the role-aware action bar. With
/// [onApprove] / [onReject] it also shows quick decision buttons.
class TravelClaimQueueCard extends StatelessWidget {
  const TravelClaimQueueCard({
    super.key,
    required this.claim,
    this.settlement = false,
    this.onApprove,
    this.onReject,
  });

  final TravelClaimSummary claim;
  final bool settlement;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final tone = travelClaimTone(claim.status);
    final name = claim.employeeName ?? 'Employee';
    final hasActions = onApprove != null || onReject != null;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/travel/review/${claim.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProAvatar(name: name, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            claim.title.isEmpty ? 'Travel claim' : claim.title,
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
                          Text(
                            [name, if (claim.claimCode != null) claim.claimCode!]
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                          if (claim.submittedAt != null)
                            Text(
                              'Submitted ${travelDateTime(claim.submittedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: AppColors.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          travelMoney(claim.totalClaimedAmount),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (claim.hasPolicyViolation)
                          ProPill.bad('Violation')
                        else if (!settlement && claim.currentLevel != null)
                          ProPill.info('Level ${claim.currentLevel}')
                        else
                          ProPill(tone.label, color: tone.color),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasActions) ...[
            const Divider(height: 1, color: AppColors.hairlineSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  if (onReject != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onReject,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.dangerTint,
                          foregroundColor: AppColors.danger,
                          minimumSize: const Size(0, 42),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 17),
                        label: const Text('Reject'),
                      ),
                    ),
                  if (onReject != null && onApprove != null) const SizedBox(width: 10),
                  if (onApprove != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onApprove,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                        icon: const Icon(Icons.check_rounded, size: 17),
                        label: const Text('Approve'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
