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

final myTravelClaimsProvider =
    FutureProvider.autoDispose<List<TravelClaimSummary>>((ref) {
  return ref.watch(travelRepositoryProvider).myClaims(size: 100);
});

/// Rounded rupee amount for the hero totals ("₹ 45,070").
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

/// Hero quick-filter groups (they narrow the list already in memory).
enum _ClaimGroup { needs, approval, done }

bool _inGroup(_ClaimGroup g, String status) {
  switch (g) {
    case _ClaimGroup.needs:
      return status == 'DRAFT' || status == 'SENT_BACK';
    case _ClaimGroup.approval:
      return status == 'SUBMITTED' || status.startsWith('LEVEL_');
    case _ClaimGroup.done:
      return status == 'APPROVED' || status == 'SETTLED';
  }
}

/// Employee "My travel claims": status-badged list with create + drill-in.
class TravelClaimsScreen extends ConsumerStatefulWidget {
  const TravelClaimsScreen({super.key});

  @override
  ConsumerState<TravelClaimsScreen> createState() => _TravelClaimsScreenState();
}

class _TravelClaimsScreenState extends ConsumerState<TravelClaimsScreen> {
  String _status = '';
  _ClaimGroup? _group;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<TravelClaimSummary> _filter(List<TravelClaimSummary> rows) {
    final term = _q.text.trim().toLowerCase();
    return rows.where((r) {
      if (_status.isNotEmpty && r.status != _status) return false;
      if (_group != null && !_inGroup(_group!, r.status)) return false;
      if (term.isEmpty) return true;
      return r.title.toLowerCase().contains(term) ||
          (r.claimCode ?? '').toLowerCase().contains(term);
    }).toList();
  }

  Future<void> _create() async {
    final created = await context.push<bool>('/travel/claims/new');
    if (created == true) ref.invalidate(myTravelClaimsProvider);
  }

  double _sum(Iterable<TravelClaimSummary> rows) =>
      rows.fold<double>(0, (a, c) => a + (c.totalClaimedAmount ?? 0));

  String _plural(int n) => '$n ${n == 1 ? 'claim' : 'claims'}';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myTravelClaimsProvider);
    final all = async.asData?.value ?? const <TravelClaimSummary>[];

    final submitted = all.where((c) => c.status != 'DRAFT').toList();
    Iterable<TravelClaimSummary> group(_ClaimGroup g) =>
        all.where((c) => _inGroup(g, c.status));
    final settled = _sum(all.where((c) => c.status == 'SETTLED'));

    ProStat stat(_ClaimGroup g, String label, Color dot, String sub) => ProStat(
          label: label,
          value: _inr0.format(_sum(group(g))),
          sub: sub,
          dot: dot,
          selected: _group == g,
          onTap: () => setState(() {
            _group = _group == g ? null : g;
            _status = '';
          }),
        );

    const statuses = TravelEnums.claimStatuses;
    final chipIndex = _group != null
        ? -1
        : (_status.isEmpty ? 0 : statuses.indexOf(_status) + 1);

    final shown = _filter(all);
    final listTitle = _group != null
        ? const {
            _ClaimGroup.needs: 'Needs you',
            _ClaimGroup.approval: 'In approval',
            _ClaimGroup.done: 'Approved',
          }[_group]!
        : (_status.isEmpty ? 'All claims' : claimStatusTone(_status).label);
    final term = _q.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Travel claims')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Raise claim'),
      ),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myTravelClaimsProvider),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        hero: ProHero(
          title: 'My travel claims',
          subtitle: async.hasValue
              ? '${_inr0.format(_sum(submitted))} claimed · ${submitted.length} submitted'
              : null,
          overlap: ProSearchField(
            raised: true,
            controller: _q,
            onChanged: (_) => setState(() {}),
            hint: 'Trip name or claim code',
          ),
          children: [
            ProHeroStats(stats: [
              stat(_ClaimGroup.needs, 'Needs you', const Color(0xFFF2B347),
                  _plural(group(_ClaimGroup.needs).length)),
              stat(_ClaimGroup.approval, 'In approval', const Color(0xFF7FB0EC),
                  _plural(group(_ClaimGroup.approval).length)),
              stat(_ClaimGroup.done, 'Approved', AppColors.live,
                  '${_inr0.format(settled)} settled'),
            ]),
          ],
        ),
        children: [
          ProChipBar(
            labels: [
              'All',
              for (final s in statuses) claimStatusTone(s).label,
            ],
            counts: [
              all.length,
              for (final s in statuses) all.where((c) => c.status == s).length,
            ],
            selected: chipIndex,
            onSelected: (i) => setState(() {
              _group = null;
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
                  icon: Icons.receipt_long_rounded,
                  title: term.isNotEmpty
                      ? 'No claims match “$term”'
                      : (_status.isNotEmpty || _group != null
                          ? 'No claims in this filter'
                          : 'No travel claims yet'),
                  message: term.isNotEmpty
                      ? 'Search by trip name or claim code.'
                      : 'Tap "Raise claim" to submit your expenses.',
                  action: term.isEmpty && _status.isEmpty && _group == null
                      ? FilledButton.icon(
                          onPressed: _create,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Raise claim'),
                        )
                      : null,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title: '$listTitle · ${shown.length}',
                    small: true,
                    trailing: Text(
                      _inr0.format(_sum(shown)),
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
                      for (final c in shown)
                        _ClaimRow(
                          claim: c,
                          onTap: () async {
                            await context.push('/travel/claims/${c.id}');
                            ref.invalidate(myTravelClaimsProvider);
                          },
                        ),
                    ],
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
    );
  }
}

/// One claim in the grouped list: status-tinted icon, title, code + submitted
/// time, optional policy flag, amount and status pill.
class _ClaimRow extends StatelessWidget {
  const _ClaimRow({required this.claim, required this.onTap});
  final TravelClaimSummary claim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = claimStatusTone(claim.status);
    final sub = [
      if (claim.claimCode != null && claim.claimCode!.isNotEmpty) claim.claimCode!,
      if (claim.submittedAt != null)
        'Submitted ${DateFormat('d MMM yyyy, h:mm a').format(claim.submittedAt!)}',
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              ProIconWell(icon: Icons.receipt_long_rounded, color: tone.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      claim.title,
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
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (claim.hasPolicyViolation)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 13, color: AppColors.danger),
                            SizedBox(width: 4),
                            Text(
                              'Policy flag',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
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
                    money(claim.totalClaimedAmount),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  ProPill(tone.label, color: tone.color),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFB3C0C3)),
            ],
          ),
        ),
      ),
    );
  }
}
