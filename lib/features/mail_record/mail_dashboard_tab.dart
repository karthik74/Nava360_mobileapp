import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'mail_list_screen.dart' show mailBranchesProvider, mailMyBranchIdProvider;
import 'mail_models.dart';
import 'mail_repository.dart';

final mailDashboardProvider = FutureProvider.autoDispose.family<MailDashboard, int>((ref, branchId) {
  return ref.watch(mailRepositoryProvider).dashboardForBranch(branchId);
});

/// Branch dropdown used by the Mail Record tabs. Starts on the signed-in user's own branch; only a full-access
/// user (`DATA_SCOPE_ALL`) may pick any branch (and, when [allowAll], "All branches"). Everyone else is limited to
/// their own branch(es) and the picker is locked when there is only one.
class MailBranchSelector extends ConsumerWidget {
  const MailBranchSelector({super.key, required this.value, required this.onChanged, this.allowAll = false});
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool allowAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final isFull = user?.hasPermission('DATA_SCOPE_ALL') ?? false;
    final assigned = user?.branchIds ?? const <int>{};
    return ref.watch(mailBranchesProvider).when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          data: (all) {
            var branches = isFull || assigned.isEmpty ? all : all.where((b) => assigned.contains(b.id)).toList();
            if (!isFull && branches.isEmpty && value != null) {
              branches = all.where((b) => b.id == value).toList();
            }
            final locked = !isFull && branches.length <= 1;
            return DropdownButtonFormField<int?>(
              isExpanded: true,
              value: branches.any((b) => b.id == value) ? value : null,
              decoration: InputDecoration(
                labelText: 'Branch',
                suffixIcon: locked ? const Icon(Icons.lock_outline_rounded, size: 16) : null,
              ),
              items: [
                if (isFull && allowAll) const DropdownMenuItem<int?>(value: null, child: Text('All branches')),
                for (final b in branches) DropdownMenuItem<int?>(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: locked ? null : onChanged,
            );
          },
        );
  }
}

/// Mail Record dashboard - mirrors web `MailDashboardTab`: FY / today counts and recent outward / inward records
/// for one branch (`GET /api/admin/mail/records/dashboard/branch/{id}`).
class MailDashboardTab extends ConsumerStatefulWidget {
  const MailDashboardTab({super.key, required this.bottomPadding});
  final double bottomPadding;

  @override
  ConsumerState<MailDashboardTab> createState() => _MailDashboardTabState();
}

class _MailDashboardTabState extends ConsumerState<MailDashboardTab> {
  int? _branchId;
  bool _seeded = false;
  bool _outward = true;

  @override
  Widget build(BuildContext context) {
    final my = ref.watch(mailMyBranchIdProvider);
    if (!_seeded && my.hasValue) {
      _branchId = my.value;
      _seeded = true;
    }
    final df = DateFormat('d MMM yyyy');
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        if (_branchId != null) ref.invalidate(mailDashboardProvider(_branchId!));
      },
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          MailBranchSelector(value: _branchId, onChanged: (v) => setState(() => _branchId = v)),
          const SizedBox(height: 12),
          if (!_seeded)
            const AppLoadingBlock(height: 160)
          else if (_branchId == null)
            const AppEmptyState(icon: Icons.dashboard_rounded, message: 'Pick a branch to see its mail summary.')
          else
            ref.watch(mailDashboardProvider(_branchId!)).when(
                  loading: () => const AppLoadingBlock(height: 160),
                  error: (e, _) => AppErrorPanel(
                      message: e.toString(), onRetry: () => ref.invalidate(mailDashboardProvider(_branchId!))),
                  data: (d) {
                    final rows = _outward ? d.recentOutward : d.recentInward;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          _kpi('Outward (${d.fyLabel})', d.outwardFyCount, AppColors.primary),
                          const SizedBox(width: 10),
                          _kpi('Inward (${d.fyLabel})', d.inwardFyCount, AppColors.success),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          _kpi('Today outward', d.todayOutwardCount, AppColors.warning),
                          const SizedBox(width: 10),
                          _kpi('Today inward', d.todayInwardCount, AppColors.info),
                        ]),
                        const SizedBox(height: 16),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('Recent outward')),
                            ButtonSegment(value: false, label: Text('Recent inward')),
                          ],
                          selected: {_outward},
                          onSelectionChanged: (s) => setState(() => _outward = s.first),
                        ),
                        const SizedBox(height: 10),
                        if (rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: Text('No records', style: TextStyle(color: AppColors.muted))),
                          ),
                        for (var i = 0; i < rows.length; i++)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              border: Border.all(color: AppColors.hairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${i + 1}. ${_outward ? 'To' : 'From'}: ${rows[i].branchLabel ?? rows[i].otherParty ?? '—'}',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(rows[i].date == null ? '—' : df.format(rows[i].date!),
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                if ((rows[i].documents ?? '').isNotEmpty)
                                  Text(rows[i].documents!, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _kpi(String label, int value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
