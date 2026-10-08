// ─────────────────────────────────────────────────────────────────────────────
//  FTOD collections — the field officer's / branch manager's month view of
//  first-time-overdue EMIs.
//
//  The heart of the screen is the date-wise distribution: for every due date,
//  the days money actually came in ("Due 01 Sep" → collected 01 Sep, 04 Sep,
//  05 Sep). Customers due on the 1st routinely pay on the 4th or 5th and some
//  pay only part, so a paid/unpaid count alone hides where the follow-up
//  effort went. Tapping a due date narrows the customer list below to it.
//
//  Opened from the FTOD push / in-app notification (route "/ftod"). Scope —
//  own customers, branch, or everything — is decided by the server.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'ftod_models.dart';
import 'ftod_repository.dart';

/// Customers fetched per page of GET /api/ftod/mine.
const int _pageSize = 50;

/// The theme has no orange token; partial sits between late (amber) and
/// pending (red), so it gets Tailwind orange-600 to stay distinguishable.
const Color _partialOrange = Color(0xFFEA580C);

Color ftodStatusColor(FtodStatus s) {
  switch (s) {
    case FtodStatus.paidOnTime:
      return AppColors.success;
    case FtodStatus.paidLate:
      return AppColors.warning;
    case FtodStatus.partial:
      return _partialOrange;
    case FtodStatus.pending:
      return AppColors.danger;
  }
}

/// Bar / legend order: good news first, reading left to right towards what
/// still needs chasing.
const List<FtodStatus> _barOrder = [
  FtodStatus.paidOnTime,
  FtodStatus.paidLate,
  FtodStatus.partial,
  FtodStatus.pending,
];

/// Filter chip order — what needs action first.
const List<FtodStatus> _chipOrder = [
  FtodStatus.pending,
  FtodStatus.partial,
  FtodStatus.paidLate,
  FtodStatus.paidOnTime,
];

String _scopeLabel(String scope) {
  switch (scope) {
    case 'BRANCH':
      return 'Your branch';
    case 'ALL':
      return 'All branches';
    default:
      return 'Your customers';
  }
}

class FtodScreen extends ConsumerStatefulWidget {
  const FtodScreen({super.key, this.initialMonth});

  /// Optional "YYYY-MM" to open on; defaults to the current month.
  final String? initialMonth;

  @override
  ConsumerState<FtodScreen> createState() => _FtodScreenState();
}

class _FtodScreenState extends ConsumerState<FtodScreen> {
  late DateTime _month;
  DateTime? _dueDate;
  FtodStatus? _status;

  List<FtodDue> _items = const [];
  int _page = 0;
  bool _last = true;
  bool _loadingList = true;
  bool _loadingMore = false;
  // A failed load-more waits for an explicit retry: without this, every scroll
  // frame near the bottom re-fired the request (and another snackbar) offline.
  bool _moreFailed = false;
  Object? _listError;

  /// Bumped on every first-page load so a slow response for an old filter
  /// can't overwrite the list for the filter the user has since picked.
  int _gen = 0;

  final GlobalKey _customersKey = GlobalKey();

  String get _monthKey => ftodMonthKey(_month);

  DateTime get _thisMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  @override
  void initState() {
    super.initState();
    _month = _parseMonth(widget.initialMonth) ?? _thisMonth;
    _fetchFirstPage();
  }

  static DateTime? _parseMonth(String? key) {
    final d = key == null ? null : DateTime.tryParse('$key-01');
    return d == null ? null : DateTime(d.year, d.month, 1);
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _fetchFirstPage() async {
    final gen = ++_gen;
    try {
      final p = await ref.read(ftodRepositoryProvider).dues(
            month: _monthKey,
            dueDate: _dueDate,
            status: _status,
            page: 0,
            size: _pageSize,
          );
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = p.items;
        _page = 0;
        _last = p.last;
        _loadingList = false;
        _loadingMore = false;
        _listError = null;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _listError = e;
        _loadingList = false;
        _loadingMore = false;
      });
    }
  }

  /// Filter/month change: clear the list so stale rows never show under the
  /// new filter. Pull-to-refresh passes clear=false to avoid a flash.
  Future<void> _reloadList({bool clear = true}) {
    setState(() {
      _loadingList = true;
      _loadingMore = false;
      _moreFailed = false;
      _listError = null;
      if (clear) {
        _items = const [];
        _last = true;
      }
    });
    return _fetchFirstPage();
  }

  Future<void> _loadMore({bool retry = false}) async {
    if (_moreFailed && !retry) return;
    if (_loadingMore || _loadingList || _last || _listError != null) return;
    final gen = _gen;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final p = await ref.read(ftodRepositoryProvider).dues(
            month: _monthKey,
            dueDate: _dueDate,
            status: _status,
            page: _page + 1,
            size: _pageSize,
          );
      if (!mounted || gen != _gen) return;
      setState(() {
        // Rows are ordered by status and an import can move one to a later
        // page between fetches — drop repeats rather than show a customer twice.
        final seen = _items.map((e) => e.id).toSet();
        _items = [..._items, ...p.items.where((e) => seen.add(e.id))];
        _page = _page + 1;
        _last = p.last || p.items.isEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
      _toast('Could not load more customers: $e');
    }
  }

  Future<void> _refresh() async {
    final key = _monthKey;
    await Future.wait<void>([
      // The error (if any) is rendered by the distribution section itself.
      ref
          .refresh(ftodDistributionProvider(key).future)
          .then((_) {}, onError: (_) {}),
      _reloadList(clear: false),
    ]);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _shiftMonth(int delta) {
    setState(() {
      _month = ftodShiftMonth(_month, delta);
      // A due date belongs to one month; the status filter carries over.
      _dueDate = null;
    });
    _reloadList();
  }

  void _selectDueDate(DateTime? d) {
    setState(() => _dueDate = (d == null || d == _dueDate) ? null : d);
    _reloadList();
    if (_dueDate != null) {
      // Bring the narrowed list into view — with a month of due dates the
      // customers can sit a few screens below the card that was tapped.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _customersKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  void _selectStatus(FtodStatus? s) {
    if (s == _status) return;
    setState(() => _status = s);
    _reloadList();
  }

  Future<void> _call(FtodDue due) async {
    final cleaned = (due.phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return;
    try {
      // Launched directly: canLaunchUrl reports false for tel: on Android
      // unless the DIAL intent is declared, even when a dialler exists.
      final ok = await launchUrl(
        Uri(scheme: 'tel', path: cleaned),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _toast('Could not open the dialler.');
    } catch (_) {
      _toast('Could not open the dialler.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final distAsync = ref.watch(ftodDistributionProvider(_monthKey));
    final dist = distAsync.valueOrNull;
    final today = DateTime.now();
    final noDues = dist != null && dist.totals.customers == 0 && dist.days.isEmpty;
    final totals = (dist != null && !noDues) ? dist.totals : null;

    final header = <Widget>[
      ...distAsync.when(
        loading: () => const [AppLoadingBlock(height: 150)],
        error: (e, _) => [
          AppErrorPanel(
            message: 'Could not load FTOD collections: $e',
            onRetry: () => ref.invalidate(ftodDistributionProvider(_monthKey)),
          ),
        ],
        data: (d) => noDues
            ? [
                ProEmpty(
                  icon: Icons.event_available_rounded,
                  title: 'No FTOD dues for ${ftodMonthLabel(_month)}.',
                  message: 'Dues show up here once they are imported for the month.',
                ),
              ]
            : _distributionSection(d),
      ),
    ];

    // The customer list is fetched on its own, so a failed distribution (the
    // heavier month aggregate) must not hide customers the officer has to call.
    final showList = !noDues;
    final counts = dist?.dayFor(_dueDate)?.counts ?? dist?.totals.counts;

    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white,
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // Only the page scroll pages the list — the horizontal chip rows
            // report their own scroll notifications through here too.
            if (n.depth == 0 &&
                n.metrics.axis == Axis.vertical &&
                n.metrics.extentAfter < 400) {
              _loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: ProHero(
                  title: 'FTOD collections',
                  subtitle: dist == null
                      ? 'First-time overdue EMIs'
                      : 'First-time overdue EMIs · ${_scopeLabel(dist.scope)}',
                  overlap: totals != null ? _totalsStrip(totals) : null,
                  children: [
                    _HeroMonthSwitcher(
                      label: ftodMonthLabel(_month),
                      onPrev: () => _shiftMonth(-1),
                      // Dues can be imported a month ahead; nothing exists beyond that.
                      onNext: _month.isBefore(ftodShiftMonth(_thisMonth, 1))
                          ? () => _shiftMonth(1)
                          : null,
                    ),
                    if (totals != null) _HeroStatusMix(counts: totals.counts),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverList(delegate: SliverChildListDelegate(header)),
              ),
              if (showList) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _customersHeader(counts),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: _customerList(dist, today),
                ),
                SliverToBoxAdapter(child: _listFooter()),
              ],
              SliverToBoxAdapter(
                child: SizedBox(height: mq.padding.bottom + 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Month totals straddling the hero: customers, EMI due, collected.
  Widget _totalsStrip(FtodTotals totals) {
    return ProKpiStrip(cells: [
      ProKpi(value: ftodCount(totals.customers), label: 'Customers'),
      ProKpi(value: ftodRupees(totals.dueAmount), label: 'EMI due'),
      ProKpi(
        value: ftodRupees(totals.collectedAmount),
        label: 'Collected · ${totals.collectedPercent}%',
        progress: totals.collectedPercent / 100,
        color: AppColors.success,
      ),
    ]);
  }

  List<Widget> _distributionSection(FtodDistribution d) {
    return [
      if (d.days.isNotEmpty) ...[
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(
                title: 'Date-wise distribution',
                subtitle: 'When each due date\'s money came in · tap to see customers',
              ),
              const SizedBox(height: 14),
              _DueChart(
                days: d.days,
                selected: _dueDate,
                onTap: (day) => _selectDueDate(day),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bars show customers by status; the figure above each is money collected.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const ProSectionHeader(title: 'By due date', small: true),
        const SizedBox(height: 8),
      ],
      for (final day in d.days) ...[
        _DueDayCard(
          day: day,
          selected: _dueDate != null && day.dueDate == _dueDate,
          onTap: () => _selectDueDate(day.dueDate),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _customersHeader(FtodStatusCounts? counts) {
    final all = counts?.total;
    return Column(
      key: _customersKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(
          title: 'Customers',
          subtitle: _dueDate == null
              ? 'All due dates this month'
              : 'Due ${ftodDay(_dueDate)}',
        ),
        if (_dueDate != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Due ${ftodDay(_dueDate)}'),
              avatar: const Icon(Icons.event_rounded, size: 16),
              onDeleted: () => _selectDueDate(null),
              deleteButtonTooltipMessage: 'Show all due dates',
            ),
          ),
        ],
        const SizedBox(height: 10),
        ProChipBar(
          labels: ['All', for (final s in _chipOrder) s.label],
          counts: all == null ? null : [all, for (final s in _chipOrder) counts!.of(s)],
          selected: _status == null ? 0 : _chipOrder.indexOf(_status!) + 1,
          onSelected: (i) => _selectStatus(i == 0 ? null : _chipOrder[i - 1]),
          bleed: 0,
        ),
      ],
    );
  }

  Widget _customerList(FtodDistribution? dist, DateTime today) {
    if (_items.isEmpty) {
      final Widget child;
      if (_loadingList) {
        child = const AppLoadingBlock(height: 120);
      } else if (_listError != null) {
        child = AppErrorPanel(
          message: 'Could not load customers: $_listError',
          onRetry: _reloadList,
        );
      } else {
        child = const ProEmpty(
          icon: Icons.people_outline_rounded,
          title: 'No customers match this filter.',
          message: 'Pick another status or due date.',
        );
      }
      return SliverToBoxAdapter(child: child);
    }
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      sliver: SliverList.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          thickness: 1,
          indent: 64,
          color: AppColors.hairlineSoft,
        ),
        itemBuilder: (_, i) => _DueTile(
          due: _items[i],
          today: today,
          // Unknown scope (distribution failed): naming the officer is harmless.
          showOfficer: dist?.showsOfficer ?? true,
          onCall: () => _call(_items[i]),
        ),
      ),
    );
  }

  Widget _listFooter() {
    Widget? child;
    if (_loadingMore || (_loadingList && _items.isNotEmpty)) {
      child = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    } else if (_listError != null && _items.isNotEmpty) {
      child = TextButton.icon(
        onPressed: _reloadList,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Could not refresh — retry'),
      );
    } else if (_moreFailed) {
      child = TextButton.icon(
        onPressed: () => _loadMore(retry: true),
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Could not load more — retry'),
      );
    } else if (!_last) {
      child = OutlinedButton(
        onPressed: _loadMore,
        child: const Text('Load more'),
      );
    } else if (_items.length > 3) {
      child = Text(
        'All ${ftodCount(_items.length)} customers shown',
        style: AppText.caption,
      );
    }
    if (child == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Center(child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Status colours tuned for the deep hero (the light-surface ones are too
/// dark there): lime / amber / orange / red.
Color _onDeep(FtodStatus s) {
  switch (s) {
    case FtodStatus.paidOnTime:
      return AppColors.live;
    case FtodStatus.paidLate:
      return const Color(0xFFF2B347);
    case FtodStatus.partial:
      return const Color(0xFFFF8A4C);
    case FtodStatus.pending:
      return const Color(0xFFE5484D);
  }
}

/// Status as a tinted Pro pill.
Widget _statusPill(FtodStatus s, String label) {
  switch (s) {
    case FtodStatus.paidOnTime:
      return ProPill.ok(label);
    case FtodStatus.paidLate:
      return ProPill.warn(label);
    case FtodStatus.partial:
      return ProPill(label, color: const Color(0xFFC2410C), background: const Color(0xFFFDEADF));
    case FtodStatus.pending:
      return ProPill.bad(label);
  }
}

/// Previous / next month on the deep hero.
class _HeroMonthSwitcher extends StatelessWidget {
  const _HeroMonthSwitcher({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          ProHeroIconButton(
            icon: Icons.chevron_left_rounded,
            iconSize: 24,
            tooltip: 'Previous month',
            onTap: onPrev,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Opacity(
            opacity: onNext == null ? 0.35 : 1,
            child: ProHeroIconButton(
              icon: Icons.chevron_right_rounded,
              iconSize: 24,
              tooltip: 'Next month',
              onTap: onNext,
            ),
          ),
        ],
      ),
    );
  }
}

/// On time / late / partial / pending mix for the month, on the deep hero.
class _HeroStatusMix extends StatelessWidget {
  const _HeroStatusMix({required this.counts});
  final FtodStatusCounts counts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (counts.total == 0)
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          )
        else
          ProStackBar(parts: [
            for (final s in _barOrder) MapEntry(counts.of(s).toDouble(), _onDeep(s)),
          ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final s in _barOrder)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: _onDeep(s), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${s.label} ',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  Text(
                    ftodCount(counts.of(s)),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Stacked On time / Late / Partial / Pending bar sized by customer count.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.counts, this.height = 8});
  final FtodStatusCounts counts;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (counts.total == 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.hairlineSoft,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }
    return ProStackBar(
      height: height,
      parts: [
        for (final s in _barOrder) MapEntry(counts.of(s).toDouble(), ftodStatusColor(s)),
      ],
    );
  }
}

/// Column chart: one stacked bar per due date (customers by status) with the
/// collected % above it. Tapping a column narrows the customers below.
class _DueChart extends StatelessWidget {
  const _DueChart({required this.days, required this.selected, required this.onTap});
  final List<FtodDueDay> days;
  final DateTime? selected;
  final ValueChanged<DateTime?> onTap;

  static const double _barMax = 96;

  @override
  Widget build(BuildContext context) {
    final maxCount = days.fold<int>(0, (m, d) => math.max(m, d.counts.total));
    return SizedBox(
      height: _barMax + 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final day = days[i];
          final on = selected != null && day.dueDate == selected;
          final total = day.counts.total;
          final h = maxCount == 0 ? 0.0 : _barMax * total / maxCount;
          return Semantics(
            button: true,
            selected: on,
            label: '${day.headline()}, ${day.collectedPercent}% collected',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(day.dueDate),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: on ? AppColors.surfaceAlt : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: on ? AppColors.primary : Colors.transparent, width: 1.4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${day.collectedPercent}%',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: _barMax,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: math.max(h, 4)),
                          duration: Duration(milliseconds: 600 + i * 40),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 22,
                              height: v,
                              child: total == 0
                                  ? const ColoredBox(color: AppColors.hairline)
                                  : Column(
                                      children: [
                                        for (final s in _barOrder.reversed)
                                          if (day.counts.of(s) > 0)
                                            Expanded(
                                              flex: day.counts.of(s),
                                              child: ColoredBox(color: ftodStatusColor(s)),
                                            ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ftodDay(day.dueDate),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ftodCount(total),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One due date: headline, collected %, status mix and the "Collected on"
/// day chips that show customers due on the 1st paying on the 4th/5th.
class _DueDayCard extends StatelessWidget {
  const _DueDayCard({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final FtodDueDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final late = day.lateAmount;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        day.headline(),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.filter_alt_rounded
                          : Icons.chevron_right_rounded,
                      size: 19,
                      color: selected ? AppColors.primary : const Color(0xFFB3C0C3),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Collected ${ftodRupees(day.collectedAmount)} '
                  '(${day.collectedPercent}%)'
                  '${late > 0 ? ' · ${ftodRupees(late)} after due date' : ''}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkSoft,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 10),
                _StatusBar(counts: day.counts, height: 6),
                const SizedBox(height: 10),
                if (day.collections.isEmpty)
                  const Text(
                    'Nothing collected yet',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  )
                else ...[
                  const Text(
                    'Collected on',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in day.collections)
                        _CollectionChip(
                          collection: c,
                          daysAfter: c.daysAfter(day.dueDate),
                        ),
                    ],
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

/// "04 Sep · 3 · ₹13,500" with a "+3d" tag when it came in after the due date.
class _CollectionChip extends StatelessWidget {
  const _CollectionChip({required this.collection, required this.daysAfter});
  final FtodCollectionDay collection;
  final int daysAfter;

  @override
  Widget build(BuildContext context) {
    final color = daysAfter > 0
        ? const Color(0xFF9A5B00)
        : daysAfter < 0
            ? AppColors.info
            : AppColors.success;
    final bg = daysAfter > 0
        ? AppColors.warningTint
        : daysAfter < 0
            ? AppColors.infoTint
            : AppColors.successTint;
    final tag = daysAfter > 0
        ? '+${daysAfter}d'
        : daysAfter < 0
            ? 'early'
            : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            collection.chipLabel(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (tag != null) ...[
            const SizedBox(width: 5),
            Text(
              tag,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({
    required this.due,
    required this.today,
    required this.showOfficer,
    required this.onCall,
  });

  final FtodDue due;
  final DateTime today;
  final bool showOfficer;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final color = ftodStatusColor(due.status);
    final progress =
        due.dueAmount <= 0 ? 0.0 : (due.collectedAmount / due.dueAmount).clamp(0.0, 1.0);
    final branch = ftodBranchLabel(due.branchName);
    final hasPhone = (due.phone ?? '').trim().isNotEmpty;
    final owesMoney =
        due.status == FtodStatus.partial || due.status == FtodStatus.pending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProAvatar(name: due.customerName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  due.customerName,
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
                  [
                    'EMI ${ftodRupees(due.dueAmount)}',
                    'Due ${ftodDay(due.dueDate)}',
                    if (due.reference != null) due.reference!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.muted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 7),
                _statusPill(due.status, due.statusText(today)),
                const SizedBox(height: 9),
                ProBar(
                  value: progress.toDouble(),
                  color: owesMoney ? color : AppColors.success,
                  height: 4,
                ),
                const SizedBox(height: 6),
                Text(
                  due.status == FtodStatus.partial
                      ? '${due.collectedLine()} · Balance ${ftodRupees(due.balance)}'
                      : due.collectedLine(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (due.collections.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoLine(
                    icon: Icons.payments_outlined,
                    text: 'Paid ${due.paymentsLine()}',
                  ),
                ],
                if (branch.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _InfoLine(icon: Icons.store_mall_directory_outlined, text: branch),
                ],
                if (showOfficer && (due.fieldOfficerName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _InfoLine(
                    icon: Icons.badge_outlined,
                    text: 'Field officer: ${due.fieldOfficerName}',
                  ),
                ],
              ],
            ),
          ),
          if (hasPhone) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Call ${due.customerName}',
              child: Material(
                color: AppColors.successTint,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onCall,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.call_rounded, size: 19, color: AppColors.success),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: AppColors.faint),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.inkSoft,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
