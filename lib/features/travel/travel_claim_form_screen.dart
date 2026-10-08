import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'travel_models.dart';
import 'travel_repository.dart';
import 'travel_status_ui.dart';

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

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: _isEdit ? 'Edit claim' : 'New travel claim',
        subtitle: _isEdit ? 'Trip details' : 'Step 1 of 3 · Trip details',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!_isEdit) ...[
            const ProStepBar(total: 3, current: 0),
            const SizedBox(height: 14),
            const ProNote(
              'Select your travel plan first — the claim details fill in automatically. Then add expense lines, bills and submit for approval.',
              tone: ProNoteTone.info,
            ),
            const SizedBox(height: 14),
          ],
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Trip details'),
                const SizedBox(height: 12),
                // ── Plan first: picking it auto-fills title / purpose / dates ──
                ProField(
                  label: 'Travel plan',
                  required: true,
                  child: plans.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    error: (e, _) => const Text('Could not load plans.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    data: (rows) {
                      final picked = rows.where((x) => x.id == _planId).firstOrNull;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          if (picked != null &&
                              ((picked.destination ?? '').isNotEmpty ||
                                  picked.travelMode != null)) ...[
                            const SizedBox(height: 8),
                            _PlanSummary(plan: picked),
                          ],
                          if (rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'No travel plans yet — create a travel plan first, then raise the claim for it.',
                                style: AppText.caption,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Title',
                  required: true,
                  child: TextField(
                    controller: _title,
                    maxLength: 150,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                    decoration: const InputDecoration(hintText: 'Filled from your plan'),
                  ),
                ),
                const SizedBox(height: 4),
                ProField(
                  label: 'Purpose',
                  child: TextField(
                    controller: _purpose,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                    decoration: const InputDecoration(hintText: 'Why did you travel?'),
                  ),
                ),
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
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppErrorPanel(message: _error!),
          ],
        ],
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving
                ? 'Saving…'
                : (_isEdit ? 'Save changes' : 'Create & add expenses')),
          ),
        ],
      ),
    );
  }
}

/// Route / mode / dates of the picked plan, shown under the plan dropdown.
class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});
  final TravelPlan plan;

  @override
  Widget build(BuildContext context) {
    final route = [
      if ((plan.fromLocation ?? '').isNotEmpty) plan.fromLocation!,
      if ((plan.destination ?? '').isNotEmpty) plan.destination!,
    ].join(' → ');
    final df = DateFormat('d MMM');
    final meta = [
      if (plan.travelMode != null) TravelEnums.label(plan.travelMode),
      if (plan.startDate != null && plan.endDate != null)
        '${df.format(plan.startDate!)} – ${df.format(plan.endDate!)}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Row(
        children: [
          ProIconWell(icon: travelModeIcon(plan.travelMode), color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (route.isNotEmpty)
                  Text(route,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                if (meta.isNotEmpty) Text(meta, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ProField(
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.calendar_today_rounded, size: 17),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: value == 'Not set' ? AppColors.faint : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
