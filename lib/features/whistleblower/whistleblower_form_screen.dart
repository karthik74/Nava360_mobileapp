import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/employee_lookup.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import 'whistleblower_evidence.dart';
import 'whistleblower_models.dart';
import 'whistleblower_repository.dart';

class WhistleblowerFormScreen extends ConsumerStatefulWidget {
  const WhistleblowerFormScreen({super.key});

  @override
  ConsumerState<WhistleblowerFormScreen> createState() => _WhistleblowerFormScreenState();
}

class _WhistleblowerFormScreenState extends ConsumerState<WhistleblowerFormScreen> {
  List<WbCategoryOption> _categories = [];
  String? _category;
  final _subject = TextEditingController();
  final _description = TextEditingController();
  DateTime? _incidentDate;
  final _department = TextEditingController();
  final _persons = TextEditingController();
  final List<EmployeeLookup> _selectedPersons = [];
  bool _anonymous = false;
  final List<EvidenceFile> _evidence = [];

  bool _submitting = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(whistleblowerRepositoryProvider).categories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    _department.dispose();
    _persons.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_category == null) {
      setState(() => _error = 'Please choose a category.');
      return;
    }
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Subject and description are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _progress = 0;
    });
    try {
      await ref.read(whistleblowerRepositoryProvider).createCase(
            category: _category!,
            subject: _subject.text.trim(),
            description: _description.text.trim(),
            incidentDate: _incidentDate,
            department: _department.text,
            personsInvolved: _personsInvolvedValue(),
            anonymous: _anonymous,
            evidence: _evidence,
            onProgress: (s, t) {
              if (mounted && t > 0) setState(() => _progress = s / t);
            },
          );
      if (mounted) await _showSubmitted();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _personsInvolvedValue() {
    final parts = <String>[
      ..._selectedPersons.map((e) => e.label),
      if (_persons.text.trim().isNotEmpty) _persons.text.trim(),
    ];
    return parts.join(', ');
  }

  Future<void> _showSubmitted() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.successTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.success, size: 32),
            ),
            const SizedBox(height: 14),
            const Text('Submitted successfully',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.35,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text('Your concern has been received and will be handled confidentially.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.45)),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(); // back to the dashboard
  }

  @override
  Widget build(BuildContext context) {
    final uploading = _submitting && _progress > 0 && _progress < 1;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Report a concern',
        subtitle: 'Confidential · handled by the review team',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ConfidentialCard(anonymous: _anonymous),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Your concern'),
                const SizedBox(height: 12),
                ProField(
                  label: 'Category',
                  required: true,
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    isExpanded: true,
                    hint: const Text('Choose a category'),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.category_outlined, size: 20)),
                    items: [
                      for (final c in _categories)
                        DropdownMenuItem(value: c.value, child: Text(c.label)),
                    ],
                    onChanged: (v) => setState(() => _category = v),
                  ),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Subject',
                  required: true,
                  child: TextField(
                    controller: _subject,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                    decoration: const InputDecoration(
                        hintText: 'A short line about what happened'),
                  ),
                ),
                const SizedBox(height: 4),
                ProField(
                  label: 'Description',
                  required: true,
                  child: TextField(
                    controller: _description,
                    minLines: 4,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                    decoration: const InputDecoration(
                        hintText: 'What happened, when and where, and who saw it'),
                  ),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Incident date',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _incidentDate ?? DateTime.now(),
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _incidentDate = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.event_rounded, size: 20)),
                      child: Text(
                        _incidentDate == null ? 'Not set' : DateFormat('d MMM yyyy').format(_incidentDate!),
                        style: TextStyle(
                            fontSize: 15,
                            color: _incidentDate == null ? AppColors.faint : AppColors.ink),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Branch or department involved',
                  child: TextField(
                    controller: _department,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                    decoration: const InputDecoration(hintText: 'e.g. Branch, team or counter'),
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
                ProSectionHeader(
                  title: 'People involved',
                  trailing: _selectedPersons.isEmpty
                      ? null
                      : ProPill.info('${_selectedPersons.length}'),
                ),
                const SizedBox(height: 12),
                _PersonSelector(
                  selected: _selectedPersons,
                  onAdd: (e) => setState(() {
                    if (!_selectedPersons.contains(e)) _selectedPersons.add(e);
                  }),
                  onRemove: (e) => setState(() => _selectedPersons.remove(e)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _persons,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [TitleCaseTextFormatter()],
                  decoration: const InputDecoration(
                    hintText: 'Add others not in the directory (optional)',
                    prefixIcon: Icon(Icons.person_add_alt_1_outlined, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const ProIconWell(
                  icon: Icons.visibility_off_outlined, color: AppColors.info),
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
              title: const Text('Submit anonymously'),
              subtitle: const Text('Your name will be hidden from reviewers.'),
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EvidenceSection(evidence: _evidence, onChanged: () => setState(() {})),
                const SizedBox(height: 12),
                const Text(
                  'Please ensure the uploaded evidence is genuine and relevant to the concern raised.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const ProNote(
            'False or malicious complaints may lead to disciplinary action as per company policy.',
            tone: ProNoteTone.neutral,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ProNote(_error!, tone: ProNoteTone.warn),
          ],
        ],
      ),
      bottomNavigationBar: ProBottomBar(
        top: uploading
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Uploading evidence',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF43585D))),
                      ),
                      Text('${(_progress * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF43585D),
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: _progress, minHeight: 6),
                  ),
                ],
              )
            : null,
        children: [
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Submitting…' : 'Submit report'),
          ),
        ],
      ),
    );
  }
}

/// Deep confidentiality banner with the current anonymity status.
class _ConfidentialCard extends StatelessWidget {
  const _ConfidentialCard({required this.anonymous});
  final bool anonymous;

  @override
  Widget build(BuildContext context) {
    return ProDeepSurface(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Your report will be handled confidentially. Please provide accurate and genuine information.',
                  style: TextStyle(
                      fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Container(
              key: ValueKey(anonymous),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(anonymous ? Icons.visibility_off_outlined : Icons.person_outline_rounded,
                      size: 17, color: const Color(0xE0FFFFFF)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      anonymous
                          ? 'Reporting anonymously. Your name will be hidden from reviewers.'
                          : 'Reporting with your name. Turn on “Submit anonymously” to hide it.',
                      style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xE0FFFFFF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Multi-select employee picker: search the org directory and add one or more
/// employees as chips. Backed by the slim /api/employees/lookup endpoint.
class _PersonSelector extends ConsumerStatefulWidget {
  const _PersonSelector({required this.selected, required this.onAdd, required this.onRemove});
  final List<EmployeeLookup> selected;
  final ValueChanged<EmployeeLookup> onAdd;
  final ValueChanged<EmployeeLookup> onRemove;

  @override
  ConsumerState<_PersonSelector> createState() => _PersonSelectorState();
}

class _PersonSelectorState extends ConsumerState<_PersonSelector> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _add(EmployeeLookup e) {
    widget.onAdd(e);
    _searchCtrl.clear();
    setState(() => _query = '');
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.trim().length >= 2
        ? ref.watch(employeeLookupProvider(_query.trim()))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in widget.selected)
                  Chip(
                    label: Text(e.label),
                    labelStyle: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                    onDeleted: () => widget.onRemove(e),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    deleteIconColor: AppColors.primary,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                    side: BorderSide.none,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          decoration: const InputDecoration(
            hintText: 'Search employees by name or code',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
        ),
        if (results != null)
          results.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (e, _) => const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Could not search employees',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF9A5B00))),
            ),
            data: (list) {
              final available = list.where((e) => !widget.selected.contains(e)).toList();
              if (available.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No matching employees', style: AppText.caption),
                );
              }
              return Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: available.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56, color: AppColors.hairlineSoft),
                  itemBuilder: (_, i) {
                    final e = available[i];
                    return ProListRow(
                      dense: true,
                      chevron: false,
                      leading: ProAvatar(name: e.name, size: 34),
                      title: e.name,
                      subtitle: e.code,
                      trailing: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.add_rounded, size: 19, color: AppColors.primary),
                      ),
                      onTap: () => _add(e),
                    );
                  },
                ),
              );
            },
          ),
      ],
    );
  }
}
