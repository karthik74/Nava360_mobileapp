// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Analytical Tool (route /mis/analytical). A national leaderboard: Top-5
//  / Bottom-5 at every level (region/division/area — all-India, unscoped),
//  plus a searchable full national list for FOs and Branches, and a "your
//  rank" line for FOs. Collection (MTD-as-of-date, PAR bucket tabs) or
//  disbursement (by month). Ports AnalyticalScreen.tsx exactly — this
//  REPLACES the old role-hierarchy drill-down ("Lowest 10%") tool, which the
//  web app itself moved away from (see analysisApi.ts's header comment).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

class _BucketDef {
  final String key;
  final String label;
  const _BucketDef(this.key, this.label);
}

const List<_BucketDef> _buckets = [
  _BucketDef('regular', 'Regular'),
  _BucketDef('1_30', '1-30'),
  _BucketDef('31_60', '31-60'),
  _BucketDef('pnpa', 'PNPA'),
  _BucketDef('npa', 'NPA'),
];

const Map<String, String> _levelLabel = {
  'region': 'Region',
  'division': 'Division',
  'area': 'Area',
  'branch': 'Branch',
  'employee': 'Officer',
};

/// Name match, plus emp_id match for the Officer level. Empty query = all.
List<AnalysisUnitRow> _filterRows(
    List<AnalysisUnitRow> rows, String query, bool isEmployee) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows
      .where((r) =>
          r.unit.toLowerCase().contains(q) ||
          (isEmployee && (r.empId ?? '').toLowerCase().contains(q)))
      .toList();
}

class MisAnalyticalScreen extends ConsumerStatefulWidget {
  const MisAnalyticalScreen({super.key});

  @override
  ConsumerState<MisAnalyticalScreen> createState() =>
      _MisAnalyticalScreenState();
}

class _MisAnalyticalScreenState extends ConsumerState<MisAnalyticalScreen> {
  String _mode = 'collection'; // collection | disbursement
  String _bucketKey = 'regular';
  String? _date;
  String? _month;

  static const _title = 'Analytical tool';
  static const _subtitle = 'National rankings at every level';

  @override
  Widget build(BuildContext context) {
    final filtersAsync = ref.watch(misAnalysisFiltersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Analytical tool')),
      body: filtersAsync.when(
        loading: () => const ProPage(
          hero: ProHero(title: _title, subtitle: _subtitle),
          children: [AppLoadingBlock(height: 240)],
        ),
        error: (e, _) => ProPage(
          hero: const ProHero(title: _title, subtitle: _subtitle),
          children: [
            AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(misAnalysisFiltersProvider),
            ),
          ],
        ),
        data: _body,
      ),
    );
  }

  Widget _body(AnalysisFilters filters) {
    final activeDate =
        _date ?? (filters.dates.isNotEmpty ? filters.dates.first : null);
    final activeMonth =
        _month ?? (filters.months.isNotEmpty ? filters.months.first : null);
    final dateReady =
        _mode == 'disbursement' ? activeMonth != null : activeDate != null;

    // Every level — region, division, area, branch, FO — top 5 (+ bottom 5
    // except region) nationally, one shared call. Branch/employee also carry
    // the full national list, backing the searchable panels below.
    final query = AnalysisQuery(
      mode: _mode,
      date: activeDate,
      month: activeMonth,
      bucket: _bucketKey,
    );

    final leaderboardAsync = dateReady
        ? ref.watch(misAnalysisLeaderboardProvider(query))
        : const AsyncValue<AnalysisLeaderboard>.loading();
    final myRankAsync = dateReady
        ? ref.watch(misAnalysisMyRankProvider(query))
        : const AsyncValue<AnalysisMyRank>.loading();
    final myRank = myRankAsync.asData?.value;

    // The caller's own national rank at each level they belong to — the
    // most specific three lead the hero.
    final mine = <ProStat>[];
    if (myRank != null) {
      for (final k in const ['region', 'division', 'area', 'branch', 'employee']) {
        final e = myRank.level(k);
        if (e == null) continue;
        mine.add(ProStat(
          label: k == 'employee' ? 'FO' : (_levelLabel[k] ?? k),
          value: '#${e.rank}',
          sub: 'of ${misNum(e.total)}',
        ));
      }
    }
    final heroStats = mine.length > 3 ? mine.sublist(mine.length - 3) : mine;
    final bucketLabel = _buckets
        .firstWhere((b) => b.key == _bucketKey, orElse: () => _buckets.first)
        .label;

    return ProPage(
      onRefresh: () async {
        if (!dateReady) return;
        ref.invalidate(misAnalysisLeaderboardProvider(query));
        ref.invalidate(misAnalysisMyRankProvider(query));
      },
      hero: ProHero(
        title: _title,
        subtitle: _subtitle,
        // The period picker straddles the hero. Collection figures are always
        // MTD as of the picked date — the daily feed is itself month-to-date
        // cumulative, so there is no separate "for the day only" reading to
        // offer alongside it.
        overlap: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            boxShadow: AppShadows.lifted,
          ),
          child: _mode == 'disbursement'
              ? MisMonthPicker(
                  label: 'Month',
                  value: activeMonth,
                  available: filters.months,
                  onChanged: (v) => setState(() => _month = v),
                )
              : MisDatePicker(
                  label: 'MTD as of',
                  value: activeDate,
                  available: filters.dates,
                  onChanged: (v) => setState(() => _date = v),
                ),
        ),
        children: [
          ProHeroSegmented(
            labels: const ['Collection', 'Disbursement'],
            selected: _mode == 'disbursement' ? 1 : 0,
            onChanged: (i) => setState(
                () => _mode = i == 1 ? 'disbursement' : 'collection'),
          ),
          if (_mode == 'collection')
            ProHeroSegmented(
              labels: [for (final b in _buckets) b.label],
              selected: _buckets
                  .indexWhere((b) => b.key == _bucketKey)
                  .clamp(0, _buckets.length - 1),
              onChanged: (i) => setState(() => _bucketKey = _buckets[i].key),
            ),
          if (heroStats.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroKicker(
                  left: 'Your national rank',
                  right: _mode == 'collection'
                      ? '$bucketLabel · MTD ${activeDate != null ? misPrettyDate(activeDate) : ''}'
                      : (activeMonth != null ? misMonthLabel(activeMonth) : ''),
                ),
                const SizedBox(height: 8),
                ProHeroStats(stats: heroStats),
              ],
            ),
        ],
      ),
      gap: 22,
      children: [
        _LevelPanel(
          title: 'Regions',
          levelKey: 'region',
          leaderboardAsync: leaderboardAsync,
          myRank: myRank,
          mode: _mode,
        ),
        _LevelPanel(
          title: 'Divisions',
          levelKey: 'division',
          leaderboardAsync: leaderboardAsync,
          myRank: myRank,
          mode: _mode,
        ),
        _LevelPanel(
          title: 'Areas',
          levelKey: 'area',
          leaderboardAsync: leaderboardAsync,
          myRank: myRank,
          mode: _mode,
        ),
        // FOs — still top 5 / bottom 5 (there can be thousands nationally),
        // but searchable by name or employee ID within the full national list.
        _LevelPanel(
          title: 'FOs',
          levelKey: 'employee',
          leaderboardAsync: leaderboardAsync,
          myRank: myRank,
          mode: _mode,
          showYourRankLine: true,
          searchable: true,
        ),
        // Branches — last on purpose: unlike every level above it, this one
        // shows the FULL national list (not just top/bottom 5), so it reads as
        // the "browse everything" panel at the end of the screen.
        _BranchPanel(
          leaderboardAsync: leaderboardAsync,
          myRank: myRank,
          mode: _mode,
        ),
      ],
    );
  }
}

/// "Your national rank · Regular · MTD 03 Oct 2026" above the hero stats.
class _HeroKicker extends StatelessWidget {
  const _HeroKicker({required this.left, required this.right});
  final String left, right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          left,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xBDFFFFFF),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0x94FFFFFF),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small grey label above a group of rank rows, with an optional dot.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.dot});
  final String text;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One white card of rank rows, hairline-divided.
class _RankGroup extends StatelessWidget {
  const _RankGroup({
    required this.rows,
    required this.levelKey,
    required this.mode,
    required this.mineUnit,
  });
  final List<AnalysisUnitRow> rows;
  final String levelKey;
  final String mode;
  final String? mineUnit;

  @override
  Widget build(BuildContext context) {
    return ProListGroup(
      dividerIndent: 0,
      children: [
        for (final r in rows)
          _RankTile(
            row: r,
            levelKey: levelKey,
            mode: mode,
            isMine: mineUnit != null && r.unit == mineUnit,
          ),
      ],
    );
  }
}

/// One level — Top 5 (all regions for `region` — too few nationally for a
/// distinct bottom 5) and Bottom 5, stacked. The caller's own unit, wherever
/// it lands, is highlighted.
class _LevelPanel extends StatefulWidget {
  const _LevelPanel({
    required this.title,
    required this.levelKey,
    required this.leaderboardAsync,
    required this.myRank,
    required this.mode,
    this.showYourRankLine = false,
    this.searchable = false,
  });

  final String title;
  final String levelKey;
  final AsyncValue<AnalysisLeaderboard> leaderboardAsync;
  final AnalysisMyRank? myRank;
  final String mode;
  final bool showYourRankLine;
  final bool searchable;

  @override
  State<_LevelPanel> createState() => _LevelPanelState();
}

class _LevelPanelState extends State<_LevelPanel> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmployee = widget.levelKey == 'employee';
    final hasBottom = widget.levelKey != 'region';
    final mine = widget.myRank?.level(widget.levelKey);
    final label = _levelLabel[widget.levelKey] ?? widget.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(title: widget.title),
        if (widget.searchable) ...[
          const SizedBox(height: 10),
          ProSearchField(
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            hint: 'Search ${label.toLowerCase()} by name or emp ID',
          ),
        ],
        const SizedBox(height: 12),
        widget.leaderboardAsync.when(
          loading: () => const AppLoadingBlock(height: 140),
          error: (e, _) => AppErrorPanel(message: e.toString()),
          data: (lb) {
            final data = lb.level(widget.levelKey);
            if (data.top.isEmpty) {
              return MisInlineEmpty(
                  'No ${label.toLowerCase()} data for this date / bucket.');
            }
            final searching = widget.searchable && _query.trim().isNotEmpty;
            if (searching) {
              // Search the full national list when the backend supplies
              // one; degrade to the current top+bottom 5 otherwise.
              final pool = data.all ?? [...data.top, ...data.bottom];
              final results = _filterRows(pool, _query, isEmployee);
              if (results.isEmpty) {
                return MisInlineEmpty(
                    'No ${label.toLowerCase()} matches your search.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GroupLabel(
                      '${misNum(results.length)} match${results.length == 1 ? '' : 'es'} nationally'),
                  _RankGroup(
                    rows: results,
                    levelKey: widget.levelKey,
                    mode: widget.mode,
                    mineUnit: mine?.unit,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GroupLabel(
                  widget.levelKey == 'region' ? 'All regions' : 'Top 5',
                  dot: AppColors.success,
                ),
                _RankGroup(
                  rows: data.top,
                  levelKey: widget.levelKey,
                  mode: widget.mode,
                  mineUnit: mine?.unit,
                ),
                if (hasBottom && data.bottom.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const _GroupLabel('Bottom 5', dot: AppColors.danger),
                  _RankGroup(
                    rows: data.bottom,
                    levelKey: widget.levelKey,
                    mode: widget.mode,
                    mineUnit: mine?.unit,
                  ),
                ],
              ],
            );
          },
        ),
        if (widget.showYourRankLine) ...[
          const SizedBox(height: 12),
          if (mine != null)
            ProNote(
              'Your rank: #${mine.rank} of ${misNum(mine.total)} FOs — '
              '${widget.mode == 'collection' ? '${mine.pct ?? '0.00'}%' : misRupees(mine.amount ?? 0)} '
              '(${mine.unit}).',
              tone: ProNoteTone.info,
              icon: Icons.emoji_events_outlined,
            )
          else
            const ProNote('No FO data for you on this date / bucket.',
                tone: ProNoteTone.info),
        ],
      ],
    );
  }
}

/// Branches — the one panel that shows EVERY branch nationally (not just its
/// top/bottom 5), because that's the level small enough to browse in full and
/// specific enough to be worth searching by name.
class _BranchPanel extends StatefulWidget {
  const _BranchPanel({
    required this.leaderboardAsync,
    required this.myRank,
    required this.mode,
  });

  final AsyncValue<AnalysisLeaderboard> leaderboardAsync;
  final AnalysisMyRank? myRank;
  final String mode;

  @override
  State<_BranchPanel> createState() => _BranchPanelState();
}

class _BranchPanelState extends State<_BranchPanel> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.myRank?.branch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProSectionHeader(title: 'Branches'),
        const SizedBox(height: 10),
        ProSearchField(
          controller: _controller,
          onChanged: (v) => setState(() => _query = v),
          hint: 'Search branch by name',
        ),
        const SizedBox(height: 12),
        widget.leaderboardAsync.when(
          loading: () => const AppLoadingBlock(height: 140),
          error: (e, _) => AppErrorPanel(message: e.toString()),
          data: (lb) {
            final allRows = lb.branch.all ?? const <AnalysisUnitRow>[];
            if (allRows.isEmpty) {
              return const MisInlineEmpty(
                  'No branch data for this date / bucket.');
            }
            final rows = _filterRows(allRows, _query, false);
            if (rows.isEmpty) {
              return const MisInlineEmpty('No branch matches your search.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GroupLabel(
                  _query.trim().isNotEmpty
                      ? '${misNum(rows.length)} of ${misNum(allRows.length)} branches'
                      : 'All ${misNum(allRows.length)} branches',
                ),
                _RankGroup(
                  rows: rows,
                  levelKey: 'branch',
                  mode: widget.mode,
                  mineUnit: mine?.unit,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Compact rank row — rank badge, unit (+ emp ID for the Officer level), and
/// the mode-specific figures — with the caller's own row (when present)
/// highlighted.
class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.row,
    required this.levelKey,
    required this.mode,
    required this.isMine,
  });

  final AnalysisUnitRow row;
  final String levelKey;
  final String mode;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final isEmployee = levelKey == 'employee';
    return Container(
      color: isMine ? const Color(0xFFF1F9F3) : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 38),
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isMine ? AppColors.successTint : AppColors.neutralTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${row.rank}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isMine ? AppColors.success : AppColors.inkSoft,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.unit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.33,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (isEmployee && (row.empId ?? '').isNotEmpty)
                      Text(
                        row.empId!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 8),
                const ProPill(
                  'Yours',
                  color: AppColors.success,
                  background: AppColors.successTint,
                  dot: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: mode == 'collection'
                ? Row(
                    children: [
                      Expanded(child: _kv('Demand', misNum(row.demand ?? 0))),
                      Expanded(
                          child: _kv(
                              'Collection', misNum(row.collection ?? 0))),
                      Expanded(
                          child: _kv('Achieved', '${row.pct ?? '0.00'}%')),
                      Expanded(
                          child: _kv('FTOD', misNum(row.ftod ?? 0),
                              color: const Color(0xFF9A5B00))),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                          child: _kv('Accounts', misNum(row.count ?? 0))),
                      Expanded(
                          child: _kv('Amount', misRupees(row.amount ?? 0))),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}
