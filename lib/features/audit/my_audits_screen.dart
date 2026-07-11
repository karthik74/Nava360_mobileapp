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

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
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
  (value: 'BM_ACTION_PENDING', label: 'Sent to BM'),
  (value: 'VERIFICATION_PENDING', label: 'BM Submitted'),
  (value: 'CLOSED', label: 'Closed'),
];

class MyAuditsScreen extends ConsumerStatefulWidget {
  const MyAuditsScreen({super.key});

  @override
  ConsumerState<MyAuditsScreen> createState() => _MyAuditsScreenState();
}

class _MyAuditsScreenState extends ConsumerState<MyAuditsScreen> {
  String? _status;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    // Auditors see only their own assigned audits; broader viewers get the
    // server's branch/hierarchy-scoped list (no auditorId filter).
    final isAuditorOnly = (user?.hasPermission('AUDIT_PERFORM') ?? false) &&
        !(user?.hasPermission('AUDIT_VIEW_ALL') ?? false) &&
        !(user?.hasPermission('AUDIT_VIEW_HIERARCHY') ?? false);
    final auditorId = isAuditorOnly ? user?.employeeId : null;

    final query = AuditPlansQuery(
      status: _status,
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
              const SizedBox(height: 14),
              async.when(
                loading: () => const AppLoadingBlock(height: 240),
                error: (e, __) => AppErrorPanel(
                  message: 'Could not load audits.\n$e',
                  onRetry: () => ref.invalidate(myAuditsProvider),
                ),
                data: (pageData) {
                  if (pageData.content.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.fact_check_rounded,
                      message:
                          'No audits found.\nAssigned branch audits will appear here.',
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
