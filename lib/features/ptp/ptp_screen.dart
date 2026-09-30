import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          title: const Text('PTP Follow-ups'),
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
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: _SummaryHeader(
                    summary: summary,
                    loading: summaryAsync.isLoading && summary == null,
                    onTapDueToday: () => _select(PtpFilter.dueToday),
                    onTapBroken: () => _select(PtpFilter.broken),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _FilterChips(
                  selected: _filter,
                  summary: summary,
                  onSelected: _select,
                ),
              ),
              ..._listSlivers(list, scope),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _listSlivers(PtpListState list, PtpScope scope) {
    const pad = EdgeInsets.fromLTRB(16, 8, 16, 0);
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
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          sliver: SliverToBoxAdapter(
            child: AppEmptyState(
              icon: _filter == PtpFilter.kept
                  ? Icons.verified_rounded
                  : Icons.event_available_rounded,
              message: _filter.emptyMessage,
            ),
          ),
        ),
      ];
    }
    return [
      // A refresh that failed with rows already on screen keeps the old rows
      // (better than a blank list) — but say so, or a card still reading
      // 'Due today' after the visit was marked done looks current.
      if (list.error != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
        child: TextButton(
          onPressed: () => ref.read(ptpListProvider(_filter).notifier).loadMore(),
          child: const Text('Load more'),
        ),
      );
    }
    return Center(
      child: Text(
        '${list.items.length} ${list.items.length == 1 ? 'customer' : 'customers'}',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.summary,
    required this.loading,
    required this.onTapDueToday,
    required this.onTapBroken,
  });

  final PtpSummary? summary;
  final bool loading;
  final VoidCallback onTapDueToday;
  final VoidCallback onTapBroken;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) {
      return loading ? const AppLoadingBlock(height: 112) : const SizedBox.shrink();
    }
    const onHero = TextStyle(color: Colors.white);
    return GlassCard(
      gradient: AppColors.heroGradient,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      shadow: AppShadows.lifted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.scope.label.toUpperCase(),
            style: onHero.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onTapDueToday,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${s.dueToday}',
                  style: onHero.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.dueTodayAmount > 0
                        ? 'due today · EMI ${ptpRupees(s.dueTodayAmount)}'
                        : 'due today',
                    style: onHero.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _HeroStat(label: 'Tomorrow', value: s.dueTomorrow),
              _HeroStat(label: 'Broken', value: s.broken, onTap: onTapBroken),
              _HeroStat(label: 'Upcoming', value: s.upcoming),
              _HeroStat(label: 'Kept (30d)', value: s.kept),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, this.onTap});
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.summary,
    required this.onSelected,
  });

  final PtpFilter selected;
  final PtpSummary? summary;
  final ValueChanged<PtpFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: PtpFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = PtpFilter.values[i];
          final on = f == selected;
          final count = summary?.countFor(f);
          return ChoiceChip(
            selected: on,
            showCheckmark: false,
            onSelected: (_) => onSelected(f),
            label: Text(count == null ? f.label : '${f.label} · $count'),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: on
                  ? Colors.white
                  : (f == PtpFilter.broken && (count ?? 0) > 0
                      ? AppColors.danger
                      : AppColors.inkSoft),
            ),
            selectedColor: f == PtpFilter.broken ? AppColors.danger : AppColors.primary,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: on ? Colors.transparent : AppColors.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          );
        },
      ),
    );
  }
}

// ── Card ────────────────────────────────────────────────────────────────────

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
      shadow: AppShadows.soft,
      border: p.status == 'BROKEN'
          ? Border.all(color: AppColors.danger.withValues(alpha: 0.35))
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(label: badge.label, color: badge.color),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (amount != null)
                            Text(
                              'EMI ${ptpRupees(amount)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          if (promised != null)
                            Text(
                              ptpPromisedLabel(promised),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          if (p.rescheduleCount > 0)
                            Text(
                              'Re-dated ${p.rescheduleCount}×',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (p.module != null) _ModuleChip(p.module!),
                          if (branch != null)
                            _Meta(icon: Icons.storefront_rounded, text: branch),
                          if (officer != null)
                            _Meta(icon: Icons.badge_rounded, text: officer),
                          if (p.reference != null)
                            _Meta(icon: Icons.tag_rounded, text: p.reference!),
                        ],
                      ),
                      if (p.callNote != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          p.callNote!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onCall != null)
                  IconButton(
                    tooltip: 'Call ${p.customerName}',
                    onPressed: onCall,
                    icon: const Icon(Icons.call_rounded),
                    color: AppColors.success,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.success.withValues(alpha: 0.12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleChip extends StatelessWidget {
  const _ModuleChip(this.module);
  final String module;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        module.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppColors.accent,
          letterSpacing: 0.3,
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
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}
