import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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
          error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
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
                prefixIcon: const Icon(Icons.store_mall_directory_outlined, size: 19),
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
  const MailDashboardTab({super.key, required this.bottomPadding, this.nav});

  /// Extra space below the content (the system inset is added on top).
  final double bottomPadding;

  /// Section switcher shown right under the hero.
  final Widget? nav;

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
    final dashAsync = _seeded && _branchId != null ? ref.watch(mailDashboardProvider(_branchId!)) : null;
    final d = dashAsync?.valueOrNull;
    final branchLabel = ref
        .watch(mailBranchesProvider)
        .valueOrNull
        ?.where((b) => b.id == _branchId)
        .map((b) => b.label)
        .firstOrNull;
    final totalFy = d == null ? 0 : d.outwardFyCount + d.inwardFyCount;

    return ProPage(
      onRefresh: () async {
        if (_branchId != null) ref.invalidate(mailDashboardProvider(_branchId!));
      },
      padding: EdgeInsets.fromLTRB(16, 16, 16, widget.bottomPadding),
      hero: ProHero(
        title: 'Mail record',
        subtitle: 'Admin tools${branchLabel == null ? '' : ' · $branchLabel'}',
        overlap: ProKpiStrip(cells: [
          ProKpi(
            value: d == null ? '—' : '${d.todayOutwardCount}',
            label: 'Today outward',
            valueColor: AppColors.warning,
          ),
          ProKpi(
            value: d == null ? '—' : '${d.todayInwardCount}',
            label: 'Today inward',
            valueColor: AppColors.info,
          ),
        ]),
        children: [
          ProHeroStats(stats: [
            ProStat(
              label: 'Outward',
              value: d == null ? '—' : '${d.outwardFyCount}',
              sub: d == null ? 'this year' : d.fyLabel,
              dot: const Color(0xFFF2B347),
            ),
            ProStat(
              label: 'Inward',
              value: d == null ? '—' : '${d.inwardFyCount}',
              sub: d == null ? 'this year' : d.fyLabel,
              dot: const Color(0xFF9FCBD5),
            ),
          ]),
          if (d != null && totalFy > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProStackBar(parts: [
                  MapEntry(d.outwardFyCount.toDouble(), const Color(0xFFF2B347)),
                  MapEntry(d.inwardFyCount.toDouble(), const Color(0xFF9FCBD5)),
                ]),
                const SizedBox(height: 8),
                Text(
                  '$totalFy entries this year · ${(d.outwardFyCount * 100 / totalFy).round()}% outward',
                  style: AppText.number.copyWith(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
        ],
      ),
      children: [
        if (widget.nav != null) widget.nav!,
        MailBranchSelector(value: _branchId, onChanged: (v) => setState(() => _branchId = v)),
        if (!_seeded)
          const AppLoadingBlock(height: 160)
        else if (_branchId == null)
          const ProEmpty(
            icon: Icons.dashboard_rounded,
            title: 'Pick a branch',
            message: 'Pick a branch to see its mail summary.',
          )
        else
          dashAsync!.when(
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
                message: e.toString(), onRetry: () => ref.invalidate(mailDashboardProvider(_branchId!))),
            data: (d) {
              final rows = _outward ? d.recentOutward : d.recentInward;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProSectionHeader(title: 'Recent records'),
                  const SizedBox(height: 10),
                  ProChipBar(
                    labels: const ['Recent outward', 'Recent inward'],
                    counts: [d.recentOutward.length, d.recentInward.length],
                    selected: _outward ? 0 : 1,
                    onSelected: (i) => setState(() => _outward = i == 0),
                    bleed: 0,
                  ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    const ProEmpty(icon: Icons.mail_outline_rounded, title: 'No records')
                  else
                    ProListGroup(
                      children: [
                        for (final r in rows)
                          ProListRow(
                            dense: true,
                            leading: ProIconWell(
                              icon: _outward ? Icons.north_east_rounded : Icons.south_west_rounded,
                              color: _outward ? AppColors.warning : AppColors.info,
                            ),
                            title: '${_outward ? 'To' : 'From'}: ${r.branchLabel ?? r.otherParty ?? '—'}',
                            subtitle: (r.documents ?? '').isNotEmpty ? r.documents : null,
                            value: r.date == null ? '—' : df.format(r.date!),
                            valueColor: AppColors.muted,
                            chevron: false,
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
