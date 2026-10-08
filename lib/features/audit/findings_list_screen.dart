// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — findings list.
//
//  Two modes:
//    • execution-scoped: pass [executionId] ⇒ findings raised for that audit.
//    • assigned/branch:   omit it ⇒ a paged, filterable findings list.
//  Card-first, RefreshIndicator, AppLoadingBlock / AppEmptyState / AppErrorPanel.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'audit_models.dart';
import 'audit_repository.dart';
import 'audit_widgets.dart';
import 'finding_detail_screen.dart';

class FindingsListScreen extends ConsumerStatefulWidget {
  const FindingsListScreen({
    super.key,
    this.executionId,
    this.embedded = false,
    this.initialStatus,
    this.initialSeverity,
    this.initialOverdue,
    this.initialBranchId,
  });

  /// Render without Scaffold/AppBar (hosted inside the audit home tabs).
  final bool embedded;
  final String? initialStatus;
  final String? initialSeverity;
  final bool? initialOverdue;
  final int? initialBranchId;

  /// When set, lists findings for that single execution. When null, shows the
  /// paged/filtered assigned findings list.
  final int? executionId;

  @override
  ConsumerState<FindingsListScreen> createState() => _FindingsListScreenState();
}

class _FindingsListScreenState extends ConsumerState<FindingsListScreen> {
  String? _severity;
  String? _status;
  bool _overdue = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _severity = widget.initialSeverity;
    _status = widget.initialStatus;
    _overdue = widget.initialOverdue ?? false;
  }

  Future<void> _reload() async {
    ref.invalidate(findingsForExecutionProvider);
    ref.invalidate(findingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.executionId != null
        ? _executionList(widget.executionId!)
        : _pagedList();
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Findings')),
      body: content,
    );
  }

  String get _heroTitle {
    if (widget.executionId != null) return 'Audit findings';
    return widget.embedded ? 'Findings & CAPA' : 'Findings';
  }

  /// Severity tiles from the rows already loaded (tap = severity filter in
  /// the paged list).
  ProHeroStats _severityStats(List<AuditFinding> rows, {required bool filters}) {
    int n(String s) => rows.where((f) => f.severity == s).length;
    ProStat stat(String key, String label, Color dot) => ProStat(
          label: label,
          value: '${n(key)}',
          sub: n(key) == 1 ? 'finding' : 'findings',
          dot: dot,
          selected: filters && _severity == key,
          onTap: filters
              ? () => setState(() {
                    _severity = _severity == key ? null : key;
                    _page = 0;
                  })
              : null,
        );
    return ProHeroStats(stats: [
      stat('HIGH', 'High', const Color(0xFFE5484D)),
      stat('MODERATE', 'Moderate', const Color(0xFFF2B347)),
      stat('LOW', 'Low', AppColors.live),
    ]);
  }

  Widget _executionList(int execId) {
    final async = ref.watch(findingsForExecutionProvider(execId));
    final rows = async.valueOrNull;
    return ProPage(
      onRefresh: _reload,
      hero: ProHero(
        title: _heroTitle,
        subtitle: rows == null
            ? 'Loading findings…'
            : '${rows.length} raised for this audit',
        children: [_severityStats(rows ?? const [], filters: false)],
      ),
      children: [
        async.when(
          loading: () => const AppLoadingBlock(height: 240),
          error: (e, __) => AppErrorPanel(
            message: 'Could not load findings.\n$e',
            onRetry: () => ref.invalidate(findingsForExecutionProvider),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const ProEmpty(
                icon: Icons.verified_rounded,
                title: 'No findings raised for this audit.',
              );
            }
            return _list('All findings · ${rows.length}', rows);
          },
        ),
      ],
    );
  }

  Widget _pagedList() {
    final query =
        AuditFindingsQuery(
      status: _status,
      severity: _severity,
      branchId: widget.initialBranchId,
      overdue: _overdue ? true : null,
      page: _page,
      size: 20,
    );
    final async = ref.watch(findingsProvider(query));
    final pd = async.valueOrNull;
    return ProPage(
      onRefresh: _reload,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      hero: ProHero(
        title: _heroTitle,
        subtitle: pd == null
            ? 'Loading findings…'
            : '${pd.totalElements} ${pd.totalElements == 1 ? 'finding' : 'findings'}'
                '${pd.totalPages > 1 ? ' · page ${pd.page + 1} of ${pd.totalPages}' : ''}',
        actions: [
          ProHeroIconButton(
            icon: Icons.alarm_rounded,
            tooltip: _overdue ? 'Showing overdue only' : 'Overdue only',
            badge: _overdue,
            onTap: () => setState(() {
              _overdue = !_overdue;
              _page = 0;
            }),
          ),
        ],
        children: [_severityStats(pd?.content ?? const [], filters: true)],
      ),
      children: [
        ..._filterBars(),
        async.when(
          loading: () => const AppLoadingBlock(height: 240),
          error: (e, __) => AppErrorPanel(
            message: 'Could not load findings.\n$e',
            onRetry: () => ref.invalidate(findingsProvider),
          ),
          data: (pageData) {
            if (pageData.content.isEmpty) {
              return const ProEmpty(
                icon: Icons.verified_rounded,
                title: 'No findings match this filter.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _list('Findings · ${pageData.totalElements}', pageData.content),
                if (pageData.totalPages > 1) ...[
                  const SizedBox(height: 14),
                  AuditPager(
                    page: pageData.page,
                    totalPages: pageData.totalPages,
                    onPrev: _page > 0 ? () => setState(() => _page -= 1) : null,
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
  }

  Widget _list(String title, List<AuditFinding> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(title: title, small: true),
        const SizedBox(height: 8),
        ProListGroup(
          children: [
            for (final f in rows) _FindingRow(finding: f, onTap: () => _open(f)),
          ],
        ),
      ],
    );
  }

  List<Widget> _filterBars() {
    const opts = <({String? value, String label})>[
      (value: null, label: 'All'),
      (value: 'HIGH', label: 'High'),
      (value: 'MODERATE', label: 'Moderate'),
      (value: 'LOW', label: 'Low'),
    ];
    const statuses = <({String? value, String label})>[
      (value: null, label: 'Any status'),
      (value: 'OPEN', label: 'Open'),
      (value: 'ACTION_PENDING', label: 'Action pending'),
      (value: 'ACTION_SUBMITTED', label: 'Action submitted'),
      (value: 'VERIFICATION_PENDING', label: 'Verification'),
      (value: 'REOPENED', label: 'Reopened'),
      (value: 'ESCALATED', label: 'Escalated'),
      (value: 'OVERDUE', label: 'Overdue'),
      (value: 'CLOSED', label: 'Closed'),
      (value: 'WAIVED', label: 'Waived'),
    ];
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: 'Severity',
            small: true,
            trailing: FilterChip(
              label: const Text('Overdue only'),
              avatar: Icon(
                Icons.alarm_rounded,
                size: 16,
                color: _overdue ? Colors.white : AppColors.inkSoft,
              ),
              selected: _overdue,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _overdue ? Colors.white : AppColors.inkSoft,
              ),
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() {
                _overdue = v;
                _page = 0;
              }),
            ),
          ),
          const SizedBox(height: 6),
          ProChipBar(
            labels: [for (final o in opts) o.label],
            selected: opts.indexWhere((o) => o.value == _severity),
            onSelected: (i) => setState(() {
              _severity = opts[i].value;
              _page = 0;
            }),
            bleed: 0,
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Status', small: true),
          const SizedBox(height: 8),
          ProChipBar(
            labels: [for (final o in statuses) o.label],
            selected: statuses.indexWhere((o) => o.value == _status),
            onSelected: (i) => setState(() {
              _status = statuses[i].value;
              _page = 0;
            }),
            bleed: 0,
          ),
        ],
      ),
    ];
  }

  void _open(AuditFinding f) {
    final id = f.id;
    if (id == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => FindingDetailScreen(findingId: id),
        ))
        .then((_) {
      ref.invalidate(findingsForExecutionProvider);
      ref.invalidate(findingsProvider);
    });
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding, required this.onTap});
  final AuditFinding finding;
  final VoidCallback onTap;

  static String? _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('dd MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final due = _fmt(finding.dueDate);
    final sev = severityTone(finding.severity);
    return ProListRow(
      leading: ProIconWell(icon: Icons.report_problem_rounded, color: sev.color),
      title: finding.title ?? finding.code ?? 'Finding',
      titleMaxLines: 2,
      subtitle: (finding.description ?? '').isNotEmpty ? finding.description : null,
      meta: due == null ? null : 'Due $due',
      pill: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SeverityChip(severity: finding.severity),
          const SizedBox(height: 4),
          FindingStatusChip(status: finding.status),
        ],
      ),
      onTap: onTap,
    );
  }
}
