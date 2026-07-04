import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'travel_models.dart';
import 'travel_repository.dart';

/// Active travel plans the employee can attach a claim to.
final _myActivePlansProvider =
    FutureProvider.autoDispose<List<TravelPlan>>((ref) {
  return ref.watch(travelRepositoryProvider).myPlans(status: 'ACTIVE', size: 100);
});

/// Create a DRAFT claim, or edit an existing claim's header (DRAFT/SENT_BACK).
/// On create the screen replaces itself with the claim detail so the employee
/// can immediately add expense lines + bills. On edit it pops `true`.
class TravelClaimFormScreen extends ConsumerStatefulWidget {
  const TravelClaimFormScreen({super.key, this.claim});
  final TravelClaim? claim;

  @override
  ConsumerState<TravelClaimFormScreen> createState() => _TravelClaimFormScreenState();
}

class _TravelClaimFormScreenState extends ConsumerState<TravelClaimFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _purpose;
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _planId;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.claim != null;

  /// Selecting a plan copies its trip details into the claim header — the plan
  /// is picked FIRST, so title/purpose/dates always start from the plan.
  void _applyPlan(TravelPlan p) {
    setState(() {
      _planId = p.id;
      _title.text = p.title;
      _purpose.text = p.purpose ?? '';
      if (p.startDate != null) _fromDate = p.startDate;
      if (p.endDate != null) _toDate = p.endDate;
    });
  }

  @override
  void initState() {
    super.initState();
    final c = widget.claim;
    _title = TextEditingController(text: c?.title ?? '');
    _purpose = TextEditingController(text: c?.purpose ?? '');
    _fromDate = c?.fromDate;
    _toDate = c?.toDate;
    _planId = c?.travelPlanId;
  }

  @override
  void dispose() {
    _title.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _fromDate : _toDate) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = d;
        if (_toDate != null && _toDate!.isBefore(d)) _toDate = d;
      } else {
        _toDate = d;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_planId == null) {
      setState(() =>
          _error = 'Select the travel plan this claim is for. Create the plan first if it doesn\'t exist.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a title.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(travelRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateClaim(
          widget.claim!.id,
          title: _title.text.trim(),
          purpose: _purpose.text.trim(),
          fromDate: _fromDate,
          toDate: _toDate,
          travelPlanId: _planId,
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final created = await repo.createClaim(
          title: _title.text.trim(),
          purpose: _purpose.text.trim(),
          fromDate: _fromDate,
          toDate: _toDate,
          travelPlanId: _planId,
        );
        if (mounted) context.pushReplacement('/travel/claims/${created.id}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final plans = ref.watch(_myActivePlansProvider);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Claim' : 'New Travel Claim'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEdit)
              GlassCard(
                color: AppColors.info.withOpacity(0.06),
                shadow: AppShadows.soft,
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.info),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Select your travel plan first — the claim details fill in automatically. Then add expense lines, bills and submit for approval.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_isEdit) const SizedBox(height: 14),
            // ── Plan first: picking it auto-fills title / purpose / dates ──
            _label('Travel plan *'),
            plans.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => const Text('Could not load plans.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
              data: (rows) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int?>(
                    value: _planId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.luggage_rounded, size: 20),
                        hintText: 'Select the plan this claim is for'),
                    items: [
                      for (final p in rows)
                        DropdownMenuItem<int?>(value: p.id, child: Text(p.title)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final p = rows.where((x) => x.id == v).firstOrNull;
                      if (p != null) _applyPlan(p);
                    },
                  ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'No travel plans yet — create a travel plan first, then raise the claim for it.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _label('Title *'),
            TextField(controller: _title, maxLength: 150),
            _label('Purpose'),
            TextField(controller: _purpose, minLines: 2, maxLines: 5),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'From',
                    value: _fromDate == null ? 'Not set' : df.format(_fromDate!),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateField(
                    label: 'To',
                    value: _toDate == null ? 'Not set' : df.format(_toDate!),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AppErrorPanel(message: _error!),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? 'Saving…'
                    : (_isEdit ? 'Save changes' : 'Create & add expenses')),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
