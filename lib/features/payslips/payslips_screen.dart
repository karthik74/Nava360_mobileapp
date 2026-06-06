import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/download_saver.dart';
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

class PayslipsScreen extends ConsumerWidget {
  const PayslipsScreen({super.key});

  String _monthName(int month) {
    final dt = DateTime(2000, month);
    return DateFormat('MMMM').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payrolls = ref.watch(myPayrollsProvider);
    final mq = MediaQuery.of(context);

    double lastNetSalary = 0;
    payrolls.whenData((list) {
      if (list.isNotEmpty) {
        final sorted = [...list]..sort((a, b) => (b.year * 12 + b.month).compareTo(a.year * 12 + a.month));
        lastNetSalary = sorted.first.netSalary;
      }
    });

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize:
              Size.fromHeight(mq.padding.top + AppChrome.appBarHeight),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: GlassBlur.chrome,
                sigmaY: GlassBlur.chrome,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.62),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.5)),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          color: AppColors.inkSoft,
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'My Payslips',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: Colors.white.withOpacity(0.92),
          onRefresh: () async => ref.invalidate(myPayrollsProvider),
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              mq.padding.bottom + 20,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Last net salary',
                      value: payrolls.when(
                        data: (_) => '₹${NumberFormat('#,##,###').format(lastNetSalary)}',
                        loading: () => '—',
                        error: (_, __) => '0',
                      ),
                      icon: Icons.payments_rounded,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Total payslips',
                      value: payrolls.when(
                        data: (list) => list.length.toString(),
                        loading: () => '—',
                        error: (_, __) => '0',
                      ),
                      icon: Icons.receipt_long_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const AppSectionHeader(
                title: 'Salary Slips',
                subtitle: 'Monthly disbursements and deduction ledgers',
                onDark: false,
              ),
              const SizedBox(height: 12),
              payrolls.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'No salary slips processed yet.',
                    );
                  }
                  final sorted = [...list]
                    ..sort((a, b) => (b.year * 12 + b.month).compareTo(a.year * 12 + a.month));
                  return Column(
                    children: [
                      for (final p in sorted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PayslipCard(payroll: p, monthName: _monthName(p.month)),
                        ),
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
        ),
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
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.muted.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Heading
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SALARY SLIP',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$monthName ${payroll.year}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: AppColors.success.withOpacity(0.2)),
                      ),
                      child: Text(
                        payroll.status.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 14),
                // Employee Details Row
                _DetailRow(label: 'Employee Name', value: payroll.employeeName),
                _DetailRow(label: 'Employee ID', value: payroll.employeeId.toString()),
                _DetailRow(label: 'Disbursement Date', value: payroll.paymentDate ?? '—'),
                _DetailRow(label: 'Working Days', value: '${payroll.workingDays} Days'),
                _DetailRow(label: 'Present Days', value: '${payroll.presentDays} Days'),
                _DetailRow(label: 'Payable Days', value: '${payroll.payableDays} Days'),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 14),
                // Earnings Ledger Table
                const Text(
                  'EARNINGS LEDGER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                _LedgerItem(label: 'Basic Salary', value: payroll.basicSalary),
                _LedgerItem(label: 'HRA & House Allowances', value: payroll.grossEarnings - payroll.basicSalary),
                _LedgerItem(label: 'Gross Earnings', value: payroll.grossEarnings, isBold: true),
                const SizedBox(height: 18),
                // Deductions Ledger Table
                const Text(
                  'DEDUCTIONS LEDGER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                _LedgerItem(label: 'Taxes & Professional Tax', value: payroll.taxAmount),
                _LedgerItem(label: 'Provident Fund (PF) & ESI', value: payroll.totalDeductions - payroll.taxAmount),
                _LedgerItem(label: 'Total Deductions', value: payroll.totalDeductions, isBold: true),
                const SizedBox(height: 18),
                const Divider(thickness: 2),
                const SizedBox(height: 14),
                // Net Salary Highlight
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.primary.withOpacity(0.12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NET SALARY PAID',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Transferred to your bank account',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '₹${NumberFormat('#,##,###').format(payroll.netSalary)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
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
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$monthName ${payroll.year}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Net amount: ₹${NumberFormat('#,##,###').format(payroll.netSalary)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  )
                : const Icon(Icons.download_rounded,
                    color: AppColors.primary, size: 20),
            onPressed: _busy ? null : _download,
            tooltip: 'Download PDF',
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined, color: AppColors.primary, size: 20),
            onPressed: () =>
                _showPayslipReceipt(context, payroll, monthName),
            tooltip: 'View Slip Details',
          ),
        ],
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
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
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
        label: Text(_busy ? 'Downloading…' : 'Download Payslip PDF'),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerItem extends StatelessWidget {
  const _LedgerItem({required this.label, required this.value, this.isBold = false});
  final String label;
  final double value;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final formatted = '₹${NumberFormat('#,##,###').format(value)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isBold ? AppColors.ink : AppColors.inkSoft,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          Text(
            formatted,
            style: TextStyle(
              fontSize: 13,
              color: isBold ? AppColors.ink : AppColors.inkSoft,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
