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

    final int? qMonth = _selected.month == 0 ? null : _selected.month;
    final int? qYear = _selected.year == 0 ? null : _selected.year;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(myPerformanceProvider);
        ref.invalidate(teamPerformanceProvider);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Match the My Team screen's spacing: status-bar inset + 8 at top (the
        // shell's glass app bar floats over), 16 horizontal, nav-bar inset at bottom.
        padding: EdgeInsets.fromLTRB(
            16, MediaQuery.of(context).padding.top + 8, 16,
            MediaQuery.of(context).padding.bottom + AppChrome.bottomNavHeight + 16),
        children: [
          // Sticky-feel month selector.
          PerfMonthSelector(
            periods: options,
            selected: _selected,
            onChanged: (p) => setState(() {
              _selected = p;
              _page = 0;
            }),
          ),
          const SizedBox(height: 12),

          // The signed-in user's own scorecard (everyone).
          if (user?.employeeId != null) ...[
            _MyPerformanceCard(month: qMonth, year: qYear),
            const SizedBox(height: 14),
          ],

          if (canTeam) ...[
            const Row(
              children: [
                Icon(Icons.groups_2_rounded, size: 17, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'My Team',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SearchField(
              controller: _searchCtrl,
              onSubmit: (v) => setState(() {
                _q = v.trim();
                _page = 0;
              }),
              onClear: () => setState(() {
                _q = '';
                _page = 0;
              }),
            ),
            const SizedBox(height: 12),
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
            ),
          ] else
            const _NotAManagerNote(),
        ],
      ),
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

// ── My own scorecard summary card ────────────────────────────────────────────

class _MyPerformanceCard extends ConsumerWidget {
  const _MyPerformanceCard({this.month, this.year});
  final int? month;
  final int? year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(myPerformanceProvider(PerfQuery(month: month, year: year)));
    return async.when(
      loading: () => const AppLoadingBlock(height: 96),
      error: (_, __) => const SizedBox.shrink(),
      data: (detail) {
        final s = detail.summary;
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: () => context.push('/my-performance'),
          child: GlassCard(
            shadow: AppShadows.soft,
            child: Row(
              children: [
                PerfRingProgress(
                  ratio: s?.overallPercentage,
                  size: 64,
                  label: 'Overall',
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Performance',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s == null
                            ? 'No scorecard synced yet'
                            : 'NLPL #${s.nlplRank ?? '—'}  ·  ${s.monthLabel ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        );
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
        return Column(
          children: [
            for (final row in pageData.content)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TeamRow(row: row, onTap: () => onOpen(row)),
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
  const _TeamRow({required this.row, required this.onTap});
  final PerformanceSummary row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = perfTone(row.overallPercentage);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        shadow: AppShadows.soft,
        child: Row(
          children: [
            UserAvatar(name: row.employeeName ?? '?', size: 38, radius: 11),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.employeeName ?? row.employeeCode ?? 'Employee',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((row.employeeCode ?? '').isNotEmpty) row.employeeCode!,
                      if ((row.branchName ?? '').isNotEmpty) row.branchName!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (row.nlplRank != null)
                        _MiniChip(
                            icon: Icons.emoji_events_rounded,
                            label: 'NLPL #${row.nlplRank}',
                            color: AppColors.primary),
                      if (row.branchRank != null)
                        _MiniChip(
                            icon: Icons.store_mall_directory_rounded,
                            label: 'Branch #${row.branchRank}',
                            color: AppColors.accent),
                      if ((row.branchGrade ?? '').isNotEmpty)
                        _MiniChip(
                            icon: Icons.workspace_premium_rounded,
                            label: 'Grade ${row.branchGrade}',
                            color: AppColors.pink),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: tone.withValues(alpha: 0.30)),
                  ),
                  child: Text(
                    perfPct(row.overallPercentage),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: tone,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Overall',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.primary,
            disabledColor: AppColors.hairline,
          ),
          Text(
            'Page ${page + 1} of $totalPages',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.primary,
            disabledColor: AppColors.hairline,
          ),
        ],
      ),
    );
  }
}

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
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmit,
              cursorColor: AppColors.primary,
              style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                hintText: 'Search by name or code…',
                hintStyle: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              splashRadius: 16,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: AppColors.muted),
              onPressed: () {
                controller.clear();
                onClear();
              },
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _NotAManagerNote extends StatelessWidget {
  const _NotAManagerNote();
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      shadow: AppShadows.soft,
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Team performance is available to managers. Your own scorecard is shown above.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.muted.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
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
      appBar: AppBar(
        title: Text(name),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(child: PerformanceTabBody(employeeId: employeeId)),
    );
  }
}
