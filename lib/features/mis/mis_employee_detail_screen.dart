// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Employee Detail (route /mis/employees/:id). One employee: record +
//  personal, with reporting, posting, contact and personal sections. Ports
//  EmployeeDetailScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

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

class MisEmployeeDetailScreen extends ConsumerWidget {
  const MisEmployeeDetailScreen({super.key, required this.empId});
  final String empId;

  Future<void> _launch(String scheme, String? value) async {
    if (value == null || value.trim().isEmpty) return;
    await launchUrl(Uri.parse('$scheme:$value'),
        mode: LaunchMode.externalApplication);
  }

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  /// "2019-03-14" → "7y 6m" (time elapsed until today); "—" when unknown.
  static String _tenure(String? iso) {
    if (iso == null || iso.length < 10) return '—';
    final from = DateTime.tryParse(iso.substring(0, 10));
    if (from == null) return '—';
    final now = DateTime.now();
    var months = (now.year - from.year) * 12 + now.month - from.month;
    if (now.day < from.day) months--;
    if (months < 0) return '—';
    final y = months ~/ 12;
    final m = months % 12;
    if (y == 0) return '${m}m';
    return '${y}y ${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empAsync = ref.watch(misEmployeeProvider(empId));
    final personalAsync = ref.watch(misEmployeePersonalProvider(empId));

    return Scaffold(
      appBar: AppBar(title: const Text('Employee')),
      body: empAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AppLoadingBlock(height: 300),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misEmployeeProvider(empId)),
          ),
        ),
        data: (emp) {
          final personal = personalAsync.asData?.value;
          final hasManager =
              emp.reportsToEmpId != null && emp.reportsToEmpId!.isNotEmpty;
          void openManager() => context.push(
              '/mis/employees/${Uri.encodeComponent(emp.reportsToEmpId!)}');
          return ProPage(
            hero: _hero(context, emp, personal,
                onManager: hasManager ? openManager : null),
            children: [
              _section('Reporting', [
                _KvRow(
                  'Reports to',
                  emp.reportsToName,
                  icon: Icons.chevron_right_rounded,
                  onTap: hasManager ? openManager : null,
                ),
                _KvRow('Manager ID', emp.reportsToEmpId),
              ]),
              _section('Posting', [
                _KvRow('Branch', emp.branch),
                _KvRow('Area', emp.area),
                _KvRow('Division', emp.division),
                _KvRow('Region', emp.region),
                _KvRow('Joined', misPrettyDate(personal?.hireDate)),
                _KvRow('Posted since', misPrettyDate(emp.postedSince)),
              ]),
              _section('Contact & role', [
                _KvRow('Mobile', emp.mobile,
                    icon: Icons.call_rounded,
                    onTap: () => _launch('tel', emp.mobile)),
                _KvRow('Email', emp.email,
                    icon: Icons.mail_outline_rounded,
                    onTap: () => _launch('mailto', emp.email)),
                _KvRow('Emergency phone', emp.emergencyPhone,
                    icon: Icons.call_rounded,
                    onTap: () => _launch('tel', emp.emergencyPhone)),
                _KvRow('Role', emp.role),
                _KvRow('Designation', emp.designation),
                _KvRow('Gender', emp.gender),
              ]),
              _section(
                'Personal',
                [
                  _KvRow('Date of birth', misPrettyDate(personal?.dateOfBirth)),
                  _KvRow('Joining date', misPrettyDate(personal?.hireDate)),
                  _KvRow('PAN', personal?.pan),
                  _KvRow(
                      'Aadhaar (last 4)',
                      personal?.aadhaarLast4 != null &&
                              personal!.aadhaarLast4!.isNotEmpty
                          ? '••••${personal.aadhaarLast4}'
                          : null),
                ],
                trailing: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: AppColors.muted),
                    SizedBox(width: 4),
                    Text('Private',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(
    BuildContext context,
    Employee emp,
    EmployeePersonal? personal, {
    VoidCallback? onManager,
  }) {
    final initials = emp.displayName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    final hasStatus = emp.status != null && emp.status!.isNotEmpty;
    return ProHero(
      overlap: ProKpiStrip(cells: [
        ProKpi(value: _tenure(personal?.hireDate), label: 'Service'),
        ProKpi(value: _tenure(emp.postedSince), label: 'In this posting'),
        ProKpi(
          value: _has(emp.role) ? emp.role! : '—',
          label: _has(emp.designation) ? emp.designation! : 'Role',
        ),
      ]),
      children: [
        ProHeroIdentity(
          name: emp.displayName,
          role: emp.designation ?? emp.role ?? '—',
          initials: initials.isEmpty ? '?' : initials,
          ringColor: emp.isWorking ? AppColors.live : Colors.white38,
          tags: [
            ProHeroTag(emp.empId, icon: Icons.badge_outlined),
            if (hasStatus)
              ProHeroTag(emp.status!,
                  tone: emp.isWorking ? ProTagTone.ok : ProTagTone.neutral),
            if (_has(emp.postedSince))
              ProHeroTag('Since ${misPrettyDate(emp.postedSince)}'),
          ],
        ),
        if (_has(emp.reportsToName))
          ProLiveLine(
            text: 'Reports to ${emp.reportsToName}'
                '${_has(emp.branch) ? ' · ${emp.branch}' : ''}',
            color: emp.isWorking ? AppColors.live : Colors.white54,
          ),
        ProHeroActions(actions: [
          ProAction(
            icon: Icons.call_rounded,
            label: 'Call',
            primary: true,
            onTap: _has(emp.mobile) ? () => _launch('tel', emp.mobile) : null,
          ),
          ProAction(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            onTap: _has(emp.email) ? () => _launch('mailto', emp.email) : null,
          ),
          ProAction(
            icon: Icons.emergency_outlined,
            label: 'Emergency',
            onTap: _has(emp.emergencyPhone)
                ? () => _launch('tel', emp.emergencyPhone)
                : null,
          ),
          ProAction(
            icon: Icons.account_tree_outlined,
            label: 'Manager',
            onTap: onManager,
          ),
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows, {Widget? trailing}) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(title: title, trailing: trailing),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(
                        top: BorderSide(color: AppColors.hairlineSoft)),
              ),
              child: rows[i],
            ),
        ],
      ),
    );
  }
}

/// Label / value row; tappable values (call, mail, manager) use the brand
/// colour with a small trailing icon.
class _KvRow extends StatelessWidget {
  const _KvRow(this.label, this.value, {this.onTap, this.icon});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.trim().isNotEmpty;
    final tappable = has && onTap != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              has ? value! : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: tappable ? AppColors.primary : AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (tappable && icon != null) ...[
            const SizedBox(width: 6),
            Icon(icon, size: 16, color: AppColors.primary),
          ],
        ],
      ),
    );
    if (!tappable) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
