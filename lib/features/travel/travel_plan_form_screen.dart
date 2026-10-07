import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
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

/// Configurable Title/purpose options (Settings → Lookups → Travel plan titles).
final travelPlanTitlesProvider = FutureProvider.autoDispose<List<String>>(
    (ref) => ref.watch(travelRepositoryProvider).planTitles());

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: _isEdit ? 'Edit travel plan' : 'New travel plan',
        subtitle: _isEdit ? widget.plan!.title : 'Record an upcoming trip',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Trip'),
                const SizedBox(height: 12),
                ProField(
                  label: 'Title',
                  required: true,
                  child: ref.watch(travelPlanTitlesProvider).when(
                    data: (options) {
                      final current = _title.text.trim();
                      // Keep a legacy free-text title selectable when editing.
                      final items = [
                        ...options,
                        if (current.isNotEmpty && !options.contains(current)) current,
                      ];
                      return DropdownButtonFormField<String>(
                        value: current.isEmpty ? null : current,
                        isExpanded: true,
                        hint: const Text('Select a purpose'),
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.flag_rounded, size: 20)),
                        items: [
                          for (final t in items)
                            DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (v) => setState(() => _title.text = v ?? ''),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                    // Lookup unavailable → fall back to free text so saving still works.
                    error: (_, __) => TextField(
                      controller: _title,
                      maxLength: 150,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: const [TitleCaseTextFormatter()],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'From',
                  required: true,
                  child: _BranchField(controller: _from, hint: 'Type or pick a branch'),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Destination',
                  required: true,
                  child: _BranchField(controller: _destination, hint: 'Type or pick a branch'),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Travel mode',
                  required: true,
                  child: DropdownButtonFormField<String>(
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
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Dates and cost'),
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
                const SizedBox(height: 14),
                ProField(
                  label: 'Estimated cost',
                  child: TextField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(prefixText: '₹ '),
                  ),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Purpose',
                  child: TextField(
                    controller: _purpose,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                  ),
                ),
              ],
            ),
          ),
          if (_isEdit && widget.plan!.attachments.isNotEmpty) ...[
            // Legacy plan attachments stay viewable; new uploads happen on the
            // CLAIM raised for this plan (policy 2026-07-04).
            const SizedBox(height: 22),
            ProSectionHeader(
              title: 'Existing attachments',
              subtitle: '${widget.plan!.attachments.length} file(s)',
            ),
            const SizedBox(height: 10),
            ProListGroup(
              children: [
                for (final att in widget.plan!.attachments)
                  _ExistingAttachmentTile(att: att),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
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
                : (_isEdit ? 'Save changes' : 'Create plan')),
          ),
        ],
      ),
    );
  }
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
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: AppColors.surface,
              elevation: 6,
              shadowColor: const Color(0x330B1D21),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                side: const BorderSide(color: AppColors.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 240,
                  maxWidth: constraints.maxWidth,
                ),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1, indent: 56, color: AppColors.hairlineSoft),
                  itemBuilder: (_, i) {
                    final label = options.elementAt(i);
                    return ProListRow(
                      dense: true,
                      chevron: false,
                      leading: ProIconWell(
                          icon: Icons.store_mall_directory_rounded,
                          color: AppColors.primary,
                          size: 30),
                      title: label,
                      onTap: () => onSelected(label),
                    );
                  },
                ),
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
    // The label keeps its trailing " *" marker; render it the ProField way.
    final required = label.endsWith(' *');
    return ProField(
      label: required ? label.substring(0, label.length - 2) : label,
      required: required,
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

class _ExistingAttachmentTile extends StatelessWidget {
  const _ExistingAttachmentTile({required this.att});
  final TravelAttachment att;

  @override
  Widget build(BuildContext context) {
    return ProListRow(
      leading: ProIconWell(icon: Icons.description_rounded, color: AppColors.primary),
      title: att.fileName ?? 'Attachment',
      chevron: false,
      trailing: const Icon(Icons.open_in_new_rounded, size: 17, color: AppColors.muted),
      onTap: () async {
        final url = Env.fileUrl(att.downloadUrl);
        if (url == null) return;
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
    );
  }
}
