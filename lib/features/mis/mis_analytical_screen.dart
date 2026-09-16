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

  @override
  Widget build(BuildContext context) {
    final filtersAsync = ref.watch(misAnalysisFiltersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Analytical Tool')),
      body: filtersAsync.when(
        loading: () => const AppLoadingBlock(height: 240),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misAnalysisFiltersProvider),
          ),
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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Collection figures are always MTD as of the picked date — the
            // daily feed is itself month-to-date cumulative, so there is no
            // separate "for the day only" reading to offer alongside it.
            if (_mode == 'collection')
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Text('MTD',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted)),
              ),
            Expanded(
              child: _mode == 'disbursement'
                  ? MisMonthPicker(
                      value: activeMonth,
                      available: filters.months,
                      onChanged: (v) => setState(() => _month = v),
                    )
                  : MisDatePicker(
                      value: activeDate,
                      available: filters.dates,
                      onChanged: (v) => setState(() => _date = v),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MisSegmented<String>(
          options: const [
            ('collection', 'Collection'),
            ('disbursement', 'Disbursement'),
          ],
          value: _mode,
          onChanged: (v) => setState(() => _mode = v),
        ),
        if (_mode == 'collection') ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MisSegmented<String>(
              options: [for (final b in _buckets) (b.key, b.label)],
              value: _bucketKey,
              onChanged: (v) => setState(() => _bucketKey = v),
            ),
          ),
        ],
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

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          if (widget.searchable) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    'Search ${label.toLowerCase()} by name or emp ID…',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          widget.leaderboardAsync.when(
            loading: () => const AppLoadingBlock(height: 140),
            error: (e, _) => AppErrorPanel(message: e.toString()),
            data: (lb) {
              final data = lb.level(widget.levelKey);
              if (data.top.isEmpty) {
                return MisInlineEmpty(
                    'No ${label.toLowerCase()} data for this date / bucket.');
              }
              final searching =
                  widget.searchable && _query.trim().isNotEmpty;
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${misNum(results.length)} match${results.length == 1 ? '' : 'es'} nationally',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: AppColors.inkSoft),
                    ),
                    const SizedBox(height: 8),
                    for (final r in results)
                      _RankTile(
                        row: r,
                        levelKey: widget.levelKey,
                        mode: widget.mode,
                        isMine: mine != null && r.unit == mine.unit,
                      ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.levelKey == 'region' ? 'All regions' : 'Top 5',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 8),
                  for (final r in data.top)
                    _RankTile(
                      row: r,
                      levelKey: widget.levelKey,
                      mode: widget.mode,
                      isMine: mine != null && r.unit == mine.unit,
                    ),
                  if (hasBottom && data.bottom.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Bottom 5',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: AppColors.inkSoft)),
                    const SizedBox(height: 8),
                    for (final r in data.bottom)
                      _RankTile(
                        row: r,
                        levelKey: widget.levelKey,
                        mode: widget.mode,
                        isMine: mine != null && r.unit == mine.unit,
                      ),
                  ],
                ],
              );
            },
          ),
          if (widget.showYourRankLine) ...[
            const SizedBox(height: 8),
            if (mine != null)
              Text(
                'Your rank: #${mine.rank} of ${misNum(mine.total)} FOs — '
                '${widget.mode == 'collection' ? '${mine.pct ?? '0.00'}%' : misRupees(mine.amount ?? 0)} '
                '(${mine.unit}).',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              )
            else
              const Text('No FO data for you on this date / bucket.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Branches',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search branch by name…',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _query.trim().isNotEmpty
                        ? '${misNum(rows.length)} of ${misNum(allRows.length)} branches'
                        : 'All ${misNum(allRows.length)} branches',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 8),
                  for (final r in rows)
                    _RankTile(
                      row: r,
                      levelKey: 'branch',
                      mode: widget.mode,
                      isMine: mine != null && r.unit == mine.unit,
                    ),
                ],
              );
            },
          ),
        ],
      ),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine
            ? AppColors.success.withOpacity(0.10)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: isMine
              ? AppColors.success.withOpacity(0.35)
              : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('#${row.rank}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isMine ? '★ ' : ''}${row.unit}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink),
                    ),
                    if (isEmployee && (row.empId ?? '').isNotEmpty)
                      Text(row.empId!,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (mode == 'collection')
            Row(
              children: [
                Expanded(child: _kv('Demand', misNum(row.demand ?? 0))),
                Expanded(
                    child: _kv('Collection', misNum(row.collection ?? 0))),
                Expanded(child: _kv('Achieved', '${row.pct ?? '0.00'}%')),
                Expanded(child: _kv('FTOD', misNum(row.ftod ?? 0))),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: _kv('Accounts', misNum(row.count ?? 0))),
                Expanded(child: _kv('Amount', misRupees(row.amount ?? 0))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink),
          ),
        ],
      );
}
