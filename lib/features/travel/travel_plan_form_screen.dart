import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../requisitions/requisition_models.dart';
import '../requisitions/requisition_repository.dart';
import 'travel_models.dart';
import 'travel_repository.dart';

/// All active branches for the From/Destination pickers — unscoped (you can
/// travel to any branch), sorted by name.
final travelBranchesProvider =
    FutureProvider.autoDispose<List<BranchOption>>((ref) async {
  final all = await ref.watch(requisitionRepositoryProvider).listBranches();
  final active = all.where((b) => b.active).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  return active;
});

/// Create or edit a self travel plan (no approval). Pass an existing [plan] to
/// edit; omit it to create. Pops `true` on success so the list refreshes.
class TravelPlanFormScreen extends ConsumerStatefulWidget {
  const TravelPlanFormScreen({super.key, this.plan});
  final TravelPlan? plan;

  @override
  ConsumerState<TravelPlanFormScreen> createState() => _TravelPlanFormScreenState();
}

class _TravelPlanFormScreenState extends ConsumerState<TravelPlanFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _destination;
  late final TextEditingController _from;
  late final TextEditingController _purpose;
  late final TextEditingController _cost;
  String? _mode;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _title = TextEditingController(text: p?.title ?? '');
    _destination = TextEditingController(text: p?.destination ?? '');
    _from = TextEditingController(text: p?.fromLocation ?? '');
    _purpose = TextEditingController(text: p?.purpose ?? '');
    _cost = TextEditingController(
        text: p?.estimatedCost == null ? '' : p!.estimatedCost!.toStringAsFixed(2));
    _mode = p?.travelMode;
    _startDate = p?.startDate;
    _endDate = p?.endDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _destination.dispose();
    _from.dispose();
    _purpose.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
    if (d == null) return;
    setState(() {
      if (isStart) {
        _startDate = d;
        if (_endDate != null && _endDate!.isBefore(d)) _endDate = d;
      } else {
        _endDate = d;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a title.');
      return;
    }
    if (_destination.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a destination.');
      return;
    }
    if (_from.text.trim().isEmpty) {
      setState(() => _error = 'Please enter the From location.');
      return;
    }
    if (_mode == null || _mode!.isEmpty) {
      setState(() => _error = 'Please select a travel mode.');
      return;
    }
    if (_startDate == null) {
      setState(() => _error = 'Please select a start date.');
      return;
    }
    if (_endDate == null) {
      setState(() => _error = 'Please select an end date.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _error = "End date can't be before the start date.");
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(travelRepositoryProvider);
    final cost = double.tryParse(_cost.text.trim());
    try {
      if (_isEdit) {
        await repo.updatePlan(
          widget.plan!.id,
          title: _title.text.trim(),
          destination: _destination.text.trim(),
          fromLocation: _from.text.trim(),
          purpose: _purpose.text.trim(),
          travelMode: _mode,
          startDate: _startDate,
          endDate: _endDate,
          estimatedCost: cost,
        );
      } else {
        await repo.createPlan(
          title: _title.text.trim(),
          destination: _destination.text.trim(),
          fromLocation: _from.text.trim(),
          purpose: _purpose.text.trim(),
          travelMode: _mode,
          startDate: _startDate,
          endDate: _endDate,
          estimatedCost: cost,
        );
      }
      // Plans take no documents (policy 2026-07-04) — bills go on the claim.
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Travel Plan' : 'New Travel Plan'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _label('Title *'),
            TextField(
              controller: _title,
              maxLength: 150,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
            ),
            _label('From *'),
            _BranchField(controller: _from, hint: 'Type or pick a branch'),
            const SizedBox(height: 12),
            _label('Destination *'),
            _BranchField(controller: _destination, hint: 'Type or pick a branch'),
            const SizedBox(height: 12),
            _label('Travel mode *'),
            DropdownButtonFormField<String>(
              value: _mode,
              isExpanded: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.commute_rounded, size: 20)),
              items: [
                for (final m in TravelEnums.travelModes)
                  DropdownMenuItem(value: m, child: Text(TravelEnums.label(m))),
              ],
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Start date *',
                    value: _startDate == null ? 'Not set' : df.format(_startDate!),
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateField(
                    label: 'End date *',
                    value: _endDate == null ? 'Not set' : df.format(_endDate!),
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _label('Estimated cost'),
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            _label('Purpose'),
            TextField(
              controller: _purpose,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
            ),
            const SizedBox(height: 18),
            if (_isEdit && widget.plan!.attachments.isNotEmpty) ...[
              // Legacy plan attachments stay viewable; new uploads happen on the
              // CLAIM raised for this plan (policy 2026-07-04).
              const AppSectionHeader(title: 'Existing attachments'),
              const SizedBox(height: 8),
              for (final att in widget.plan!.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ExistingAttachmentTile(att: att),
                ),
              const SizedBox(height: 12),
            ],
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
                    : (_isEdit ? 'Save changes' : 'Create plan')),
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

/// Location field backed by the branch directory: type to search, matching
/// branches drop down inline under the field, tap one to select — a simple
/// autocomplete (no popup sheet). Free text stays allowed for non-branch
/// places and values saved before this picker existed.
class _BranchField extends ConsumerStatefulWidget {
  const _BranchField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  ConsumerState<_BranchField> createState() => _BranchFieldState();
}

class _BranchFieldState extends ConsumerState<_BranchField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branches =
        ref.watch(travelBranchesProvider).asData?.value ?? const <BranchOption>[];
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (TextEditingValue v) {
          final q = v.text.trim().toLowerCase();
          final labels = branches.map((b) => b.label);
          if (q.isEmpty) return labels;
          return labels.where((l) => l.toLowerCase().contains(q));
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadii.md),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 240,
                maxWidth: constraints.maxWidth,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final label = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.store_mall_directory_rounded,
                        size: 18, color: AppColors.primary),
                    title: Text(label,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    onTap: () => onSelected(label),
                  );
                },
              ),
            ),
          ),
        ),
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

class _ExistingAttachmentTile extends StatelessWidget {
  const _ExistingAttachmentTile({required this.att});
  final TravelAttachment att;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      shadow: AppShadows.soft,
      child: InkWell(
        onTap: () async {
          final url = Env.fileUrl(att.downloadUrl);
          if (url == null) return;
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        },
        child: Row(
          children: [
            const Icon(Icons.description_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(att.fileName ?? 'Attachment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
            ),
            const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
