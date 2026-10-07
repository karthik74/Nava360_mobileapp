import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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

/// Calm status pill (neutral for closed requests).
ProPill _statusPill(String status) {
  final label = _humanStatus(status);
  switch (status) {
    case 'APPROVED':
      return ProPill.ok(label);
    case 'PENDING':
      return ProPill.warn(label);
    case 'IN_APPROVAL':
      return ProPill.info(label);
    case 'REJECTED':
      return ProPill.bad(label);
    default:
      return ProPill.neutral(label);
  }
}

/// Dot colour for the hero live line.
Color _liveDot(String status) {
  switch (status) {
    case 'APPROVED':
      return AppColors.live;
    case 'IN_APPROVAL':
      return const Color(0xFF4CC3DB);
    default:
      return const Color(0xFFF2B347);
  }
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerTint,
              foregroundColor: AppColors.danger,
            ),
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
    final resignations = ref.watch(myResignationsProvider);
    final notice = ref.watch(myNoticePeriodProvider);

    final active = resignations.valueOrNull?.where((r) => r.isActive).toList();
    final past = resignations.valueOrNull?.where((r) => r.isClosed).toList();
    final hasActive = active != null && active.isNotEmpty;
    final current = hasActive ? active.first : null;
    final info = notice.valueOrNull;

    String fmtShort(DateTime? d) => d == null ? '—' : DateFormat('d MMM').format(d);
    String fmt(DateTime? d) => d == null ? '—' : DateFormat('d MMM y').format(d);

    final children = <Widget>[
      // Notice period — a calm explanation rather than a big card.
      notice.when(
        loading: () => const AppLoadingBlock(height: 70),
        error: (_, __) => const SizedBox.shrink(),
        data: (info) => ProNote(
          'Your notice period is ${info.noticePeriodDays} days — '
          '${info.tenureMonths != null ? '${info.tenureMonths} months of service${info.resolved ? '' : ' · org default'}' : (info.resolved ? 'based on your tenure' : 'organisation default')}. '
          'Your last working day defaults to the notice period.',
          tone: ProNoteTone.neutral,
          icon: Icons.event_note_rounded,
        ),
      ),
      ...resignations.when<List<Widget>>(
        loading: () => const [AppLoadingBlock(height: 150)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: _refresh,
          ),
        ],
        data: (_) => [
          if (hasActive) ...[
            const ProSectionHeader(
              title: 'Current resignation',
              subtitle: 'Your active request',
            ),
            for (final r in active)
              _ResignationCard(
                resignation: r,
                onWithdraw: _busy ? null : () => _withdraw(r),
              ),
          ] else
            _ApplyPrompt(
              busy: _busy,
              onApply: _busy ? null : _apply,
            ),
          if (past != null && past.isNotEmpty) ...[
            ProSectionHeader(
              title: 'History · ${past.length}',
              subtitle: 'Past resignation requests',
            ),
            for (final r in past) _ResignationCard(resignation: r),
          ],
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Resignation')),
      body: ProPage(
        onRefresh: () async => _refresh(),
        hero: ProHero(
          title: 'My resignation',
          subtitle: 'Your notice period and resignation requests',
          overlap: info == null
              ? null
              : ProKpiStrip(cells: [
                  ProKpi(value: '${info.noticePeriodDays}', label: 'Days notice'),
                  ProKpi(
                    value: info.tenureMonths != null ? '${info.tenureMonths}' : '—',
                    label: 'Months of service',
                  ),
                  ProKpi(
                    value: fmtShort(current?.lastWorkingDay),
                    label: 'Last working day',
                  ),
                ]),
          children: [
            if (current != null)
              ProLiveLine(
                text: '${_humanStatus(current.status)} · resignation date ${fmt(current.resignationDate)}'
                    '${current.lastWorkingDay != null ? ' · last day ${fmt(current.lastWorkingDay)}' : ''}',
                color: _liveDot(current.status),
              ),
          ],
        ),
        children: children,
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
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(
        children: [
          const ProIconWell(icon: Icons.logout_rounded, size: 48),
          const SizedBox(height: 14),
          const Text(
            'No active resignation',
            style: AppText.title,
          ),
          const SizedBox(height: 4),
          const Text(
            'If you wish to resign, submit a request below. HR will review it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onApply,
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
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ProIconWell(icon: Icons.description_outlined),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Resignation request',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15,
                    color: AppColors.ink,
                  ),
                ),
              ),
              _statusPill(r.status),
            ],
          ),
          const SizedBox(height: 6),
          ProKeyValue(rows: [
            MapEntry('Resignation date', _fmt(r.resignationDate)),
            if (r.lastWorkingDay != null)
              MapEntry('Last working day', _fmt(r.lastWorkingDay)),
            if (r.noticePeriodDays != null)
              MapEntry('Notice period', '${r.noticePeriodDays} days'),
            if (r.reason != null && r.reason!.isNotEmpty) MapEntry('Reason', r.reason!),
            if (r.reviewComment != null && r.reviewComment!.isNotEmpty)
              MapEntry('Reviewer note', r.reviewComment!),
          ]),
          if (onWithdraw != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onWithdraw,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerTint,
                foregroundColor: AppColors.danger,
              ),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Withdraw resignation'),
            ),
          ],
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
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mq.size.height - mq.viewInsets.bottom - mq.padding.top - 24,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Apply for resignation',
                              style: TextStyle(
                                fontSize: 19,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.35,
                                color: AppColors.ink,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'HR will review your request. Your last working day defaults to the notice period.',
                              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SheetClose(onTap: () => Navigator.of(context).pop()),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.noticePeriodDays != null) ...[
                      ProNote(
                        'Your notice period is ${widget.noticePeriodDays} days. '
                        'Picking a resignation date suggests a last working day from it — you can change it.',
                        tone: ProNoteTone.neutral,
                        icon: Icons.event_note_rounded,
                      ),
                      const SizedBox(height: 16),
                    ],
                    ProField(
                      label: 'Resignation date',
                      required: true,
                      child: _DateField(
                        value: _label(_resignationDate),
                        empty: _resignationDate == null,
                        onTap: _pickResignationDate,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Last working day (optional)',
                      child: _DateField(
                        value: _label(_lastWorkingDay),
                        empty: _lastWorkingDay == null,
                        onTap: _pickLastWorkingDay,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Reason (optional)',
                      child: TextField(
                        controller: _reasonCtrl,
                        minLines: 3,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [TitleCaseTextFormatter()],
                        decoration: const InputDecoration(
                          hintText: 'Share a brief reason…',
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ProNote(_error!, tone: ProNoteTone.bad),
                    ],
                  ],
                ),
              ),
            ),
            ProBottomBar(
              children: [
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Submit resignation'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetClose extends StatelessWidget {
  const _SheetClose({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEEF3F4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.close_rounded, size: 18, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.empty,
    required this.onTap,
  });
  final String value;
  final bool empty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: Color(0xFFDBE3E5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: empty ? AppColors.faint : AppColors.ink,
                    fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 20, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}
