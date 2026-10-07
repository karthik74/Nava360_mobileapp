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
import '../../core/pro_ui.dart';
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
  (value: 'DRAFT', label: 'Draft'),
  (value: 'PLANNED', label: 'Planned'),
  (value: 'ASSIGNED', label: 'Assigned'),
  (value: 'IN_PROGRESS', label: 'In progress'),
  (value: 'SUBMITTED', label: 'Submitted'),
  (value: 'SUPERVISOR_APPROVAL_PENDING', label: 'Supervisor approval'),
  (value: 'BM_ACTION_PENDING', label: 'Sent to BM'),
  (value: 'BM_ACTION_SUBMITTED', label: 'BM action submitted'),
  (value: 'VERIFICATION_PENDING', label: 'Verification'),
  (value: 'REOPENED', label: 'Reopened'),
  (value: 'CLOSED', label: 'Closed'),
  (value: 'CANCELLED', label: 'Cancelled'),
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
  const MyAuditsScreen({
    super.key,
    this.embedded = false,
    this.mine,
    this.initialStatus,
    this.initialBranchId,
  });

  /// Render without Scaffold/AppBar (hosted inside the audit home tabs).
  final bool embedded;

  /// true = only the signed-in auditor's audits ("My Audits"), false = the
  /// server's permission-scoped list ("Audit Plans"), null = auto-detect.
  final bool? mine;
  final String? initialStatus;
  final int? initialBranchId;

  @override
  ConsumerState<MyAuditsScreen> createState() => _MyAuditsScreenState();
}

class _MyAuditsScreenState extends ConsumerState<MyAuditsScreen> {
  String? _status;
  int _page = 0;
  String _q = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _branchId = widget.initialBranchId;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
    final isAuditorOnly = widget.mine ??
        ((user?.hasPermission('AUDIT_PERFORM') ?? false) &&
            !(user?.hasPermission('AUDIT_VIEW_ALL') ?? false) &&
            !(user?.hasPermission('AUDIT_VIEW_HIERARCHY') ?? false));
    final auditorId = isAuditorOnly ? user?.employeeId : null;

    final branches = ref.watch(auditBranchesProvider).asData?.value ??
        const <BranchOption>[];
    final scoped = _inScope(branches);
    final termBranch = Branding.current.term('branch');

    final query = AuditPlansQuery(
      status: _status,
      // Only branchId is server-filterable — see _orgFilterCard for why the
      // upper levels narrow the Branch picker instead of filtering directly.
      branchId: _branchId,
      auditorId: auditorId,
      q: _q,
      page: _page,
      size: 20,
    );
    final async = ref.watch(myAuditsProvider(query));
    final pageData = async.valueOrNull;
    final title = widget.mine == true ? 'My audits' : 'Audit plans';

    final content = ProPage(
      onRefresh: () async {
        ref.invalidate(myAuditsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      },
      // Room for the "New plan" button when hosted in the audit home tabs.
      padding: EdgeInsets.fromLTRB(16, 16, 16, widget.embedded ? 96 : 24),
      hero: ProHero(
        title: title,
        subtitle: pageData == null
            ? 'Loading audits…'
            : '${pageData.totalElements} '
                '${pageData.totalElements == 1 ? 'audit' : 'audits'}'
                '${_q.isEmpty ? '' : ' · “$_q”'}',
        actions: [
          if (branches.isNotEmpty)
            ProHeroIconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Filter by $termBranch',
              badge: _hasOrgFilter,
              onTap: () => setState(() => _filtersOpen = !_filtersOpen),
            ),
        ],
        overlap: _SubmitSearchField(
          controller: _searchCtrl,
          hint: 'Search code or title',
          showClear: _q.isNotEmpty,
          onSubmitted: (v) => setState(() {
            _q = v.trim();
            _page = 0;
          }),
          onClear: () {
            _searchCtrl.clear();
            setState(() {
              _q = '';
              _page = 0;
            });
          },
        ),
        children: [ProHeroStats(stats: _stats(pageData))],
      ),
      children: [
        ProChipBar(
          labels: [for (final f in _kStatusFilters) f.label],
          selected: _kStatusFilters.indexWhere((f) => f.value == _status),
          onSelected: (i) => setState(() {
            _status = _kStatusFilters[i].value;
            _page = 0;
          }),
          bleed: 0,
        ),
        if (_filtersOpen && branches.isNotEmpty)
          _orgFilterCard(branches, scoped, termBranch),
        if (_hasOrgFilter) _scopeNote(scoped, termBranch),
        async.when(
          loading: () => const AppLoadingBlock(height: 240),
          error: (e, __) => AppErrorPanel(
            message: 'Could not load audits.\n$e',
            onRetry: () => ref.invalidate(myAuditsProvider),
          ),
          data: (pageData) {
            if (pageData.content.isEmpty) {
              return ProEmpty(
                icon: Icons.fact_check_rounded,
                title: _hasOrgFilter
                    ? 'No audits for the selected scope.'
                    : 'No audits found.',
                message: _hasOrgFilter
                    ? 'Try clearing the filter.'
                    : 'Assigned branch audits will appear here.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(
                  title: '$title · ${pageData.totalElements}',
                  small: true,
                ),
                const SizedBox(height: 8),
                ProListGroup(
                  children: [
                    for (final plan in pageData.content)
                      _AuditPlanRow(plan: plan, onTap: () => _open(plan)),
                  ],
                ),
                if (pageData.totalPages > 1) ...[
                  const SizedBox(height: 14),
                  AuditPager(
                    page: pageData.page,
                    totalPages: pageData.totalPages,
                    onPrev:
                        _page > 0 ? () => setState(() => _page -= 1) : null,
                    onNext: pageData.last
                        ? null
                        : () => setState(() => _page += 1),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Internal audit')),
      body: content,
    );
  }

  /// Hero tiles built from the page already loaded.
  List<ProStat> _stats(AuditPage<AuditPlan>? pd) {
    final rows = pd?.content ?? const <AuditPlan>[];
    final scored = rows.where((p) => p.finalScore != null).toList();
    final avg = scored.isEmpty
        ? null
        : scored.fold<double>(0, (a, p) => a + p.finalScore!) / scored.length;
    String statusLabel() {
      for (final f in _kStatusFilters) {
        if (f.value == _status) return f.label;
      }
      return _status ?? 'All statuses';
    }

    return [
      ProStat(
        label: 'Audits',
        value: pd == null ? '—' : '${pd.totalElements}',
        sub: _status == null ? 'All statuses' : statusLabel(),
        dot: const Color(0xFF9FCBD5),
      ),
      ProStat(
        label: 'In view',
        value: pd == null ? '—' : '${rows.length}',
        sub: pd == null
            ? null
            : (pd.totalPages > 1
                ? 'Page ${pd.page + 1} of ${pd.totalPages}'
                : 'All loaded'),
        dot: const Color(0xFF5FC3D6),
      ),
      ProStat(
        label: 'Avg score',
        value: auditPct(avg),
        sub: pd == null ? null : '${scored.length} scored',
        dot: AppColors.live,
      ),
    ];
  }

  Future<void> _pick<T>({
    required String title,
    required T? selected,
    required List<({T? value, String label})> options,
    required ValueChanged<T?> onChanged,
  }) async {
    final r = await showAuditPicker<T>(
      context,
      title: title,
      options: options,
      selected: selected,
    );
    if (r == null || !mounted) return;
    onChanged(r.value);
  }

  /// Region → Division → Area → Branch cascade.
  ///
  /// `GET /api/audit/plans` accepts `branchId` only — it has no region /
  /// division / area parameters — so the upper three levels narrow the Branch
  /// picker rather than filtering the list themselves. The list re-queries
  /// once a branch is picked. Filtering the upper levels client-side instead
  /// would silently break the server-side pager.
  Widget _orgFilterCard(
    List<BranchOption> all,
    List<BranchOption> scoped,
    String termBranch,
  ) {
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

    List<({String? value, String label})> strOpts(List<String> v, String allLabel) => [
          (value: null, label: allLabel),
          for (final s in v) (value: s, label: s),
        ];

    String? branchLabel;
    for (final b in scoped) {
      if (b.id == _branchId) branchLabel = b.label;
    }

    final region = AuditPickField(
      label: termRegion,
      value: _region ?? 'All ${_plural(termRegion)}',
      active: _region != null,
      onTap: () => _pick<String>(
        title: termRegion,
        selected: _region,
        options: strOpts(regions, 'All ${_plural(termRegion)}'),
        onChanged: (v) => setState(() {
          _region = v;
          _division = null;
          _area = null;
          _branchId = null;
          _page = 0;
        }),
      ),
    );
    final division = AuditPickField(
      label: termDivision,
      value: _division ?? 'All ${_plural(termDivision)}',
      active: _division != null,
      onTap: () => _pick<String>(
        title: termDivision,
        selected: _division,
        options: strOpts(divisions, 'All ${_plural(termDivision)}'),
        onChanged: (v) => setState(() {
          _division = v;
          _area = null;
          _branchId = null;
          _page = 0;
        }),
      ),
    );
    final area = AuditPickField(
      label: termArea,
      value: _area ?? 'All ${_plural(termArea)}',
      active: _area != null,
      onTap: () => _pick<String>(
        title: termArea,
        selected: _area,
        options: strOpts(areas, 'All ${_plural(termArea)}'),
        onChanged: (v) => setState(() {
          _area = v;
          _branchId = null;
          _page = 0;
        }),
      ),
    );
    final branch = AuditPickField(
      label: termBranch,
      value: branchLabel ?? 'All ${_plural(termBranch)}',
      active: _branchId != null,
      onTap: () => _pick<int>(
        title: termBranch,
        selected: _branchId,
        options: [
          (value: null, label: 'All ${_plural(termBranch)}'),
          for (final b in scoped) (value: b.id, label: b.label),
        ],
        onChanged: (v) => setState(() {
          _branchId = v;
          _page = 0;
        }),
      ),
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: 'Filter by $termBranch',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_activeFilterCount > 0)
                  ProPill('$_activeFilterCount', color: AppColors.primary),
                IconButton(
                  tooltip: 'Close filter',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.muted),
                  onPressed: () => setState(() => _filtersOpen = false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: region),
            const SizedBox(width: 8),
            Expanded(child: division),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: area),
            const SizedBox(width: 8),
            Expanded(child: branch),
          ]),
        ],
      ),
    );
  }

  Widget _scopeNote(List<BranchOption> scoped, String termBranch) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 17, color: AppColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scopeText(scoped, termBranch),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (_branchId == null)
                  Text(
                    'Pick a ${termBranch.toLowerCase()} to filter the list.',
                    style: AppText.caption,
                  ),
              ],
            ),
          ),
          TextButton(onPressed: _clearOrgFilter, child: const Text('Clear')),
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

  void _open(AuditPlan plan) {
    final id = plan.id;
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuditDetailScreen(planId: id),
    ));
  }
}

/// Raised search field (hero overlap) that searches on submit, like before.
class _SubmitSearchField extends StatelessWidget {
  const _SubmitSearchField({
    required this.controller,
    required this.hint,
    required this.showClear,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final bool showClear;
  final ValueChanged<String> onSubmitted;
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
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
          suffixIcon: showClear
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: onClear,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          border: border(AppColors.hairline),
          enabledBorder: border(AppColors.hairline),
          focusedBorder: border(AppColors.primary, 1.6),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _AuditPlanRow extends StatelessWidget {
  const _AuditPlanRow({required this.plan, required this.onTap});
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
    final idLine = [
      if ((plan.code ?? '').isNotEmpty) plan.code!,
      if ((plan.branchName ?? '').isNotEmpty) plan.branchName!,
    ].join(' · ');
    final dates = _dateRange().isEmpty ? 'No dates set' : _dateRange();
    return ProListRow(
      leading: ProIconWell(
        icon: Icons.fact_check_rounded,
        color: auditStatusTone(plan.status).color,
      ),
      title: plan.title ?? plan.code ?? 'Audit',
      titleMaxLines: 2,
      subtitle: idLine.isEmpty ? null : idLine,
      meta: (plan.finalScore != null && (plan.grade ?? '').isNotEmpty)
          ? '$dates · Grade ${plan.grade}'
          : dates,
      value: plan.finalScore != null ? auditPct(plan.finalScore) : null,
      valueColor: auditInk(tone),
      pill: AuditStatusChip(status: plan.status),
      onTap: onTap,
    );
  }
}
