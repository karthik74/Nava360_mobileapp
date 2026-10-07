import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/download_saver.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'payslips_models.dart';
import 'payslips_repository.dart';

final myPayrollsProvider =
    FutureProvider.autoDispose<List<PayrollRecord>>((ref) {
  return ref.watch(payslipsRepositoryProvider).getMyPayrolls();
});

/// Downloads [payroll]'s payslip PDF and saves it to the device's public
/// storage (Downloads on Android, the Files app on iOS) — not the app sandbox.
/// Surfaces progress/errors via snackbars. Returns true on success.
Future<bool> _downloadAndOpenPayslip(
  WidgetRef ref,
  BuildContext context,
  PayrollRecord payroll,
  String monthName,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text('Downloading payslip for $monthName ${payroll.year}…'),
      duration: const Duration(seconds: 2),
    ),
  );
  try {
    final bytes = await ref
        .read(payslipsRepositoryProvider)
        .downloadMyPayslip(payroll.id);

    final fileName = 'Payslip_${monthName}_${payroll.year}.pdf';
    final saved = await DownloadSaver.savePdf(fileName, bytes);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Saved to ${saved.locationLabel}'),
          duration: const Duration(seconds: 5),
          action: saved.canOpen
              ? SnackBarAction(label: 'OPEN', onPressed: saved.open)
              : null,
        ),
      );
    return true;
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Download failed: $e'),
        ),
      );
    return false;
  }
}

String _money(double v) => '₹${NumberFormat('#,##,###').format(v)}';

/// "PAID" → "Paid".
String _statusLabel(String s) {
  if (s.isEmpty) return s;
  final t = s.toLowerCase().replaceAll('_', ' ');
  return '${t[0].toUpperCase()}${t.substring(1)}';
}

class PayslipsScreen extends ConsumerWidget {
  const PayslipsScreen({super.key});

  String _monthName(int month) {
    final dt = DateTime(2000, month);
    return DateFormat('MMMM').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payrolls = ref.watch(myPayrollsProvider);

    PayrollRecord? latest;
    payrolls.whenData((list) {
      if (list.isNotEmpty) {
        final sorted = [...list]..sort((a, b) => (b.year * 12 + b.month).compareTo(a.year * 12 + a.month));
        latest = sorted.first;
      }
    });
    final last = latest;
    final lastNetSalary = last?.netSalary ?? 0;
    final totalPayslips = payrolls.when(
      data: (list) => list.length.toString(),
      loading: () => '—',
      error: (_, __) => '0',
    );

    final Widget heroTitle;
    if (last == null) {
      heroTitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'My payslips',
            style: TextStyle(
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.65,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            payrolls.isLoading
                ? 'Loading your salary slips…'
                : 'Monthly disbursements and deduction ledgers',
            style: const TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
        ],
      );
    } else {
      final monthLabel = '${_monthName(last.month)} ${last.year}';
      heroTitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Last net salary · $monthLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(lastNetSalary),
              style: const TextStyle(
                fontSize: 36,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (last.status.isNotEmpty)
                ProHeroTag(_statusLabel(last.status),
                    tone: ProTagTone.ok, icon: Icons.check_rounded),
              if (last.paymentDate != null)
                ProHeroTag('Paid on ${last.paymentDate}'),
              ProHeroTag('$totalPayslips payslips',
                  icon: Icons.receipt_long_rounded),
            ],
          ),
        ],
      );
    }

    final takePct = last == null || last.grossEarnings <= 0
        ? null
        : (last.netSalary / last.grossEarnings * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Payslips')),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myPayrollsProvider),
        gap: 22,
        hero: ProHero(
          titleWidget: heroTitle,
          overlap: last == null
              ? null
              : ProKpiStrip(
                  cells: [
                    ProKpi(value: _money(last.grossEarnings), label: 'Gross earnings'),
                    ProKpi(
                      value: _money(last.totalDeductions),
                      label: 'Deductions',
                      valueColor: AppColors.danger,
                    ),
                    ProKpi(
                      value: _money(last.netSalary),
                      label: takePct == null ? 'Net pay' : 'Net pay · $takePct%',
                      valueColor: AppColors.success,
                      progress: takePct == null ? null : takePct / 100,
                      color: AppColors.success,
                    ),
                  ],
                ),
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: payrolls.valueOrNull == null ||
                        payrolls.valueOrNull!.isEmpty
                    ? 'Salary slips'
                    : 'Salary slips · ${payrolls.valueOrNull!.length}',
                subtitle: 'Monthly disbursements and deduction ledgers',
              ),
              const SizedBox(height: 10),
              payrolls.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const ProEmpty(
                      icon: Icons.receipt_long_outlined,
                      title: 'No salary slips processed yet.',
                    );
                  }
                  final sorted = [...list]
                    ..sort((a, b) => (b.year * 12 + b.month).compareTo(a.year * 12 + a.month));
                  return ProListGroup(
                    children: [
                      for (final p in sorted)
                        _PayslipCard(payroll: p, monthName: _monthName(p.month)),
                    ],
                  );
                },
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myPayrollsProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayslipCard extends ConsumerStatefulWidget {
  const _PayslipCard({required this.payroll, required this.monthName});
  final PayrollRecord payroll;
  final String monthName;

  @override
  ConsumerState<_PayslipCard> createState() => _PayslipCardState();
}

void _showPayslipReceipt(
  BuildContext context,
  PayrollRecord payroll,
  String monthName,
) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, 24 + MediaQuery.of(ctx).padding.bottom),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6D3D6),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Heading
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Salary slip', style: AppText.caption),
                          Text(
                            '$monthName ${payroll.year}',
                            style: const TextStyle(
                              fontSize: 19,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (payroll.status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ProPill.ok(_statusLabel(payroll.status)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Net salary highlight
              ProDeepSurface(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Net salary paid',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _money(payroll.netSalary),
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.8,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Transferred to your bank account',
                      style: TextStyle(fontSize: 12.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Employee details
              GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Details'),
                    const SizedBox(height: 4),
                    ProKeyValue(rows: [
                      MapEntry('Employee name', payroll.employeeName),
                      MapEntry('Employee ID', payroll.employeeId.toString()),
                      MapEntry('Disbursement date', payroll.paymentDate ?? '—'),
                      MapEntry('Working days', '${payroll.workingDays} Days'),
                      MapEntry('Present days', '${payroll.presentDays} Days'),
                      MapEntry('Payable days', '${payroll.payableDays} Days'),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Earnings ledger
              GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProSectionHeader(
                      title: 'Earnings',
                      trailing: Text(
                        _money(payroll.grossEarnings),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ProKeyValue(rows: [
                      MapEntry('Basic salary', _money(payroll.basicSalary)),
                      MapEntry('HRA & house allowances',
                          _money(payroll.grossEarnings - payroll.basicSalary)),
                      MapEntry('Gross earnings', _money(payroll.grossEarnings)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Deductions ledger
              GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProSectionHeader(
                      title: 'Deductions',
                      trailing: Text(
                        _money(payroll.totalDeductions),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ProKeyValue(rows: [
                      MapEntry('Taxes & professional tax',
                          _money(payroll.taxAmount)),
                      MapEntry('Provident fund (PF) & ESI',
                          _money(payroll.totalDeductions - payroll.taxAmount)),
                      MapEntry('Total deductions',
                          _money(payroll.totalDeductions)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Download action — fetches the PDF and opens the system viewer.
              Consumer(
                builder: (context, ref, _) => _SheetDownloadButton(
                  onDownload: () => _downloadAndOpenPayslip(
                    ref,
                    context,
                    payroll,
                    monthName,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

class _PayslipCardState extends ConsumerState<_PayslipCard> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _downloadAndOpenPayslip(
      ref,
      context,
      widget.payroll,
      widget.monthName,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final payroll = widget.payroll;
    final monthName = widget.monthName;
    return ProListRow(
      leading: ProIconWell(
        icon: Icons.receipt_long_rounded,
        color: AppColors.primary,
      ),
      title: '$monthName ${payroll.year}',
      subtitle: 'Net amount: ${_money(payroll.netSalary)}',
      onTap: () => _showPayslipReceipt(context, payroll, monthName),
      trailing: IconButton(
        icon: _busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              )
            : Icon(Icons.download_rounded, color: AppColors.primary, size: 20),
        onPressed: _busy ? null : _download,
        tooltip: 'Download PDF',
      ),
    );
  }
}

/// Full-width download button used at the bottom of the receipt sheet; tracks
/// its own in-flight state so it can show a spinner.
class _SheetDownloadButton extends StatefulWidget {
  const _SheetDownloadButton({required this.onDownload});
  final Future<bool> Function() onDownload;

  @override
  State<_SheetDownloadButton> createState() => _SheetDownloadButtonState();
}

class _SheetDownloadButtonState extends State<_SheetDownloadButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                await widget.onDownload();
                if (mounted) setState(() => _busy = false);
              },
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Icon(Icons.download_rounded, size: 20),
        label: Text(_busy ? 'Downloading…' : 'Download payslip PDF'),
      ),
    );
  }
}
