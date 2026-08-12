// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — "My Audits" list (route: /audit).
//
//  Lists the current user's audits. For auditors (AUDIT_PERFORM) the list is
//  scoped to auditorId = authUser.employeeId; reviewers/HR with the broader
//  view permissions get the branch/hierarchy-scoped list the backend returns.
//  Card-first, RefreshIndicator pull-to-refresh, AppLoadingBlock / AppEmptyState
//  / AppErrorPanel states. Tap a card → AuditDetailScreen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/branding.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../requisitions/requisition_models.dart';
import '../requisitions/requisition_repository.dart';
import 'audit_detail_screen.dart';
import 'audit_models.dart';
import 'audit_repository.dart';
import 'audit_widgets.dart';

// Values MUST be backend AuditStatus enum names — anything else makes the
// list endpoint fail with "Failed to convert…".
const _kStatusFilters = <({String? value, String label})>[
  (value: null, label: 'All'),
  (value: 'IN_PROGRESS', label: 'In Progress'),
  (value: 'SUBMITTED', label: 'Submitted'),
  (value: 'SUPERVISOR_APPROVAL_PENDING', label: 'Supervisor Approval'),
  (value: 'BM_ACTION_PENDING', label: 'Sent to BM'),
  (value: 'VERIFICATION_PENDING', label: 'BM Submitted'),
  (value: 'CLOSED', label: 'Closed'),
];

/// Active branches with their org hierarchy, for the Region → Division → Area →
/// Branch cascade. One unscoped fetch of `GET /api/org/branches` backs all four
/// dropdowns — the higher levels are derived from the branch rows' labels, so
/// there are no extra round-trips per level.
final auditBranchesProvider =
    FutureProvider.autoDispose<List<BranchOption>>((ref) async {
  final all = await ref.watch(requisitionRepositoryProvider).listBranches();
  final active = all.where((b) => b.active).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  return active;
});

class MyAuditsScreen extends ConsumerStatefulWidget {
  const MyAuditsScreen({super.key});

  @override
  ConsumerState<MyAuditsScreen> createState() => _MyAuditsScreenState();
}

class _MyAuditsScreenState extends ConsumerState<MyAuditsScreen> {
  String? _status;
  int _page = 0;

  // Org filter cascade. The upper three levels are matched by label, not id,
  // because GET /api/org/branches carries hierarchy labels only.
  String? _region;
  String? _division;
  String? _area;
  int? _branchId;
  bool _filtersOpen = false;

  /// Branches under the region/division/area currently pinned.
  List<BranchOption> _inScope(List<BranchOption> all) => all.where((b) {
        if (_region != null && b.regionLabel != _region) return false;
        if (_division != null && b.divisionLabel != _division) return false;
        if (_area != null && b.areaLabel != _area) return false;
        return true;
      }).toList();

  static List<String> _distinct(Iterable<String?> values) =>
      values.where((s) => s != null && s.trim().isNotEmpty).cast<String>().toSet().toList()
        ..sort();

  bool get _hasOrgFilter =>
      _region != null || _division != null || _area != null || _branchId != null;

  int get _activeFilterCount => [_region, _division, _area, _branchId]
      .where((v) => v != null)
      .length;

  void _clearOrgFilter() => setState(() {
        _region = null;
        _division = null;
        _area = null;
        _branchId = null;
        _page = 0;
      });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    // Auditors see only their own assigned audits; broader viewers get the
    // server's branch/hierarchy-scoped list (no auditorId filter).
    final isAuditorOnly = (user?.hasPermission('AUDIT_PERFORM') ?? false) &&
        !(user?.hasPermission('AUDIT_VIEW_ALL') ?? false) &&
        !(user?.hasPermission('AUDIT_VIEW_HIERARCHY') ?? false);
    final auditorId = isAuditorOnly ? user?.employeeId : null;

    final branches = ref.watch(auditBranchesProvider).asData?.value ??
        const <BranchOption>[];
    final scoped = _inScope(branches);

    final query = AuditPlansQuery(
      status: _status,
      // Only branchId is server-filterable — see _OrgFilterCard for why the
      // upper levels narrow the Branch dropdown instead of filtering directly.
      branchId: _branchId,
      auditorId: auditorId,
      page: _page,
      size: 20,
    );
    final async = ref.watch(myAuditsProvider(query));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Internal Audit'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(myAuditsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 250));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _StatusFilterBar(
                selected: _status,
                onChanged: (v) => setState(() {
                  _status = v;
                  _page = 0;
                }),
              ),
              const SizedBox(height: 10),
              _buildOrgFilters(branches, scoped),
              const SizedBox(height: 14),
              async.when(
                loading: () => const AppLoadingBlock(height: 240),
                error: (e, __) => AppErrorPanel(
                  message: 'Could not load audits.\n$e',
                  onRetry: () => ref.invalidate(myAuditsProvider),
                ),
                data: (pageData) {
                  if (pageData.content.isEmpty) {
                    return AppEmptyState(
                      icon: Icons.fact_check_rounded,
                      message: _hasOrgFilter
                          ? 'No audits for the selected scope.\nTry clearing the filter.'
                          : 'No audits found.\nAssigned branch audits will appear here.',
                    );
                  }
                  return Column(
                    children: [
                      for (final plan in pageData.content)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AuditPlanCard(
                            plan: plan,
                            onTap: () => _open(plan),
                          ),
                        ),
                      if (pageData.totalPages > 1)
                        _Pager(
                          page: pageData.page,
                          totalPages: pageData.totalPages,
                          onPrev: _page > 0
                              ? () => setState(() => _page -= 1)
                              : null,
                          onNext: pageData.last
                              ? null
                              : () => setState(() => _page += 1),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Region → Division → Area → Branch cascade.
  ///
  /// `GET /api/audit/plans` accepts `branchId` only — it has no region /
  /// division / area parameters — so the upper three levels narrow the Branch
  /// dropdown rather than filtering the list themselves. The list re-queries
  /// once a branch is picked. Filtering the upper levels client-side instead
  /// would silently break the server-side pager.
  Widget _buildOrgFilters(List<BranchOption> all, List<BranchOption> scoped) {
    if (all.isEmpty) return const SizedBox.shrink();

    final regions = _distinct(all.map((b) => b.regionLabel));
    final divisions = _distinct(all
        .where((b) => _region == null || b.regionLabel == _region)
        .map((b) => b.divisionLabel));
    final areas = _distinct(all
        .where((b) =>
            (_region == null || b.regionLabel == _region) &&
            (_division == null || b.divisionLabel == _division))
        .map((b) => b.areaLabel));

    final termRegion = Branding.current.term('region');
    final termDivision = Branding.current.term('division');
    final termArea = Branding.current.term('area');
    final termBranch = Branding.current.term('branch');

    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _filtersOpen = !_filtersOpen),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(
                  'Filter by $termBranch',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                if (_activeFilterCount > 0) ...[
                  const SizedBox(width: 6),
                  StatusPill(
                    label: '$_activeFilterCount',
                    color: AppColors.primary,
                  ),
                ],
                const Spacer(),
                Icon(
                  _filtersOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
          if (_filtersOpen) ...[
            const SizedBox(height: 10),
            _dropdown<String>(
              hint: 'All ${_plural(termRegion)}',
              value: _region,
              items: _stringItems(regions, 'All ${_plural(termRegion)}'),
              onChanged: (v) => setState(() {
                _region = v;
                _division = null;
                _area = null;
                _branchId = null;
                _page = 0;
              }),
            ),
            _dropdown<String>(
              hint: 'All ${_plural(termDivision)}',
              value: _division,
              items: _stringItems(divisions, 'All ${_plural(termDivision)}'),
              onChanged: (v) => setState(() {
                _division = v;
                _area = null;
                _branchId = null;
                _page = 0;
              }),
            ),
            _dropdown<String>(
              hint: 'All ${_plural(termArea)}',
              value: _area,
              items: _stringItems(areas, 'All ${_plural(termArea)}'),
              onChanged: (v) => setState(() {
                _area = v;
                _branchId = null;
                _page = 0;
              }),
            ),
            _dropdown<int>(
              hint: 'All ${_plural(termBranch)}',
              value: _branchId,
              items: [
                DropdownMenuItem<int>(
                  value: null,
                  child: Text('All ${_plural(termBranch)}'),
                ),
                for (final b in scoped)
                  DropdownMenuItem<int>(
                    value: b.id,
                    child: Text(b.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() {
                _branchId = v;
                _page = 0;
              }),
            ),
          ],
          if (_hasOrgFilter) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _scopeText(scoped, termBranch),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearOrgFilter,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (_branchId == null)
              Text(
                'Pick a ${termBranch.toLowerCase()} to filter the list.',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// "South → Division 2 · 4 branches" — names only the levels actually pinned,
  /// so a filtered empty list can't be misread as "no audits anywhere".
  String _scopeText(List<BranchOption> scoped, String termBranch) {
    final trail = <String>[
      if (_region != null) _region!,
      if (_division != null) _division!,
      if (_area != null) _area!,
    ];
    if (_branchId != null) {
      final picked = scoped.where((b) => b.id == _branchId);
      if (picked.isNotEmpty) trail.add(picked.first.label);
    }
    final n = _branchId != null ? 1 : scoped.length;
    final count =
        '$n ${n == 1 ? termBranch.toLowerCase() : _plural(termBranch).toLowerCase()}';
    return trail.isEmpty ? count : '${trail.join(' → ')} · $count';
  }

  static String _plural(String term) =>
      term.endsWith('s') ? term : '${term}s';

  static List<DropdownMenuItem<String>> _stringItems(
    List<String> options,
    String allLabel,
  ) =>
      [
        DropdownMenuItem<String>(value: null, child: Text(allLabel)),
        for (final o in options)
          DropdownMenuItem<String>(
            value: o,
            child: Text(o, overflow: TextOverflow.ellipsis),
          ),
      ];

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            icon: const Icon(Icons.expand_more_rounded,
                size: 18, color: AppColors.muted),
            hint: Text(
              hint,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  void _open(AuditPlan plan) {
    final id = plan.id;
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuditDetailScreen(planId: id),
    ));
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onChanged});
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _kStatusFilters) ...[
            _FilterChip(
              label: f.label,
              selected: selected == f.value,
              onTap: () => onChanged(f.value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditPlanCard extends StatelessWidget {
  const _AuditPlanCard({required this.plan, required this.onTap});
  final AuditPlan plan;
  final VoidCallback onTap;

  String _dateRange() {
    final f = _fmt(plan.plannedStartDate);
    final t = _fmt(plan.plannedEndDate);
    if (f == null && t == null) return '';
    return '${f ?? '—'} → ${t ?? '—'}';
  }

  static String? _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('dd MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final tone = auditScoreTone(plan.finalScore);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(12),
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
                        plan.title ?? plan.code ?? 'Audit',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if ((plan.code ?? '').isNotEmpty) plan.code!,
                          if ((plan.branchName ?? '').isNotEmpty)
                            plan.branchName!,
                        ].join(' · '),
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
                const SizedBox(width: 8),
                AuditStatusChip(status: plan.status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 13, color: AppColors.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _dateRange().isEmpty ? 'No dates set' : _dateRange(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                if (plan.finalScore != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: tone.withValues(alpha: 0.30)),
                    ),
                    child: Text(
                      auditPct(plan.finalScore),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tone,
                      ),
                    ),
                  ),
                  if ((plan.grade ?? '').isNotEmpty) ...[
                    const SizedBox(width: 6),
                    StatusPill(
                      label: 'Grade ${plan.grade}',
                      color: AppColors.primary,
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
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
