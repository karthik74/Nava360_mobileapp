import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'resignation_models.dart';
import 'resignation_repository.dart';

final myResignationsProvider =
    FutureProvider.autoDispose<List<Resignation>>((ref) {
  return ref.watch(resignationRepositoryProvider).myResignations();
});

final myNoticePeriodProvider =
    FutureProvider.autoDispose<NoticePeriodInfo>((ref) {
  return ref.watch(resignationRepositoryProvider).myNoticePeriod();
});

Color resignationStatusColor(String status) {
  switch (status) {
    case 'APPROVED':
      return AppColors.success;
    case 'PENDING':
      return AppColors.warning;
    case 'IN_APPROVAL':
      return AppColors.accent;
    case 'REJECTED':
      return AppColors.danger;
    case 'COMPLETED':
      return AppColors.primary;
    case 'WITHDRAWN':
    default:
      return AppColors.muted;
  }
}

String _humanStatus(String raw) {
  final s = raw.replaceAll('_', ' ').toLowerCase();
  return s.isEmpty ? raw : s[0].toUpperCase() + s.substring(1);
}

class ResignationScreen extends ConsumerStatefulWidget {
  const ResignationScreen({super.key});

  @override
  ConsumerState<ResignationScreen> createState() => _ResignationScreenState();
}

class _ResignationScreenState extends ConsumerState<ResignationScreen> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(myResignationsProvider);
    ref.invalidate(myNoticePeriodProvider);
  }

  Future<void> _apply() async {
    final notice = ref.read(myNoticePeriodProvider).valueOrNull;
    final result = await showModalBottomSheet<_ApplyResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ApplySheet(noticePeriodDays: notice?.noticePeriodDays),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(resignationRepositoryProvider).apply(
            resignationDate: result.resignationDate,
            lastWorkingDay: result.lastWorkingDay,
            reason: result.reason,
          );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resignation submitted.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(Resignation r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw resignation?'),
        content: const Text(
          'Your resignation will be cancelled. You can submit a new one later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(resignationRepositoryProvider).withdraw(r.id);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resignation withdrawn.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not withdraw: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final resignations = ref.watch(myResignationsProvider);
    final notice = ref.watch(myNoticePeriodProvider);

    final active = resignations.valueOrNull?.where((r) => r.isActive).toList();
    final past = resignations.valueOrNull?.where((r) => r.isClosed).toList();
    final hasActive = active != null && active.isNotEmpty;

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(mq.padding.top + AppChrome.appBarHeight),
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
                            'My Resignation',
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
          onRefresh: () async => _refresh(),
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 24),
            children: [
              _NoticePeriodCard(async: notice),
              const SizedBox(height: 20),
              resignations.when(
                loading: () => const AppLoadingBlock(height: 150),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: _refresh,
                ),
                data: (_) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasActive) ...[
                        const AppSectionHeader(
                          title: 'Current resignation',
                          subtitle: 'Your active request',
                        ),
                        const SizedBox(height: 12),
                        for (final r in active)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ResignationCard(
                              resignation: r,
                              onWithdraw: _busy ? null : () => _withdraw(r),
                            ),
                          ),
                      ] else ...[
                        _ApplyPrompt(
                          busy: _busy,
                          onApply: _busy ? null : _apply,
                        ),
                      ],
                      if (past != null && past.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const AppSectionHeader(
                          title: 'History',
                          subtitle: 'Past resignation requests',
                        ),
                        const SizedBox(height: 12),
                        for (final r in past)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ResignationCard(resignation: r),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Notice period ──────────────────────────────

class _NoticePeriodCard extends StatelessWidget {
  const _NoticePeriodCard({required this.async});
  final AsyncValue<NoticePeriodInfo> async;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const AppLoadingBlock(height: 90),
      error: (_, __) => const SizedBox.shrink(),
      data: (info) => GlassCard(
        padding: const EdgeInsets.all(16),
        shadow: AppShadows.soft,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.22)),
              ),
              child: const Icon(Icons.event_note_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${info.noticePeriodDays} days notice period',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.tenureMonths != null
                        ? '${info.tenureMonths} months of service${info.resolved ? '' : ' · org default'}'
                        : (info.resolved ? 'Based on your tenure' : 'Organisation default'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Apply prompt ───────────────────────────────

class _ApplyPrompt extends StatelessWidget {
  const _ApplyPrompt({required this.busy, required this.onApply});
  final bool busy;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadow: AppShadows.soft,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.10),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.danger.withOpacity(0.2)),
            ),
            child: const Icon(Icons.logout_rounded,
                color: AppColors.danger, size: 24),
          ),
          const SizedBox(height: 14),
          const Text(
            'No active resignation',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'If you wish to resign, submit a request below. HR will review it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.edit_note_rounded, size: 20),
              label: Text(busy ? 'Submitting…' : 'Apply for resignation'),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Resignation card ───────────────────────────

class _ResignationCard extends StatelessWidget {
  const _ResignationCard({required this.resignation, this.onWithdraw});
  final Resignation resignation;
  final VoidCallback? onWithdraw;

  String _fmt(DateTime? d) => d == null ? '—' : DateFormat('d MMM y').format(d);

  @override
  Widget build(BuildContext context) {
    final r = resignation;
    final color = resignationStatusColor(r.status);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Resignation request',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              StatusPill(label: _humanStatus(r.status), color: color),
            ],
          ),
          const SizedBox(height: 12),
          _row(Icons.event_outlined, 'Resignation date', _fmt(r.resignationDate)),
          if (r.lastWorkingDay != null)
            _row(Icons.event_available_outlined, 'Last working day',
                _fmt(r.lastWorkingDay)),
          if (r.noticePeriodDays != null)
            _row(Icons.timelapse_rounded, 'Notice period',
                '${r.noticePeriodDays} days'),
          if (r.reason != null && r.reason!.isNotEmpty)
            _row(Icons.notes_rounded, 'Reason', r.reason!),
          if (r.reviewComment != null && r.reviewComment!.isNotEmpty)
            _row(Icons.rate_review_outlined, 'Reviewer note', r.reviewComment!),
          if (onWithdraw != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onWithdraw,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withOpacity(0.4)),
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Withdraw resignation'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.muted),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Apply sheet ────────────────────────────────

class _ApplyResult {
  _ApplyResult({
    required this.resignationDate,
    this.lastWorkingDay,
    this.reason,
  });
  final String resignationDate;
  final String? lastWorkingDay;
  final String? reason;
}

class _ApplySheet extends StatefulWidget {
  const _ApplySheet({this.noticePeriodDays});
  final int? noticePeriodDays;

  @override
  State<_ApplySheet> createState() => _ApplySheetState();
}

class _ApplySheetState extends State<_ApplySheet> {
  DateTime? _resignationDate;
  DateTime? _lastWorkingDay;
  final _reasonCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _label(DateTime? d) => d == null ? 'Select date' : DateFormat('d MMM y').format(d);

  Future<void> _pickResignationDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _resignationDate ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _resignationDate = picked;
      // Suggest a last working day from the notice period if not set.
      if (_lastWorkingDay == null && widget.noticePeriodDays != null) {
        _lastWorkingDay = picked.add(Duration(days: widget.noticePeriodDays!));
      }
    });
  }

  Future<void> _pickLastWorkingDay() async {
    final base = _resignationDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastWorkingDay ?? base,
      firstDate: base,
      lastDate: base.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _lastWorkingDay = picked);
  }

  void _submit() {
    if (_resignationDate == null) {
      setState(() => _error = 'Please choose a resignation date.');
      return;
    }
    Navigator.pop(
      context,
      _ApplyResult(
        resignationDate: _iso(_resignationDate!),
        lastWorkingDay: _lastWorkingDay == null ? null : _iso(_lastWorkingDay!),
        reason: _reasonCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Apply for resignation',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'HR will review your request. Your last working day defaults to the notice period.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 18),
              _DateField(
                label: 'Resignation date',
                value: _label(_resignationDate),
                onTap: _pickResignationDate,
              ),
              const SizedBox(height: 12),
              _DateField(
                label: 'Last working day (optional)',
                value: _label(_lastWorkingDay),
                onTap: _pickLastWorkingDay,
              ),
              const SizedBox(height: 12),
              const Text(
                'Reason (optional)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonCtrl,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
                decoration: InputDecoration(
                  hintText: 'Share a brief reason…',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide: BorderSide(color: AppColors.muted.withOpacity(0.25)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide: BorderSide(color: AppColors.muted.withOpacity(0.25)),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Submit resignation'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.muted.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 10),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
