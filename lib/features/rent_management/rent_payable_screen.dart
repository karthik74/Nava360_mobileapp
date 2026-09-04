import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
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
      child: GlassBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(row?.branchName ?? 'Rent Payable'),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(_changed),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : row == null
                  ? Center(
                      child: AppErrorPanel(
                        message: _error ?? 'Rent payable row not found.',
                        onRetry: _load,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        GlassCard(
                          padding: const EdgeInsets.all(16),
                          shadow: AppShadows.soft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(row.branchName,
                                        style: const TextStyle(
                                            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                                  ),
                                  StatusPill(
                                    label: rentPayableStatusTone(row.status).label,
                                    color: rentPayableStatusTone(row.status).color,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Period: ${row.period}',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                              const Divider(height: 22),
                              _kv('Rent amount', rentMoney(row.rentAmount)),
                              if (row.submittedAt != null)
                                _kv('Submitted', '${df.format(row.submittedAt!)} · ${row.submittedBy ?? '—'}'),
                              if (row.approvedAt != null)
                                _kv('Approved', '${df.format(row.approvedAt!)} · ${row.approvedBy ?? '—'}'),
                              if (row.paidAt != null)
                                _kv('Paid', '${df.format(row.paidAt!)} · ${row.paidBy ?? '—'}'),
                              if (row.paidUtr != null && row.paidUtr!.isNotEmpty) _kv('UTR', row.paidUtr!),
                              if (row.status == RentPayableStatus.held && row.holdReason != null)
                                _kv('Hold reason', row.holdReason!),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const AppSectionHeader(title: 'Actions'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (row.status == RentPayableStatus.pending)
                              _actionButton('Submit', Icons.send_rounded,
                                  () => _act(() => ref.read(rentRepositoryProvider).submitPayable(row.id))),
                            if (row.status == RentPayableStatus.submitted)
                              _actionButton('Approve', Icons.check_circle_outline_rounded,
                                  () => _act(() => ref.read(rentRepositoryProvider).approvePayable(row.id))),
                            if (row.status == RentPayableStatus.approved)
                              _actionButton('Mark paid', Icons.payments_rounded, _markPaid, primary: true),
                            if (row.status == RentPayableStatus.held)
                              _actionButton(
                                  'Release hold',
                                  Icons.lock_open_rounded,
                                  () => _act(
                                      () => ref.read(rentRepositoryProvider).releasePayableHold(row.id))),
                            if (row.status != RentPayableStatus.held && row.status != RentPayableStatus.paid)
                              _actionButton('Hold', Icons.pause_circle_outline_rounded, _hold, danger: true),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(k, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink))),
          ],
        ),
      );

  Widget _actionButton(String label, IconData icon, VoidCallback onTap,
      {bool primary = false, bool danger = false}) {
    final color = danger ? AppColors.danger : (primary ? AppColors.primary : AppColors.ink);
    return FilledButton.icon(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: danger ? AppColors.danger : (primary ? AppColors.primary : AppColors.surface),
        foregroundColor: danger || primary ? Colors.white : AppColors.ink,
        side: danger || primary ? null : const BorderSide(color: AppColors.hairline),
      ),
      icon: Icon(icon, size: 17, color: danger || primary ? Colors.white : color),
      label: Text(label),
    );
  }
}
