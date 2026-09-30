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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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

    final header = <Widget>[
      _MonthSwitcher(
        label: ftodMonthLabel(_month),
        scopeLabel: dist == null ? null : _scopeLabel(dist.scope),
        onPrev: () => _shiftMonth(-1),
        // Dues can be imported a month ahead; nothing exists beyond that.
        onNext: _month.isBefore(ftodShiftMonth(_thisMonth, 1))
            ? () => _shiftMonth(1)
            : null,
      ),
      const SizedBox(height: 12),
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
                AppEmptyState(
                  icon: Icons.event_available_rounded,
                  message: 'No FTOD dues for ${ftodMonthLabel(_month)}.',
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('FTOD collections'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
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
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList(delegate: SliverChildListDelegate(header)),
              ),
              if (showList) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
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

  List<Widget> _distributionSection(FtodDistribution d) {
    return [
      _TotalsCard(totals: d.totals),
      const SizedBox(height: 20),
      const AppSectionHeader(
        title: 'Date-wise distribution',
        subtitle: 'When each due date\'s money came in · tap to see customers',
      ),
      const SizedBox(height: 10),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'Customers',
          subtitle: _dueDate == null
              ? 'All due dates this month'
              : 'Due ${ftodDay(_dueDate)}',
        ),
        if (_dueDate != null) ...[
          const SizedBox(height: 8),
          InputChip(
            label: Text('Due ${ftodDay(_dueDate)}'),
            avatar: const Icon(Icons.event_rounded, size: 16),
            onDeleted: () => _selectDueDate(null),
            deleteButtonTooltipMessage: 'Show all due dates',
          ),
        ],
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                count: all,
                selected: _status == null,
                color: AppColors.primary,
                onTap: () => _selectStatus(null),
              ),
              for (final s in _chipOrder)
                _FilterChip(
                  label: s.label,
                  count: counts?.of(s),
                  selected: _status == s,
                  color: ftodStatusColor(s),
                  onTap: () => _selectStatus(s),
                ),
            ],
          ),
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
        child = const AppEmptyState(
          icon: Icons.people_outline_rounded,
          message: 'No customers match this filter.',
        );
      }
      return SliverToBoxAdapter(child: child);
    }
    return SliverList.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _DueTile(
        due: _items[i],
        today: today,
        // Unknown scope (distribution failed): naming the officer is harmless.
        showOfficer: dist?.showsOfficer ?? true,
        onCall: () => _call(_items[i]),
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
      child = TextButton(
        onPressed: _loadMore,
        child: const Text('Load more'),
      );
    } else if (_items.length > 3) {
      child = Text(
        'All ${ftodCount(_items.length)} customers shown',
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
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

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.label,
    required this.scopeLabel,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final String? scopeLabel;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                if (scopeLabel != null)
                  Text(
                    scopeLabel!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNext,
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});
  final FtodTotals totals;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Customers',
                  value: ftodCount(totals.customers),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'EMI due',
                  value: ftodRupees(totals.dueAmount),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Collected',
                  value: ftodRupees(totals.collectedAmount),
                  sub: '${totals.collectedPercent}%',
                  subColor: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _StatusBar(counts: totals.counts, height: 10),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final s in _barOrder)
                _LegendDot(
                  color: ftodStatusColor(s),
                  label: '${s.label} ${ftodCount(totals.counts.of(s))}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.sub,
    this.subColor,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        if (sub != null)
          Text(
            sub!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: subColor ?? AppColors.muted,
            ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: SizedBox(
        height: height,
        child: counts.total == 0
            ? const ColoredBox(color: AppColors.hairline)
            : Row(
                children: [
                  for (final s in _barOrder)
                    if (counts.of(s) > 0)
                      Expanded(
                        flex: counts.of(s),
                        child: ColoredBox(color: ftodStatusColor(s)),
                      ),
                ],
              ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
      ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          shadow: selected ? AppShadows.card : AppShadows.soft,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: selected ? 1.6 : 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      day.headline(),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.filter_alt_rounded
                        : Icons.chevron_right_rounded,
                    size: 18,
                    color: selected ? AppColors.primary : AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Collected ${ftodRupees(day.collectedAmount)} '
                '(${day.collectedPercent}%)'
                '${late > 0 ? ' · ${ftodRupees(late)} after due date' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 10),
              _StatusBar(counts: day.counts, height: 6),
              const SizedBox(height: 10),
              if (day.collections.isEmpty)
                const Text(
                  'Nothing collected yet',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                )
              else ...[
                const Text(
                  'COLLECTED ON',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
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
        ? AppColors.warning
        : daysAfter < 0
            ? AppColors.info
            : AppColors.success;
    final tag = daysAfter > 0
        ? '+${daysAfter}d'
        : daysAfter < 0
            ? 'early'
            : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            collection.chipLabel(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (tag != null) ...[
            const SizedBox(width: 5),
            Text(
              tag,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: color,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: selected ? color : AppColors.hairline,
        ),
        label: Text(
          count == null ? label : '$label ${ftodCount(count!)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.inkSoft,
          ),
        ),
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

    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      due.customerName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        'EMI ${ftodRupees(due.dueAmount)}',
                        'Due ${ftodDay(due.dueDate)}',
                        if (due.reference != null) due.reference!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasPhone)
                IconButton.filledTonal(
                  onPressed: onCall,
                  tooltip: 'Call ${due.customerName}',
                  icon: const Icon(Icons.call_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.success.withValues(alpha: 0.12),
                    foregroundColor: AppColors.success,
                    minimumSize: const Size(38, 38),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          StatusPill(label: due.statusText(today), color: color),
          const SizedBox(height: 10),
          Text(
            due.status == FtodStatus.partial
                ? '${due.collectedLine()} · Balance ${ftodRupees(due.balance)}'
                : due.collectedLine(),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              minHeight: 5,
              color: owesMoney ? color : AppColors.success,
              backgroundColor: AppColors.hairline,
            ),
          ),
          if (due.collections.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.payments_outlined,
              text: 'Paid ${due.paymentsLine()}',
            ),
          ],
          if (branch.isNotEmpty) ...[
            const SizedBox(height: 6),
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
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}
