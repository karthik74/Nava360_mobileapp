import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(
        index: _tab,
        children: [
          _CustomersView(
            header: _HubToggle(current: 0, onChanged: _select),
          ),
          TasksScreen(
            header: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _HubToggle(current: 1, onChanged: _select),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubToggle extends StatelessWidget {
  const _HubToggle({required this.current, required this.onChanged});
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          _seg('Customers', Icons.people_alt_rounded, 0),
          _seg('My tasks', Icons.task_alt_rounded, 1),
        ],
      ),
    );
  }

  Widget _seg(String label, IconData icon, int index) {
    final selected = current == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: selected ? Colors.white : AppColors.muted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final async = ref.watch(customerSearchProvider(_query));

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white.withOpacity(0.85),
      onRefresh: () async => ref.invalidate(customerSearchProvider(_query)),
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          mq.padding.top + 1,
          16,
          mq.padding.bottom + AppChrome.bottomNavHeight + 10,
        ),
        children: [
          widget.header,
          const SizedBox(height: 12),
          const AppSectionHeader(
            title: 'Customers',
            subtitle: 'Pick a customer to perform a task for them',
          ),
          const SizedBox(height: 14),
          _CustomerSearchField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            onClear: () {
              _searchCtrl.clear();
              _onSearchChanged('');
            },
          ),
          const SizedBox(height: 16),
          async.when(
            data: (customers) {
              if (customers.isEmpty) {
                return AppEmptyState(
                  icon: Icons.person_search_rounded,
                  message: _query.isEmpty
                      ? 'No customers available in your branch yet.'
                      : 'No customers match “$_query”.',
                );
              }
              return Column(
                children: [
                  for (final c in customers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        // Push onto the ROOT navigator so the detail screen
                        // covers the HomeShell chrome — otherwise the bottom
                        // nav bar overlaps the "Perform task" button.
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CustomerDetailScreen(customerId: c.id),
                          ),
                        ),
                        child: _CustomerCard(customer: c),
                      ),
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
      ),
    );
  }
}

class _CustomerSearchField extends StatelessWidget {
  const _CustomerSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.primary,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search by name, code or mobile…',
                hintStyle: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppColors.muted,
              onPressed: onClear,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          UserAvatar(name: c.customerName, size: 44, radius: 13),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (!c.isActive) ...[
                      const SizedBox(width: 6),
                      _StatusDot(label: c.status ?? 'INACTIVE'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    if (c.customerCode != null && c.customerCode!.isNotEmpty)
                      _meta(Icons.tag_rounded, c.customerCode!),
                    if (c.mobileNumber != null && c.mobileNumber!.isNotEmpty)
                      _meta(Icons.call_outlined, c.mobileNumber!),
                    if (c.branchName != null && c.branchName!.isNotEmpty)
                      _meta(Icons.store_mall_directory_outlined, c.branchName!),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: AppColors.muted),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.5, color: AppColors.muted),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.muted.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppColors.muted,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
