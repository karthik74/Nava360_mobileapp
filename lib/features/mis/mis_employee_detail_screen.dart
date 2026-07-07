// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Employee Detail (route /mis/employees/:id). One employee: record +
//  personal, with reporting, posting, contact and personal sections. Ports
//  EmployeeDetailScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';

class MisEmployeeDetailScreen extends ConsumerWidget {
  const MisEmployeeDetailScreen({super.key, required this.empId});
  final String empId;

  Future<void> _launch(String scheme, String? value) async {
    if (value == null || value.trim().isEmpty) return;
    await launchUrl(Uri.parse('$scheme:$value'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empAsync = ref.watch(misEmployeeProvider(empId));
    final personalAsync = ref.watch(misEmployeePersonalProvider(empId));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Employee')),
      body: empAsync.when(
        loading: () => const AppLoadingBlock(height: 300),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misEmployeeProvider(empId)),
          ),
        ),
        data: (emp) {
          final personal = personalAsync.asData?.value;
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 14, 16, MediaQuery.of(context).padding.bottom + 24),
            children: [
              _header(emp),
              const SizedBox(height: 16),
              _section('Reporting', [
                _field(
                  'Reports to',
                  emp.reportsToName,
                  onTap: emp.reportsToEmpId != null &&
                          emp.reportsToEmpId!.isNotEmpty
                      ? () => context.push(
                          '/mis/employees/${Uri.encodeComponent(emp.reportsToEmpId!)}')
                      : null,
                ),
                _field('Manager ID', emp.reportsToEmpId),
              ]),
              _section('Posting', [
                _field('Branch', emp.branch),
                _field('Area', emp.area),
                _field('Division', emp.division),
                _field('Region', emp.region),
                _field('Joined', misPrettyDate(personal?.hireDate)),
                _field('Posted since', misPrettyDate(emp.postedSince)),
              ]),
              _section('Contact & role', [
                _field('Mobile', emp.mobile,
                    onTap: () => _launch('tel', emp.mobile)),
                _field('Email', emp.email,
                    onTap: () => _launch('mailto', emp.email)),
                _field('Emergency phone', emp.emergencyPhone,
                    onTap: () => _launch('tel', emp.emergencyPhone)),
                _field('Role', emp.role),
                _field('Designation', emp.designation),
                _field('Gender', emp.gender),
              ]),
              _section('Personal', [
                _field('Date of birth', misPrettyDate(personal?.dateOfBirth)),
                _field('Joining date', misPrettyDate(personal?.hireDate)),
                _field('PAN', personal?.pan),
                _field(
                    'Aadhaar (last 4)',
                    personal?.aadhaarLast4 != null &&
                            personal!.aadhaarLast4!.isNotEmpty
                        ? '••••${personal.aadhaarLast4}'
                        : null),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _header(Employee emp) {
    final initials = emp.displayName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(initials.isEmpty ? '?' : initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp.displayName,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                          '${emp.empId} · ${emp.designation ?? emp.role ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.muted)),
                    ),
                    if (emp.status != null && emp.status!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      StatusPill(
                        label: emp.status!,
                        color: emp.isWorking
                            ? AppColors.success
                            : AppColors.muted,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 22,
              runSpacing: 14,
              children: fields,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String? value, {VoidCallback? onTap}) {
    final has = value != null && value.trim().isNotEmpty;
    final tappable = has && onTap != null;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: tappable ? onTap : null,
            child: Text(
              has ? value : '—',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tappable ? AppColors.primary : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
