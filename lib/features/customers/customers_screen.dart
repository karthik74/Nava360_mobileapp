import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text_formatters.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/navigation/mobile_menu_config.dart';
import '../auth/auth_controller.dart';
import '../tasks/team_tasks_screen.dart';
import '../tasks/tasks_screen.dart';
import 'customer_detail_screen.dart';
import 'customer_models.dart';
import 'customer_repository.dart';

/// Customers matching the current search query (branch-scoped server-side).
final customerSearchProvider =
    FutureProvider.autoDispose.family<List<Customer>, String>((ref, query) {
  return ref.watch(customerRepositoryProvider).search(query);
});

/// Customer-first Tasks tab: pick a customer, then perform a task for them.
/// A toggle keeps the existing "My tasks" view one tap away.
class CustomerTasksHub extends ConsumerStatefulWidget {
  const CustomerTasksHub({super.key});

  @override
  ConsumerState<CustomerTasksHub> createState() => _CustomerTasksHubState();
}

class _CustomerTasksHubState extends ConsumerState<CustomerTasksHub> {
  int _tab = 0;

  void _select(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    // Managers holding TASK_VIEW get a third view: their team's tasks.
    final user = ref.watch(authUserProvider);
    final showTeam =
        isManagerUser(user) && (user?.hasPermission('TASK_VIEW') ?? false);
    final tab = (!showTeam && _tab == 2) ? 1 : _tab;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(
        index: tab,
        children: [
          _CustomersView(
            header: _HubToggle(current: 0, showTeam: showTeam, onChanged: _select),
          ),
          TasksScreen(
            header: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _HubToggle(current: 1, showTeam: showTeam, onChanged: _select),
            ),
          ),
          if (showTeam)
            TeamTasksScreen(
              header: _HubToggle(current: 2, showTeam: showTeam, onChanged: _select),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _HubToggle extends StatelessWidget {
  const _HubToggle({
    required this.current,
    required this.onChanged,
    this.showTeam = false,
  });
  final int current;
  final ValueChanged<int> onChanged;
  /// Adds the manager-only "Team" segment.
  final bool showTeam;

  /// Deep-surface segmented switch — sits inside the hero of the Customers,
  /// My tasks and Team views (Customers.dc.html / Tasks.dc.html).
  @override
  Widget build(BuildContext context) {
    return ProHeroSegmented(
      labels: [
        'Customers',
        'My tasks',
        if (showTeam) 'Team',
      ],
      icons: const [
        Icons.people_alt_rounded,
        Icons.task_alt_rounded,
        Icons.groups_rounded,
      ],
      selected: current,
      onChanged: onChanged,
    );
  }
}

class _CustomersView extends ConsumerStatefulWidget {
  const _CustomersView({required this.header});
  final Widget header;

  @override
  ConsumerState<_CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends ConsumerState<_CustomersView> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  /// Client-side quick filter over the loaded list:
  /// 0 all · 1 active · 2 inactive · 3 no location pinned.
  int _filter = 0;

  /// false = server order, true = A–Z by name (list already in memory).
  bool _sortAz = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value);
    });
  }

  bool _matches(Customer c, int filter) {
    switch (filter) {
      case 1:
        return c.isActive;
      case 2:
        return !c.isActive;
      case 3:
        return !c.hasLocation;
      default:
        return true;
    }
  }

  void _open(Customer c) {
    // Push onto the ROOT navigator so the detail screen covers the HomeShell
    // chrome — otherwise the bottom nav bar overlaps the "Perform task" button.
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customerId: c.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final async = ref.watch(customerSearchProvider(_query));
    final all = async.valueOrNull ?? const <Customer>[];
    final active = all.where((c) => c.isActive).length;
    final inactive = all.length - active;
    final noPin = all.where((c) => !c.hasLocation).length;
    const filterNames = [
      'All customers',
      'Active customers',
      'Inactive customers',
      'Without a location pin',
    ];

    return ProPage(
      topInset: mq.padding.top,
      clearNav: true,
      onRefresh: () async => ref.invalidate(customerSearchProvider(_query)),
      hero: ProHero(
        title: 'Customers',
        subtitle: 'Pick a customer to perform a task for them',
        overlap: _CustomerSearchField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
        ),
        children: [
          widget.header,
          ProHeroStats(stats: [
            ProStat(
              label: 'Customers',
              value: async.hasValue ? '${all.length}' : '—',
              sub: _query.isEmpty ? 'in your branch' : 'matching search',
              dot: Colors.white,
              selected: _filter == 0 && async.hasValue,
              onTap: () => setState(() => _filter = 0),
            ),
            ProStat(
              label: 'Active',
              value: async.hasValue ? '$active' : '—',
              sub: 'of ${all.length}',
              dot: AppColors.live,
              selected: _filter == 1,
              onTap: () => setState(() => _filter = _filter == 1 ? 0 : 1),
            ),
            ProStat(
              label: 'Inactive',
              value: async.hasValue ? '$inactive' : '—',
              sub: 'closed or paused',
              dot: const Color(0xFFB3C0C3),
              selected: _filter == 2,
              onTap: () => setState(() => _filter = _filter == 2 ? 0 : 2),
            ),
          ]),
        ],
      ),
      children: [
        ProChipBar(
          labels: const ['All', 'Active', 'Inactive', 'No location'],
          counts: async.hasValue ? [all.length, active, inactive, noPin] : null,
          selected: _filter,
          onSelected: (i) => setState(() => _filter = i),
          bleed: 0,
        ),
        async.when(
          data: (customers) {
            if (customers.isEmpty) {
              return ProEmpty(
                icon: Icons.person_search_rounded,
                title: _query.isEmpty ? 'No customers yet' : 'No matches',
                message: _query.isEmpty
                    ? 'No customers available in your branch yet.'
                    : 'No customers match “$_query”.',
              );
            }
            final shown = customers.where((c) => _matches(c, _filter)).toList();
            if (_sortAz) {
              shown.sort((a, b) => a.customerName
                  .toLowerCase()
                  .compareTo(b.customerName.toLowerCase()));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(
                  title: '${filterNames[_filter]} · ${shown.length}',
                  small: true,
                  trailing: TextButton.icon(
                    onPressed: () => setState(() => _sortAz = !_sortAz),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: AppColors.inkSoft,
                    ),
                    icon: const Icon(Icons.sort_rounded, size: 17),
                    label: Text(_sortAz ? 'A–Z' : 'Default order'),
                  ),
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  const ProEmpty(
                    icon: Icons.filter_alt_off_rounded,
                    title: 'Nothing in this filter',
                    message: 'Pick another filter above to see more customers.',
                  )
                else
                  ProListGroup(
                    dividerIndent: 66,
                    children: [
                      for (final c in shown)
                        _CustomerRow(customer: c, onTap: () => _open(c)),
                    ],
                  ),
              ],
            );
          },
          loading: () => const AppLoadingBlock(height: 160),
          error: (err, _) => AppErrorPanel(
            message: err.toString(),
            onRetry: () => ref.invalidate(customerSearchProvider(_query)),
          ),
        ),
      ],
    );
  }
}

/// [ProSearchField] look (raised, 50px) that keeps the customer search's
/// title-case formatter.
class _CustomerSearchField extends StatelessWidget {
  const _CustomerSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

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
          onChanged: onChanged,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Name, customer code or mobile',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: v.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});
  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final sub = [
      if (c.customerCode != null && c.customerCode!.isNotEmpty) c.customerCode!,
      if (c.branchName != null && c.branchName!.isNotEmpty) c.branchName!,
      if (c.mobileNumber != null && c.mobileNumber!.isNotEmpty) c.mobileNumber!,
    ].join(' · ');
    return ProListRow(
      leading: ProAvatar(
        name: c.customerName,
        size: 42,
        dot: c.isActive ? null : const Color(0xFFB3C0C3),
      ),
      title: c.customerName,
      subtitle: sub.isEmpty ? null : sub,
      meta: c.hasLocation ? null : 'No location pinned',
      pill: c.isActive
          ? ProPill.ok('Active')
          : ProPill.neutral(_statusLabel(c.status ?? 'INACTIVE')),
      onTap: onTap,
    );
  }

  static String _statusLabel(String raw) {
    final s = raw.replaceAll('_', ' ').trim().toLowerCase();
    if (s.isEmpty) return 'Inactive';
    return s[0].toUpperCase() + s.substring(1);
  }
}
