import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_dynamic_form.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';

/// Raise a helpdesk ticket. Org context is attached server-side from the raiser.
class HelpdeskRaiseScreen extends ConsumerStatefulWidget {
  const HelpdeskRaiseScreen({super.key});

  @override
  ConsumerState<HelpdeskRaiseScreen> createState() => _HelpdeskRaiseScreenState();
}

class _HelpdeskRaiseScreenState extends ConsumerState<HelpdeskRaiseScreen> {
  final _title = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  String _priority = 'MEDIUM';
  bool _saving = false;
  String? _error;

  List<HdCategory> _categories = [];
  int? _categoryId;
  List<HdTicketType> _types = [];
  int? _ticketTypeId;
  HdFormVersion? _form;
  final Map<String, dynamic> _formValues = {};
  Map<String, String> _formErrors = {};
  List<HdKbSuggestion> _suggestions = [];
  Timer? _suggestDebounce;

  void _onTitleChanged(String v) {
    _suggestDebounce?.cancel();
    if (v.trim().length < 4) { setState(() => _suggestions = []); return; }
    _suggestDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final s = await ref.read(helpdeskRepositoryProvider).suggestArticles(v.trim());
        if (mounted) setState(() => _suggestions = s);
      } catch (_) {/* ignore */}
    });
  }

  @override
  void initState() {
    super.initState();
    ref.read(helpdeskRepositoryProvider).listCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {/* categories are optional; fall back to free-text */});
  }

  Future<void> _loadTypes(int? categoryId) async {
    setState(() { _ticketTypeId = null; _types = []; _clearForm(); });
    if (categoryId == null) return;
    try {
      final t = await ref.read(helpdeskRepositoryProvider).listTicketTypes(categoryId);
      if (mounted) setState(() => _types = t);
    } catch (_) {/* ignore */}
  }

  void _clearForm() { _form = null; _formValues.clear(); _formErrors = {}; }

  Future<void> _loadForm(int? ticketTypeId) async {
    setState(_clearForm);
    if (ticketTypeId == null) return;
    try {
      final f = await ref.read(helpdeskRepositoryProvider).getActiveForm(ticketTypeId);
      if (!mounted || f == null) return;
      setState(() {
        _form = f;
        for (final field in f.fields) {
          if (field.defaultValue != null) _formValues[field.key] = field.defaultValue;
        }
      });
    } catch (_) {/* ignore */}
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _title.dispose();
    _category.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a title.');
      return;
    }
    if (_form != null) {
      final errs = hdValidateForm(_form!.fields, _formValues);
      if (errs.isNotEmpty) {
        setState(() { _formErrors = errs; _error = 'Please fix the highlighted form fields.'; });
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final t = await ref.read(helpdeskRepositoryProvider).create(
            title: _title.text.trim(),
            description: _description.text.trim(),
            category: _categoryId == null ? _category.text.trim() : null,
            categoryId: _categoryId,
            ticketTypeId: _ticketTypeId,
            formResponse: _form == null ? null : hdVisibleValues(_form!.fields, _formValues),
            priority: _priority,
          );
      ref.invalidate(helpdeskTicketsProvider('mine'));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ticket ${t.summary.ticketNumber} raised')));
        context.pushReplacement('/helpdesk/tickets/${t.id}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          title: const Text('Raise a Ticket'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _label('Title *'),
            TextField(controller: _title, maxLength: 200, onChanged: _onTitleChanged),
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('These articles might help:',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    const SizedBox(height: 4),
                    for (final s in _suggestions)
                      InkWell(
                        onTap: () => context.push('/helpdesk/kb/${s.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text('• ${s.title}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.primary)),
                        ),
                      ),
                  ],
                ),
              ),
            _label('Category'),
            if (_categories.isNotEmpty)
              DropdownButtonFormField<int>(
                value: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined, size: 20)),
                hint: const Text('Select category'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c.id,
                        child: Text(c.departmentName != null ? '${c.departmentName} · ${c.name}' : c.name,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) { setState(() => _categoryId = v); _loadTypes(v); },
              )
            else
              TextField(controller: _category,
                  decoration: const InputDecoration(hintText: 'e.g. IT, Payroll, Attendance')),
            if (_types.isNotEmpty) ...[
              const SizedBox(height: 12),
              _label('Ticket type'),
              DropdownButtonFormField<int>(
                value: _ticketTypeId,
                isExpanded: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.label_outline, size: 20)),
                hint: const Text('Select type'),
                items: [for (final t in _types) DropdownMenuItem(value: t.id, child: Text(t.name))],
                onChanged: (v) { setState(() => _ticketTypeId = v); _loadForm(v); },
              ),
            ],
            if (_form != null && _form!.fields.isNotEmpty) ...[
              const SizedBox(height: 12),
              _label('Additional details'),
              HelpdeskDynamicForm(
                fields: _form!.fields,
                values: _formValues,
                errors: _formErrors,
                onChanged: (k, v) => setState(() => _formValues[k] = v),
              ),
            ],
            const SizedBox(height: 12),
            _label('Priority'),
            DropdownButtonFormField<String>(
              value: _priority,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.flag_outlined, size: 20)),
              items: [
                for (final p in kHelpdeskPriorities) DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'MEDIUM'),
            ),
            const SizedBox(height: 12),
            _label('Description'),
            TextField(controller: _description, minLines: 4, maxLines: 8),
            const SizedBox(height: 8),
            const Text('Your branch, department, region and reporting manager are attached automatically.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AppErrorPanel(message: _error!),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? 'Submitting…' : 'Submit Ticket'),
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
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );
}
