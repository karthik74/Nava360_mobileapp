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

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(misEmployeeListProvider(_query));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Directory')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(misEmployeeListProvider(_query));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              16, 14, 16, MediaQuery.of(context).padding.bottom + 24),
          children: [
            TextField(
              controller: _controller,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search name, code, branch, area…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            listAsync.when(
              loading: () => const AppLoadingBlock(height: 200),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(misEmployeeListProvider(_query)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const MisInlineEmpty(
                      'No employees match your search.');
                }
                return Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('${rows.length} shown',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                    ),
                    const SizedBox(height: 8),
                    for (final r in rows) ...[
                      _EmployeeCard(row: r, onCall: () => _call(r.mobile)),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.row, required this.onCall});
  final EmployeeRow row;
  final VoidCallback onCall;

  String get _initials {
    final parts = (row.name ?? row.empId).trim().split(RegExp(r'\s+'));
    final l = parts.where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join();
    return l.isEmpty ? '?' : l.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = (row.mobile ?? '').replaceAll(RegExp(r'\D'), '').length >= 10;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
            '/mis/employees/${Uri.encodeComponent(row.empId)}'),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          shadow: AppShadows.soft,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(_initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name ?? row.empId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    Text('${row.empId} · ${row.displayDesignation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.muted)),
                    if (row.location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(row.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.inkSoft)),
                    ],
                  ],
                ),
              ),
              if (hasPhone)
                IconButton(
                  onPressed: onCall,
                  icon: const Icon(Icons.phone_rounded,
                      size: 20, color: AppColors.success),
                  tooltip: 'Call ${row.name ?? row.empId}',
                )
              else
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
