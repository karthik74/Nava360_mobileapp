import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
import '../../core/widgets.dart';
import 'rent_gst_dialog.dart';
import 'rent_models.dart';
import 'rent_repository.dart';
import 'rent_status_ui.dart';

/// One rent-payable row's detail + workflow actions. There is no
/// `GET /payable/{id}` endpoint (the web lists by period only), so this
/// screen re-lists [period] and finds [payableId] within it — same source
/// of truth the list screen uses.
///
/// Workflow: PENDING → (submit) → SUBMITTED → (approve) → APPROVED →
/// (mark paid) → PAID, with a HELD side-state reachable from any
/// non-PAID/non-HELD status via "Hold" and left via "Release hold" (back to
/// PENDING). Actions are gated both by permission and by the row's current
/// [RentPayable.status] — mirrors `AdminRentPage.tsx`'s `PayableTab` action
/// buttons and confirm modals.
class RentPayableScreen extends ConsumerStatefulWidget {
  const RentPayableScreen({super.key, required this.payableId, required this.period});
  final int payableId;
  final String period;

  @override
  ConsumerState<RentPayableScreen> createState() => _RentPayableScreenState();
}

class _RentPayableScreenState extends ConsumerState<RentPayableScreen> {
  RentPayable? _row;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(rentRepositoryProvider).listPayableForPeriod(widget.period);
      final match = rows.where((r) => r.id == widget.payableId);
      if (!mounted) return;
      setState(() => _row = match.isNotEmpty ? match.first : null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<RentPayable> Function() fn) async {
    setState(() => _busy = true);
    try {
      final updated = await fn();
      if (!mounted) return;
      setState(() {
        _row = updated;
        _changed = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid() async {
    final utr = await _promptText(
      title: 'Mark "${_row!.branchName}" as paid',
      label: 'Payment reference / UTR',
    );
    if (utr == null) return;
    final repo = ref.read(rentRepositoryProvider);
    await _act(() => repo.markPayablePaid(_row!.id, paidUtr: utr.isEmpty ? null : utr));
  }

  Future<void> _hold() async {
    final reason = await _promptText(
      title: 'Hold "${_row!.branchName}"\'s rent payable',
      label: 'Reason for hold',
    );
    if (reason == null) return;
    final repo = ref.read(rentRepositoryProvider);
    await _act(() => repo.holdPayable(_row!.id, holdReason: reason.isEmpty ? null : reason));
  }

  Future<String?> _promptText({required String title, required String label}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    final df = DateFormat('d MMM yyyy, HH:mm');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rent payable'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        bottomNavigationBar: row == null || _loading ? null : _actionBar(row),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : row == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AppErrorPanel(
                        message: _error ?? 'Rent payable row not found.',
                        onRetry: _load,
                      ),
                    ),
                  )
                : _content(row, df),
      ),
    );
  }

  Widget _content(RentPayable row, DateFormat df) {
    final tone = rentPayableStatusTone(row.status);
    final tagTone = tone.color == AppColors.success
        ? ProTagTone.ok
        : tone.color == AppColors.danger
            ? ProTagTone.bad
            : tone.color == AppColors.warning
                ? ProTagTone.warn
                : ProTagTone.neutral;
    final stage = switch (row.status) {
      RentPayableStatus.pending => 'Waiting to be submitted',
      RentPayableStatus.submitted => 'Submitted · waiting for approval',
      RentPayableStatus.approved => 'Approved · ready to pay',
      RentPayableStatus.paid => row.paidAt != null ? 'Paid on ${df.format(row.paidAt!)}' : 'Paid',
      RentPayableStatus.held => 'On hold${row.holdReason != null ? ' · ${row.holdReason}' : ''}',
      _ => tone.label,
    };
    final stageColor = switch (row.status) {
      RentPayableStatus.held => const Color(0xFFE5484D),
      RentPayableStatus.paid => AppColors.live,
      _ => const Color(0xFFF2B347),
    };
    final kpis = <ProKpi>[
      ProKpi(value: rentMoney(row.rentAmount), label: 'Rent amount'),
      if (row.gstAmount != null) ProKpi(value: rentMoney(row.gstAmount), label: 'GST'),
      if (row.tdsAmount != null) ProKpi(value: rentMoney(row.tdsAmount), label: 'TDS'),
      if (row.netAmount != null)
        ProKpi(value: rentMoney(row.netAmount), label: 'Net payable', valueColor: AppColors.primary),
    ];

    return ProPage(
      onRefresh: _load,
      hero: ProHero(
        overlap: ProKpiStrip(cells: kpis),
        children: [
          ProHeroIdentity(
            name: row.branchName,
            role: 'Period ${row.period}',
            icon: Icons.receipt_long_rounded,
            tags: [ProHeroTag(tone.label, tone: tagTone)],
          ),
          ProLiveLine(text: stage, color: stageColor),
        ],
      ),
      children: [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Details'),
              const SizedBox(height: 4),
              ProKeyValue(rows: [
                MapEntry('Period', row.period),
                MapEntry('Rent amount', rentMoney(row.rentAmount)),
                if (row.gstAmount != null) MapEntry('GST', rentMoney(row.gstAmount)),
                if (row.tdsAmount != null) MapEntry('TDS', rentMoney(row.tdsAmount)),
                if (row.netAmount != null) MapEntry('Net payable', rentMoney(row.netAmount)),
                if (row.paidUtr != null && row.paidUtr!.isNotEmpty) MapEntry('UTR', row.paidUtr!),
                if (row.status == RentPayableStatus.held && row.holdReason != null)
                  MapEntry('Hold reason', row.holdReason!),
              ]),
            ],
          ),
        ),
        if (row.submittedAt != null || row.approvedAt != null || row.paidAt != null)
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Workflow'),
                const SizedBox(height: 4),
                ProKeyValue(rows: [
                  if (row.submittedAt != null)
                    MapEntry('Submitted', '${df.format(row.submittedAt!)} · ${row.submittedBy ?? '—'}'),
                  if (row.approvedAt != null)
                    MapEntry('Approved', '${df.format(row.approvedAt!)} · ${row.approvedBy ?? '—'}'),
                  if (row.paidAt != null) MapEntry('Paid', '${df.format(row.paidAt!)} · ${row.paidBy ?? '—'}'),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  /// Workflow actions for the row's current status (same handlers and gates
  /// as before), in a sticky bottom bar.
  Widget? _actionBar(RentPayable row) {
    final actions = <Widget>[
      if (row.status == RentPayableStatus.pending)
        _actionButton('Submit', Icons.send_rounded, () async {
          final repo = ref.read(rentRepositoryProvider);
          if (!await confirmGstBeforeSubmit(context, repo, row.branchId)) return;
          await _act(() => repo.submitPayable(row.id));
        }, primary: true),
      if (row.status == RentPayableStatus.submitted)
        _actionButton('Approve', Icons.check_circle_outline_rounded,
            () => _act(() => ref.read(rentRepositoryProvider).approvePayable(row.id)),
            primary: true),
      if (row.status == RentPayableStatus.approved)
        _actionButton('Mark paid', Icons.payments_rounded, _markPaid, primary: true),
      if (row.status == RentPayableStatus.held)
        _actionButton('Release hold', Icons.lock_open_rounded,
            () => _act(() => ref.read(rentRepositoryProvider).releasePayableHold(row.id)),
            primary: true),
      if (row.status != RentPayableStatus.held && row.status != RentPayableStatus.paid)
        _actionButton('Hold', Icons.pause_circle_outline_rounded, _hold, danger: true),
    ];
    if (actions.isEmpty) return null;
    // Destructive action first, primary on the right.
    return ProBottomBar(children: actions.reversed.toList());
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap,
      {bool primary = false, bool danger = false}) {
    if (danger) {
      return FilledButton.icon(
        onPressed: _busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.dangerTint,
          foregroundColor: AppColors.danger,
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    if (primary) {
      return FilledButton.icon(
        onPressed: _busy ? null : onTap,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
