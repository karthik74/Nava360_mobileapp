import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/download_saver.dart';
import '../../core/report_download.dart';
import '../../core/theme.dart';
import 'rent_models.dart';
import 'rent_repository.dart';
import 'rent_status_ui.dart';

/// Tabular data behind one on-screen report.
class _ReportData {
  _ReportData({required this.lede, required this.kpis, required this.headers, required this.rows, this.fileName = 'report.csv'});
  final String lede;
  final List<(String, String)> kpis;
  final List<String> headers; // first header is the row title
  final List<List<String>> rows;
  final String fileName;
}

// Same assumptions as web `deriveLeaseInfo`: uniform 3-year term, 12-month lock-in, 90-day notice.
class _Lease {
  _Lease(this.b) {
    final s = b.startDate;
    if (s != null) {
      end = DateTime(s.year + 3, s.month, s.day);
      lockEnd = DateTime(s.year, s.month + 12, s.day);
      daysToEnd = end!.difference(DateTime.now()).inDays;
    }
  }
  final RentBranch b;
  DateTime? end;
  DateTime? lockEnd;
  int? daysToEnd;
  double get deposit => b.rentAdvance ?? 0;
  int get depositMonths => (b.rent ?? 0) > 0 ? (deposit / b.rent!).round() : 0;
  String get status {
    final d = daysToEnd;
    if (d == null) return 'Active';
    if (d < 0) return 'Expired';
    if (d < 90) return 'Renewal due';
    if (d < 180) return 'Renewal upcoming';
    return 'Active';
  }
}

final _dDate = DateFormat('d MMM yyyy');
String _d(DateTime? d) => d == null ? '—' : _dDate.format(d);

class RentReportsTab extends ConsumerWidget {
  const RentReportsTab({super.key, required this.bottomPadding});
  final double bottomPadding;

  static const _reports = <(String, String, String)>[
    ('payable', 'Monthly Rent Payable', 'Branch-wise rent for a month, with TDS + GST breakdown (Excel).'),
    ('holding', 'Monthly Rent Holding', 'Rent withheld pending resolution.'),
    ('renewal', 'Agreement Renewal', 'Leases approaching expiry, sorted by urgency.'),
    ('incremental', 'Rent Incremental', 'Rent escalation history (not yet tracked).'),
    ('notice', 'Notice Issued', 'Every notice raised against a branch.'),
    ('new', 'New Branches', 'Recently onboarded branches.'),
    ('vintage', 'Lease Age', "How long each branch's lease has run."),
    ('expiry', 'Lease Expiry', 'Expiry calendar with lock-in dates.'),
    ('deposit', 'Security Deposit Tracking', 'Deposits held by landlords and concentration risk.'),
    ('advance', 'Advance Settlement', 'Advance rent paid vs. adjusted against rent.'),
  ];

  Future<DateTime?> _pickMonth(BuildContext context) => showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2015),
        lastDate: DateTime(2035),
        helpText: 'Pick any day in the month',
        initialDatePickerMode: DatePickerMode.year,
      );

  Future<void> _open(BuildContext context, WidgetRef ref, String id, String title) async {
    final repo = ref.read(rentRepositoryProvider);
    if (id == 'payable') {
      final d = await _pickMonth(context);
      if (d == null || !context.mounted) return;
      final period = isoPeriod(d);
      await downloadExcelReport(context, () => repo.downloadPayableReport(period), 'rent-payable-${period.substring(0, 7)}.xlsx');
      return;
    }
    if (id == 'incremental') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rent escalation history is not tracked yet - no records to show.')));
      return;
    }
    DateTime? month;
    if (id == 'holding') {
      month = await _pickMonth(context);
      if (month == null || !context.mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await _load(repo, id, month);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ReportSheet(title: title, data: data),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to load report: $e')));
    }
  }

  Future<_ReportData> _load(RentRepository repo, String id, DateTime? month) async {
    const money = rentMoney;
    switch (id) {
      case 'holding':
        final period = isoPeriod(month!);
        final held = (await repo.listPayableForPeriod(period)).where((r) => r.status == RentPayableStatus.held).toList();
        double net(RentPayable r) => r.netAmount ?? r.rentAmount;
        final total = held.fold<double>(0, (s, r) => s + net(r));
        int days(RentPayable r) => r.updatedAt == null ? 0 : DateTime.now().difference(r.updatedAt!).inDays.clamp(0, 100000);
        final avg = held.isEmpty ? 0 : (held.fold<int>(0, (s, r) => s + days(r)) / held.length).round();
        return _ReportData(
          lede: 'Rent withheld pending resolution for ${period.substring(0, 7)}.',
          kpis: [('Held rows', '${held.length}'), ('Total withheld', money(total)), ('Avg days held', '$avg')],
          headers: ['Branch', 'Period', 'Reason', 'Days held', 'Withheld'],
          rows: [for (final r in held) [r.branchName, r.period, r.holdReason ?? '—', '${days(r)}', money(net(r))]],
          fileName: 'rent_holding_${period.substring(0, 7)}.csv',
        );
      case 'notice':
        final n = await repo.listNotices();
        final prefix = DateFormat('yyyy-MM').format(DateTime.now());
        final thisMonth = n.where((x) => x.issuedOn != null && DateFormat('yyyy-MM').format(x.issuedOn!) == prefix).length;
        return _ReportData(
          lede: 'Every notice raised against a branch.',
          kpis: [
            ('Notices issued', '${n.length}'),
            ('This month', '$thisMonth'),
            ('Hold rent', '${n.where((x) => x.holdRent).length}'),
            ('Branches', '${n.map((x) => x.branchId).toSet().length}'),
          ],
          headers: ['Branch', 'Subject', 'Issued on', 'Holds rent', 'Issued by'],
          rows: [for (final x in n) [x.branchName, x.subject, _d(x.issuedOn), x.holdRent ? 'Yes' : 'No', x.issuedBy ?? '—']],
          fileName: 'notices.csv',
        );
    }
    final branches = await repo.listBranches();
    final leases = [for (final b in branches) _Lease(b)].where((l) => l.b.startDate != null).toList();
    switch (id) {
      case 'renewal':
        leases.sort((a, b) => a.end!.compareTo(b.end!));
        int c(String s) => leases.where((l) => l.status == s).length;
        return _ReportData(
          lede: "Leases approaching expiry, sorted by urgency. Dates are assumed (3-year term, 12-month lock-in) from each branch's start date.",
          kpis: [('Expired', '${c('Expired')}'), ('Renewal due', '${c('Renewal due')}'), ('Upcoming', '${c('Renewal upcoming')}'), ('Active', '${c('Active')}')],
          headers: ['Branch', 'End date', 'Notice (days)', 'Monthly rent', 'Renewal status'],
          rows: [for (final l in leases) [l.b.branchName, _d(l.end), '90', money(l.b.rent), l.status]],
          fileName: 'agreement_renewal.csv',
        );
      case 'new':
        final sorted = [...leases]..sort((a, b) => b.b.startDate!.compareTo(a.b.startDate!));
        final last90 = sorted.where((l) => DateTime.now().difference(l.b.startDate!).inDays <= 90).length;
        return _ReportData(
          lede: 'Recently onboarded branches, most recent first.',
          kpis: [('Last 90 days', '$last90'), ('Active branches', '${branches.where((b) => b.active).length}'), ('Total', '${branches.length}')],
          headers: ['Branch', 'Owner', 'Start date', 'Monthly rent', 'Active'],
          rows: [for (final l in sorted) [l.b.branchName, l.b.ownerName ?? '—', _d(l.b.startDate), money(l.b.rent), l.b.active ? 'Yes' : 'No']],
          fileName: 'new_branches.csv',
        );
      case 'vintage':
        double age(_Lease l) => DateTime.now().difference(l.b.startDate!).inDays / 365;
        final sorted = [...leases]..sort((a, b) => age(b).compareTo(age(a)));
        final avg = sorted.isEmpty ? 0.0 : sorted.fold<double>(0, (s, l) => s + age(l)) / sorted.length;
        return _ReportData(
          lede: 'How long each branch\'s lease has run (from its start date).',
          kpis: [('Leases', '${sorted.length}'), ('Average age (yrs)', avg.toStringAsFixed(1))],
          headers: ['Branch', 'Start date', 'Lease age (years)', 'Monthly rent'],
          rows: [for (final l in sorted) [l.b.branchName, _d(l.b.startDate), age(l).toStringAsFixed(1), money(l.b.rent)]],
          fileName: 'lease_age.csv',
        );
      case 'expiry':
        leases.sort((a, b) => a.end!.compareTo(b.end!));
        final now = DateTime.now();
        final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
        final fyStart = DateTime(fyStartYear, 4, 1);
        final fyEnd = DateTime(fyStartYear + 1, 4, 1);
        final fy = leases.where((l) => !l.end!.isBefore(fyStart) && l.end!.isBefore(fyEnd)).length;
        final within = leases.where((l) => l.lockEnd!.isAfter(now)).length;
        return _ReportData(
          lede: 'Lease expiry calendar with lock-in overlays.',
          kpis: [("This FY's expiries", '$fy'), ('Within lock-in', '$within'), ('Beyond lock-in', '${leases.length - within}')],
          headers: ['Branch', 'Start', 'End', 'Lock-in ends', 'Monthly rent'],
          rows: [for (final l in leases) [l.b.branchName, _d(l.b.startDate), _d(l.end), _d(l.lockEnd), money(l.b.rent)]],
          fileName: 'lease_expiry.csv',
        );
      case 'deposit':
        final rows = [for (final b in branches) _Lease(b)].where((l) => l.deposit > 0).toList();
        final total = rows.fold<double>(0, (s, l) => s + l.deposit);
        final avgM = rows.isEmpty ? 0.0 : rows.fold<int>(0, (s, l) => s + l.depositMonths) / rows.length;
        String risk(double v) => v > 5000000 ? 'High' : (v > 2500000 ? 'Medium' : 'Low');
        return _ReportData(
          lede: 'Deposits held by landlords and concentration risk.',
          kpis: [('Total deposit', money(total)), ('Branches', '${rows.length}'), ('Avg months held', avgM.toStringAsFixed(1))],
          headers: ['Branch', 'Owner', 'Monthly rent', 'Months held', 'Deposit', 'Recoverable on', 'Risk'],
          rows: [
            for (final l in rows)
              [l.b.branchName, l.b.ownerName ?? '—', money(l.b.rent), '${l.depositMonths}', money(l.deposit), _d(l.end), risk(l.deposit)]
          ],
          fileName: 'security_deposits.csv',
        );
      case 'advance':
        final rows = [for (final b in branches) _Lease(b)].where((l) => l.deposit > 0).toList();
        final total = rows.fold<double>(0, (s, l) => s + l.deposit);
        return _ReportData(
          lede: "Advance rent paid to landlords. Adjustment-against-rent isn't tracked yet, so every advance shows as fully unadjusted.",
          kpis: [('Total advance', money(total)), ('Adjusted', money(0)), ('Unadjusted', money(total))],
          headers: ['Branch', 'Advance paid', 'Adjusted', 'Unadjusted', 'Closure ETA'],
          rows: [for (final l in rows) [l.b.branchName, money(l.deposit), money(0), money(l.deposit), _d(l.end)]],
          fileName: 'advance_settlement.csv',
        );
    }
    throw Exception('Unknown report');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
      children: [
        for (var i = 0; i < _reports.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () => _open(context, ref, _reports[i].$1, _reports[i].$2),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    SizedBox(
                        width: 30,
                        child: Text((i + 1).toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_reports[i].$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(_reports[i].$3, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Icon(_reports[i].$1 == 'payable' ? Icons.download_rounded : Icons.chevron_right_rounded,
                        color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.title, required this.data});
  final String title;
  final _ReportData data;

  String _csv() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    return [data.headers, ...data.rows].map((r) => r.map(q).join(',')).join('\n');
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await DownloadSaver.save(data.fileName, Uint8List.fromList(utf8.encode(_csv())), mimeType: 'text/csv');
      messenger.showSnackBar(SnackBar(
        content: Text('Saved to ${saved.locationLabel}: ${data.fileName}'),
        action: saved.canOpen ? SnackBarAction(label: 'Open', onPressed: () => saved.open()) : null,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not export: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              TextButton.icon(
                onPressed: data.rows.isEmpty ? null : () => _export(context),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('CSV'),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(data.lede, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in data.kpis)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(k.$1, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                          Text(k.$2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (data.rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('No records.', style: TextStyle(color: AppColors.muted))),
                ),
              for (final r in data.rows)
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
                      Text(r.first, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      for (var i = 1; i < r.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: 120,
                                  child: Text(data.headers[i], style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
                              Expanded(child: Text(r[i], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
