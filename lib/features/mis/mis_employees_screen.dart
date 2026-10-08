// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Contacts / Employee Directory (route /mis/employees). Everyone in the
//  caller's scope, searchable, with click-to-call. Ports
//  EmployeeDirectoryScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';

class MisEmployeesScreen extends ConsumerStatefulWidget {
  const MisEmployeesScreen({super.key});

  @override
  ConsumerState<MisEmployeesScreen> createState() => _MisEmployeesScreenState();
}

class _MisEmployeesScreenState extends ConsumerState<MisEmployeesScreen> {
  final _controller = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  Future<void> _call(String? mobile) async {
    final digits = (mobile ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      await launchUrl(
          Uri.parse('tel:${digits.substring(digits.length - 10)}'),
          mode: LaunchMode.externalApplication);
    }
  }

  static bool _hasPhone(EmployeeRow r) =>
      (r.mobile ?? '').replaceAll(RegExp(r'\D'), '').length >= 10;

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(misEmployeeListProvider(_query));
    final loaded = listAsync.asData?.value;

    // Hero figures come from the list that is already loaded.
    final people = loaded?.length;
    final branches = loaded
        ?.map((r) => r.branch ?? '')
        .where((b) => b.isNotEmpty)
        .toSet()
        .length;
    final callable = loaded?.where(_hasPhone).length;
    String n(int? v) => v == null ? '—' : misNum(v);

    return Scaffold(
      appBar: AppBar(title: const Text('MIS')),
      body: ProPage(
        onRefresh: () async {
          ref.invalidate(misEmployeeListProvider(_query));
        },
        hero: ProHero(
          title: 'Directory',
          subtitle: people == null
              ? 'Everyone in your scope'
              : _query.isEmpty
                  ? 'MIS · ${misNum(people)} people'
                  : 'MIS · ${misNum(people)} match “$_query”',
          overlap: ProSearchField(
            raised: true,
            controller: _controller,
            onChanged: _onChanged,
            hint: 'Search name, code, branch, area…',
            onClear: () {
              _debounce?.cancel();
              setState(() => _query = '');
            },
          ),
          children: [
            ProHeroStats(stats: [
              ProStat(
                  label: 'People',
                  value: n(people),
                  sub: 'in scope',
                  dot: AppColors.live),
              ProStat(
                  label: 'Branches',
                  value: n(branches),
                  sub: 'covered',
                  dot: const Color(0xFF7FD3E3)),
              ProStat(
                  label: 'Callable',
                  value: n(callable),
                  sub: 'with mobile',
                  dot: const Color(0xFFF2B347)),
            ]),
          ],
        ),
        children: [
          listAsync.when(
            loading: () => const AppLoadingBlock(height: 200),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(misEmployeeListProvider(_query)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const ProEmpty(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  message: 'No employees match your search.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title: _query.isEmpty ? 'Everyone' : 'Results',
                    small: true,
                    trailing: Text('${rows.length} shown',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.muted)),
                  ),
                  const SizedBox(height: 8),
                  ProListGroup(
                    dividerIndent: 66,
                    children: [
                      for (final r in rows)
                        _EmployeeRowTile(
                          row: r,
                          hasPhone: _hasPhone(r),
                          onCall: () => _call(r.mobile),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmployeeRowTile extends StatelessWidget {
  const _EmployeeRowTile({
    required this.row,
    required this.hasPhone,
    required this.onCall,
  });
  final EmployeeRow row;
  final bool hasPhone;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final name = row.name ?? row.empId;
    return ProListRow(
      leading: ProAvatar(name: name, size: 42),
      title: name,
      subtitle: '${row.empId} · ${row.displayDesignation}',
      meta: row.location.isNotEmpty ? row.location : null,
      onTap: () =>
          context.push('/mis/employees/${Uri.encodeComponent(row.empId)}'),
      chevron: !hasPhone,
      trailing: hasPhone
          ? Tooltip(
              message: 'Call $name',
              child: Material(
                color: AppColors.successTint,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onCall,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.phone_rounded,
                        size: 19, color: AppColors.success),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
