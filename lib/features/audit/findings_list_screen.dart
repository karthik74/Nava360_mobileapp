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

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'audit_models.dart';
import 'audit_repository.dart';
import 'audit_widgets.dart';
import 'finding_detail_screen.dart';

class FindingsListScreen extends ConsumerStatefulWidget {
  const FindingsListScreen({super.key, this.executionId});

  /// When set, lists findings for that single execution. When null, shows the
  /// paged/filtered assigned findings list.
  final int? executionId;

  @override
  ConsumerState<FindingsListScreen> createState() => _FindingsListScreenState();
}

class _FindingsListScreenState extends ConsumerState<FindingsListScreen> {
  String? _severity;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Findings'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(findingsForExecutionProvider);
            ref.invalidate(findingsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 250));
          },
          child: widget.executionId != null
              ? _executionList(widget.executionId!)
              : _pagedList(),
        ),
      ),
    );
  }

  Widget _executionList(int execId) {
    final async = ref.watch(findingsForExecutionProvider(execId));
    return async.when(
      loading: () => _scroll([const AppLoadingBlock(height: 240)]),
      error: (e, __) => _scroll([
        AppErrorPanel(
          message: 'Could not load findings.\n$e',
          onRetry: () => ref.invalidate(findingsForExecutionProvider),
        ),
      ]),
      data: (rows) {
        if (rows.isEmpty) {
          return _scroll(const [
            AppEmptyState(
              icon: Icons.verified_rounded,
              message: 'No findings raised for this audit.',
            ),
          ]);
        }
        return _scroll([
          for (final f in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FindingCard(finding: f, onTap: () => _open(f)),
            ),
        ]);
      },
    );
  }

  Widget _pagedList() {
    final query =
        AuditFindingsQuery(severity: _severity, page: _page, size: 20);
    final async = ref.watch(findingsProvider(query));
    return async.when(
      loading: () => _scroll([
        _severityBar(),
        const SizedBox(height: 12),
        const AppLoadingBlock(height: 240),
      ]),
      error: (e, __) => _scroll([
        _severityBar(),
        const SizedBox(height: 12),
        AppErrorPanel(
          message: 'Could not load findings.\n$e',
          onRetry: () => ref.invalidate(findingsProvider),
        ),
      ]),
      data: (pageData) => _scroll([
        _severityBar(),
        const SizedBox(height: 12),
        if (pageData.content.isEmpty)
          const AppEmptyState(
            icon: Icons.verified_rounded,
            message: 'No findings match this filter.',
          )
        else ...[
          for (final f in pageData.content)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FindingCard(finding: f, onTap: () => _open(f)),
            ),
          if (pageData.totalPages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed:
                      _page > 0 ? () => setState(() => _page -= 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: AppColors.primary,
                  disabledColor: AppColors.hairline,
                ),
                Text('Page ${pageData.page + 1} of ${pageData.totalPages}',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkSoft)),
                IconButton(
                  onPressed: pageData.last
                      ? null
                      : () => setState(() => _page += 1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: AppColors.primary,
                  disabledColor: AppColors.hairline,
                ),
              ],
            ),
        ],
      ]),
    );
  }

  Widget _scroll(List<Widget> children) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: children,
      );

  Widget _severityBar() {
    const opts = <({String? value, String label})>[
      (value: null, label: 'All'),
      (value: 'HIGH', label: 'High'),
      (value: 'MODERATE', label: 'Moderate'),
      (value: 'LOW', label: 'Low'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in opts) ...[
            ChoiceChip(
              label: Text(o.label),
              selected: _severity == o.value,
              onSelected: (_) => setState(() {
                _severity = o.value;
                _page = 0;
              }),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
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

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, required this.onTap});
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
                  child: Text(
                    finding.title ?? finding.code ?? 'Finding',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SeverityChip(severity: finding.severity),
              ],
            ),
            if ((finding.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                finding.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                FindingStatusChip(status: finding.status),
                const Spacer(),
                if (due != null) ...[
                  const Icon(Icons.event_rounded,
                      size: 13, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    'Due $due',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
