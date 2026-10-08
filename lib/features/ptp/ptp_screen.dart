import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../tasks/task_detail_screen.dart';
import 'ptp_models.dart';
import 'ptp_providers.dart';

/// PTP follow-ups — every promise-to-pay customer the signed-in user has to
/// chase. Opened from the PTP push / in-app notification (route `/ptp`, with
/// an optional `?filter=DUE_TODAY` etc.) and from the menu. A field officer
/// sees their own customers; a branch manager sees the whole branch with the
/// officer on each card, because the server widens the scope for them.
class PtpScreen extends ConsumerStatefulWidget {
  const PtpScreen({super.key, this.initialFilter = PtpFilter.all});

  final PtpFilter initialFilter;

  @override
  ConsumerState<PtpScreen> createState() => _PtpScreenState();
}

class _PtpScreenState extends ConsumerState<PtpScreen> {
  late PtpFilter _filter = widget.initialFilter;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void didUpdateWidget(covariant PtpScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A second notification tap can re-target the same screen at another chip.
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 400) {
      // After a failed load-more, wait for the footer's retry — otherwise every
      // scroll tick near the bottom re-sends the failing request.
      if (ref.read(ptpListProvider(_filter)).moreError != null) return;
      ref.read(ptpListProvider(_filter).notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(ptpSummaryProvider);
    await Future.wait([
      ref.read(ptpListProvider(_filter).notifier).refresh(),
      ref.read(ptpSummaryProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  void _select(PtpFilter f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _openTask(CrmPtp p) async {
    final id = p.taskId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)),
    );
    // The visit may have closed or re-dated the follow-up task; show the
    // counts as they are now.
    if (mounted) _refresh();
  }

  Future<void> _call(String? number) async {
    final cleaned = number?.replaceAll(RegExp(r'[^0-9+#*]'), '') ?? '';
    if (cleaned.isEmpty) return;
    try {
      // Launched directly: canLaunchUrl reports false for tel: on Android
      // unless the DIAL intent is declared, even when a dialler exists.
      if (await launchUrl(Uri(scheme: 'tel', path: cleaned),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Could not open the dialler.')));
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(ptpSummaryProvider);
    final summary = summaryAsync.asData?.value;
    final list = ref.watch(ptpListProvider(_filter));
    final scope = summary?.scope ?? PtpScope.fo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PTP follow-ups'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white,
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _SummaryHero(
                summary: summary,
                loading: summaryAsync.isLoading && summary == null,
                selected: _filter,
                onSelect: _select,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: 16),
              sliver: SliverToBoxAdapter(
                child: ProChipBar(
                  labels: [for (final f in PtpFilter.values) f.label],
                  counts: summary == null
                      ? null
                      : [for (final f in PtpFilter.values) summary.countFor(f)],
                  selected: PtpFilter.values.indexOf(_filter),
                  onSelected: (i) => _select(PtpFilter.values[i]),
                ),
              ),
            ),
            ..._listSlivers(list, scope, summary),
          ],
        ),
      ),
    );
  }

  List<Widget> _listSlivers(PtpListState list, PtpScope scope, PtpSummary? summary) {
    const pad = EdgeInsets.fromLTRB(16, 14, 16, 0);
    if (list.loading && list.items.isEmpty) {
      return const [
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(child: AppLoadingBlock(height: 160)),
        ),
      ];
    }
    if (list.error != null && list.items.isEmpty) {
      return [
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(
            child: AppErrorPanel(
              message: list.error!,
              onRetry: () => ref.read(ptpListProvider(_filter).notifier).refresh(),
            ),
          ),
        ),
      ];
    }
    if (list.items.isEmpty) {
      final lines = _filter.emptyMessage.split('\n');
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          sliver: SliverToBoxAdapter(
            child: ProEmpty(
              icon: _filter == PtpFilter.kept
                  ? Icons.verified_rounded
                  : Icons.event_available_rounded,
              title: lines.first,
              message: lines.length > 1 ? lines.skip(1).join('\n') : null,
            ),
          ),
        ),
      ];
    }
    final count = summary?.countFor(_filter);
    return [
      // A refresh that failed with rows already on screen keeps the old rows
      // (better than a blank list) — but say so, or a card still reading
      // 'Due today' after the visit was marked done looks current.
      if (list.error != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Could not refresh — tap to retry'),
              ),
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: ProSectionHeader(
            title: count == null ? _filter.label : '${_filter.label} · $count',
            small: true,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: list.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final p = list.items[i];
            return _PtpCard(
              ptp: p,
              showOfficer: scope != PtpScope.fo,
              onTap: p.taskId == null ? null : () => _openTask(p),
              onCall: p.phone == null ? null : () => _call(p.phone),
            );
          },
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        sliver: SliverToBoxAdapter(child: _footer(list)),
      ),
    ];
  }

  Widget _footer(PtpListState list) {
    if (list.loadingMore) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (list.moreError != null) {
      return Center(
        child: TextButton.icon(
          onPressed: () => ref.read(ptpListProvider(_filter).notifier).loadMore(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Could not load more — tap to retry'),
        ),
      );
    }
    if (!list.last) {
      // Short first pages never scroll, so the listener alone would not fire.
      return Center(
        child: OutlinedButton(
          onPressed: () => ref.read(ptpListProvider(_filter).notifier).loadMore(),
          child: const Text('Load more'),
        ),
      );
    }
    return Center(
      child: Text(
        '${list.items.length} ${list.items.length == 1 ? 'customer' : 'customers'}',
        style: AppText.caption,
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

/// Deep hero: scope, today's count + EMI (tap = "Due today" filter) and the
/// other buckets as filter tiles.
class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.summary,
    required this.loading,
    required this.selected,
    required this.onSelect,
  });

  final PtpSummary? summary;
  final bool loading;
  final PtpFilter selected;
  final ValueChanged<PtpFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) {
      return ProHero(
        title: 'Promise-to-pay',
        subtitle: loading ? 'Loading your follow-ups…' : 'Pull down to refresh',
      );
    }
    ProStat stat(String label, int value, PtpFilter f, Color dot) => ProStat(
          label: label,
          value: '$value',
          dot: dot,
          selected: selected == f,
          onTap: () => onSelect(f),
        );
    return ProHero(
      titleWidget: _TapTitle(
        kicker: s.scope.label,
        title: '${s.dueToday} due today',
        subtitle: s.dueTodayAmount > 0
            ? 'EMI ${ptpRupees(s.dueTodayAmount)}'
            : null,
        onTap: () => onSelect(PtpFilter.dueToday),
      ),
      children: [
        ProHeroStats(stats: [
          stat('Tomorrow', s.dueTomorrow, PtpFilter.dueTomorrow, const Color(0xFF9DB9F0)),
          stat('Broken', s.broken, PtpFilter.broken, const Color(0xFFE5484D)),
          stat('Upcoming', s.upcoming, PtpFilter.upcoming, const Color(0xFF5FC3D6)),
          stat('Kept (30d)', s.kept, PtpFilter.kept, AppColors.live),
        ]),
      ],
    );
  }
}

/// Hero title block (same type as [ProHero]'s) that is tappable.
class _TapTitle extends StatelessWidget {
  const _TapTitle({
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String kicker;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kicker,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.65,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 22),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.white70,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Card ────────────────────────────────────────────────────────────────────

Color _tint(Color c) {
  if (c == AppColors.success) return AppColors.successTint;
  if (c == AppColors.warning) return AppColors.warningTint;
  if (c == AppColors.danger) return AppColors.dangerTint;
  if (c == AppColors.info || c == AppColors.accent) return AppColors.infoTint;
  if (c == AppColors.muted) return AppColors.neutralTint;
  return c.withValues(alpha: 0.12);
}

Color _ink(Color c) {
  if (c == AppColors.warning) return const Color(0xFF9A5B00);
  if (c == AppColors.muted) return const Color(0xFF43585D);
  return c;
}

class _PtpCard extends StatelessWidget {
  const _PtpCard({
    required this.ptp,
    required this.showOfficer,
    this.onTap,
    this.onCall,
  });

  final CrmPtp ptp;
  final bool showOfficer;
  final VoidCallback? onTap;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final p = ptp;
    final badge = ptpBadge(p);
    final branch = ptpBranchLabel(p.branchName);
    final officer = showOfficer ? p.officerLabel : null;
    final amount = p.amount;
    final promised = p.promisedDate;

    return GlassCard(
      padding: EdgeInsets.zero,
      border: p.status == 'BROKEN'
          ? Border.all(color: AppColors.danger.withValues(alpha: 0.35))
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProAvatar(name: p.customerName, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              p.customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.33,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.15,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          if (amount != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              'EMI ${ptpRupees(amount)}',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (branch != null || officer != null || p.reference != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (branch != null)
                                _Meta(icon: Icons.storefront_rounded, text: branch),
                              if (officer != null)
                                _Meta(icon: Icons.badge_rounded, text: officer),
                              if (p.reference != null)
                                _Meta(icon: Icons.tag_rounded, text: p.reference!),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ProPill(badge.label,
                              color: _ink(badge.color),
                              background: _tint(badge.color),
                              dot: true),
                          if (promised != null)
                            ProPill.neutral(ptpPromisedLabel(promised)),
                          if (p.rescheduleCount > 0)
                            ProPill.warn('Re-dated ${p.rescheduleCount}×'),
                          if (p.module != null) ProPill.info(p.module!.toUpperCase()),
                        ],
                      ),
                      if (p.callNote != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          p.callNote!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onCall != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Call ${p.customerName}',
                    onPressed: onCall,
                    icon: const Icon(Icons.call_rounded, size: 20),
                    color: AppColors.success,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.successTint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.faint),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
