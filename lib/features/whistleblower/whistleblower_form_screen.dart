import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/employee_lookup.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
            SizedBox(height: 12),
            Text('Submitted successfully',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            SizedBox(height: 6),
            Text('Your concern has been received and will be handled confidentially.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(); // back to the dashboard
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a Concern')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            color: AppColors.info.withOpacity(0.06),
            shadow: AppShadows.soft,
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.info),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your report will be handled confidentially. Please provide accurate and genuine information.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _label('Category *'),
          DropdownButtonFormField<String>(
            value: _category,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined, size: 20)),
            items: [
              for (final c in _categories) DropdownMenuItem(value: c.value, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          _label('Subject *'),
          TextField(
            controller: _subject,
            maxLength: 200,
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseTextFormatter()],
          ),
          _label('Description *'),
          TextField(
            controller: _description,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseTextFormatter()],
          ),
          const SizedBox(height: 12),
          _label('Incident Date'),
          InkWell(
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
              decoration: const InputDecoration(prefixIcon: Icon(Icons.event_rounded, size: 20)),
              child: Text(
                _incidentDate == null ? 'Not set' : DateFormat('d MMM yyyy').format(_incidentDate!),
                style: TextStyle(color: _incidentDate == null ? AppColors.muted : AppColors.ink),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _label('Branch / Department involved'),
          TextField(
            controller: _department,
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseTextFormatter()],
          ),
          const SizedBox(height: 12),
          _label('Person(s) involved'),
          _PersonSelector(
            selected: _selectedPersons,
            onAdd: (e) => setState(() {
              if (!_selectedPersons.contains(e)) _selectedPersons.add(e);
            }),
            onRemove: (e) => setState(() => _selectedPersons.remove(e)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _persons,
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseTextFormatter()],
            decoration: const InputDecoration(
              hintText: 'Add others not in the directory (optional)',
              prefixIcon: Icon(Icons.person_add_alt_1_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: const Text('Submit anonymously'),
            subtitle: const Text('Your name will be hidden from reviewers.'),
          ),
          const SizedBox(height: 8),
          EvidenceSection(evidence: _evidence, onChanged: () => setState(() {})),
          const SizedBox(height: 16),
          const Text(
            'Please ensure the uploaded evidence is genuine and relevant to the concern raised.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          GlassCard(
            color: AppColors.warning.withOpacity(0.08),
            shadow: AppShadows.soft,
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'False or malicious complaints may lead to disciplinary action as per company policy.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppErrorPanel(message: _error!),
          ],
          const SizedBox(height: 18),
          if (_submitting && _progress > 0 && _progress < 1) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Submit Report'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in widget.selected)
                  Chip(
                    label: Text(e.label, style: const TextStyle(fontSize: 12)),
                    onDeleted: () => widget.onRemove(e),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.10),
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
              padding: EdgeInsets.only(top: 6),
              child: Text('Could not search employees', style: TextStyle(fontSize: 12, color: AppColors.danger)),
            ),
            data: (list) {
              final available = list.where((e) => !widget.selected.contains(e)).toList();
              if (available.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No matching employees', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                );
              }
              return Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final e in available)
                      ListTile(
                        dense: true,
                        title: Text(e.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: e.code == null ? null : Text(e.code!, style: const TextStyle(fontSize: 11.5)),
                        trailing: const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.primary),
                        onTap: () => _add(e),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
