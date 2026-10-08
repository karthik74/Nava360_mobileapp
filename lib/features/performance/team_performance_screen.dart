// ─────────────────────────────────────────────────────────────────────────────
//  Performance — bottom-nav tab.
//
//  Shows the signed-in user their OWN scorecard summary (tap → full My
//  Performance), and — for managers / HR — the performance of every employee in
//  their reporting hierarchy (direct + indirect downline) via /api/performance/team.
//  The team endpoint is permission-gated server-side, so non-managers never call
//  it (no 403): they just see their own summary.
//
//  Rendered as the HomeShell `child` (the shell provides the app bar + bottom
//  nav), so this widget returns body content only — no Scaffold/AppBar here.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/auth_controller.dart';
import 'performance_models.dart';
import 'performance_repository.dart';
import 'performance_tab.dart';
import 'performance_widgets.dart';

const List<String> _kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Sentinel period meaning "latest available" (backend picks the most recent).
const PeriodOption _kLatest = PeriodOption(month: 0, year: 0, label: 'Latest');

class TeamPerformanceScreen extends ConsumerStatefulWidget {
  const TeamPerformanceScreen({super.key});

  @override
  ConsumerState<TeamPerformanceScreen> createState() =>
      _TeamPerformanceScreenState();
}

class _TeamPerformanceScreenState extends ConsumerState<TeamPerformanceScreen> {
  PeriodOption _selected = _kLatest;
  String _q = '';
  int _page = 0;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _canViewTeam(AuthUser? u) =>
      (u?.hasPermission('VIEW_TEAM_PERFORMANCE') ?? false) ||
      (u?.hasPermission('VIEW_ALL_PERFORMANCE') ?? false) ||
      (u?.hasRole(const {'ADMIN', 'HR'}) ?? false);

  /// The last 13 months as selectable periods, newest first, prefixed by "Latest".
  List<PeriodOption> _periodOptions() {
    final now = DateTime.now();
    final out = <PeriodOption>[_kLatest];
    for (var i = 0; i < 13; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      out.add(PeriodOption(
        month: d.month,
        year: d.year,
        label: '${_kMonthNames[d.month - 1]} ${d.year}',
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canTeam = _canViewTeam(user);
    final options = _periodOptions();
    final hasSelf = user?.employeeId != null;

    final int? qMonth = _selected.month == 0 ? null : _selected.month;
    final int? qYear = _selected.year == 0 ? null : _selected.year;
    final selectedIndex = options.indexOf(_selected);

    return ProPage(
      topInset: MediaQuery.of(context).padding.top,
      clearNav: true,
      onRefresh: () async {
        ref.invalidate(myPerformanceProvider);
        ref.invalidate(teamPerformanceProvider);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      },
      hero: ProHero(
        title: canTeam ? 'Team performance' : 'Performance',
        subtitle: _selected == _kLatest
            ? 'Latest scorecards'
            : 'Scorecards · ${_selected.label}',
        actions: [
          if (hasSelf)
            ProHeroIconButton(
              icon: Icons.insights_rounded,
              tooltip: 'My performance',
              onTap: () => context.push('/my-performance'),
            ),
        ],
        // ── Search the team (server-side, on submit) ──
        overlap: canTeam
            ? _SearchField(
                controller: _searchCtrl,
                onSubmit: (v) => setState(() {
                  _q = v.trim();
                  _page = 0;
                }),
                onClear: () => setState(() {
                  _q = '';
                  _page = 0;
                }),
              )
            : null,
        children: [
          // The signed-in user's own scorecard (everyone).
          if (hasSelf) _MyPerformanceCard(month: qMonth, year: qYear),
        ],
      ),
      children: [
        // Period chips (Latest + the last 13 months).
        ProChipBar(
          labels: [for (final p in options) p.label],
          selected: selectedIndex < 0 ? 0 : selectedIndex,
          onSelected: (i) => setState(() {
            _selected = options[i];
            _page = 0;
          }),
          bleed: 0,
        ),
        if (canTeam)
          _TeamList(
            query: TeamPerfQuery(
              month: qMonth,
              year: qYear,
              q: _q.isEmpty ? null : _q,
              page: _page,
              size: 20,
              sort: 'overallPercentage,desc',
            ),
            onPrev: _page > 0 ? () => setState(() => _page -= 1) : null,
            onNext: (last) => last ? null : () => setState(() => _page += 1),
            onOpen: _openEmployee,
          )
        else
          const _NotAManagerNote(),
      ],
    );
  }

  void _openEmployee(PerformanceSummary row) {
    final id = row.employeeId;
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EmployeePerformanceScreen(
        employeeId: id,
        name: row.employeeName ?? row.employeeCode ?? 'Employee',
      ),
    ));
  }
}

// ── My own scorecard summary (hero stats) ────────────────────────────────────

class _MyPerformanceCard extends ConsumerWidget {
  const _MyPerformanceCard({this.month, this.year});
  final int? month;
  final int? year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(myPerformanceProvider(PerfQuery(month: month, year: year)));
    void open() => context.push('/my-performance');
    return async.when(
      loading: () => const ProHeroStats(stats: [
        ProStat(label: 'My overall', value: '—'),
        ProStat(label: 'NLPL rank', value: '—'),
        ProStat(label: 'Branch rank', value: '—'),
      ]),
      error: (_, __) => const SizedBox.shrink(),
      data: (detail) {
        final s = detail.summary;
        return ProHeroStats(stats: [
          ProStat(
            label: 'My overall',
            value: perfPct(s?.overallPercentage),
            sub: s == null ? 'No scorecard synced yet' : (s.monthLabel ?? ''),
            dot: perfToneOnDark(s?.overallPercentage),
            onTap: open,
          ),
          ProStat(
            label: 'NLPL rank',
            value: s == null ? '—' : '#${s.nlplRank ?? '—'}',
            dot: const Color(0xFFF2B347),
            onTap: open,
          ),
          ProStat(
            label: 'Branch rank',
            value: s?.branchRank == null ? '—' : '#${s!.branchRank}',
            dot: Colors.white54,
            onTap: open,
          ),
        ]);
      },
    );
  }
}

// ── Team list (paged) ────────────────────────────────────────────────────────

class _TeamList extends ConsumerWidget {
  const _TeamList({
    required this.query,
    required this.onPrev,
    required this.onNext,
    required this.onOpen,
  });

  final TeamPerfQuery query;
  final VoidCallback? onPrev;
  final VoidCallback? Function(bool last) onNext;
  final void Function(PerformanceSummary row) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamPerformanceProvider(query));
    return async.when(
      loading: () => const AppLoadingBlock(height: 220),
      error: (e, __) => AppErrorPanel(
        message: 'Could not load team performance.\n$e',
        onRetry: () => ref.invalidate(teamPerformanceProvider),
      ),
      data: (pageData) {
        if (pageData.content.isEmpty) {
          return const AppEmptyState(
            icon: Icons.insights_rounded,
            message:
                'No team scorecards for this period.\nYour reportees\' performance will appear here once synced.',
          );
        }
        // The list is sorted by overall score server-side, so the position is
        // the rank — shown only when no search narrows the list.
        final ranked = query.q == null;
        final base = pageData.page * query.size;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProSectionHeader(
              title: query.q == null
                  ? 'My team · ${pageData.totalElements}'
                  : '${pageData.totalElements} match “${query.q}”',
              subtitle: 'Ranked by overall',
            ),
            const SizedBox(height: 10),
            ProListGroup(
              dividerIndent: ranked ? 92 : 62,
              children: [
                for (var i = 0; i < pageData.content.length; i++)
                  _TeamRow(
                    row: pageData.content[i],
                    rank: ranked ? base + i + 1 : null,
                    onTap: () => onOpen(pageData.content[i]),
                  ),
              ],
            ),
            if (pageData.totalPages > 1)
              _Pager(
                page: pageData.page,
                totalPages: pageData.totalPages,
                onPrev: onPrev,
                onNext: onNext(pageData.last),
              ),
          ],
        );
      },
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.row, required this.onTap, this.rank});
  final PerformanceSummary row;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final name = row.employeeName ?? row.employeeCode ?? 'Employee';
    final sub = [
      if ((row.employeeCode ?? '').isNotEmpty) row.employeeCode!,
      if ((row.branchName ?? '').isNotEmpty) row.branchName!,
    ].join(' · ');
    final meta = [
      if (row.nlplRank != null) 'NLPL #${row.nlplRank}',
      if (row.branchRank != null) 'Branch #${row.branchRank}',
      if ((row.branchGrade ?? '').isNotEmpty) 'Grade ${row.branchGrade}',
    ].join(' · ');
    final avatar = ProAvatar(name: row.employeeName ?? '?', size: 38);
    return ProListRow(
      leading: rank == null
          ? avatar
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: rank! <= 3 ? AppColors.primary : AppColors.faint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                avatar,
              ],
            ),
      title: name,
      subtitle: sub.isEmpty ? null : sub,
      meta: meta.isEmpty ? null : meta,
      value: perfPct(row.overallPercentage),
      valueColor: perfTone(row.overallPercentage),
      pill: ProPill.neutral('Overall'),
      onTap: onTap,
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });
  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            tooltip: 'Previous page',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const SizedBox(width: 12),
          Text(
            'Page ${page + 1} of $totalPages',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppColors.inkSoft,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(
            tooltip: 'Next page',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

/// Raised search field (Pro look) that searches on submit, like before.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onSubmit,
    required this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: c, width: w),
        );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: AppShadows.lifted,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, __) => TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          textInputAction: TextInputAction.search,
          onSubmitted: onSubmit,
          cursorColor: AppColors.primary,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Search team by name or code',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: v.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      controller.clear();
                      onClear();
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            border: border(AppColors.hairline),
            enabledBorder: border(AppColors.hairline),
            focusedBorder: border(AppColors.primary, 1.6),
          ),
        ),
      ),
    );
  }
}

class _NotAManagerNote extends StatelessWidget {
  const _NotAManagerNote();
  @override
  Widget build(BuildContext context) {
    return const ProNote(
      'Team performance is available to managers. Your own scorecard is shown above.',
    );
  }
}

// ── Pushed per-employee performance detail (its own Scaffold) ────────────────

class _EmployeePerformanceScreen extends StatelessWidget {
  const _EmployeePerformanceScreen({required this.employeeId, required this.name});
  final int employeeId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(name)),
      body: SafeArea(child: PerformanceTabBody(employeeId: employeeId)),
    );
  }
}
