import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import 'helpdesk_dynamic_form.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';
import 'helpdesk_tickets_screen.dart' show helpdeskStatusLabel;

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
    final typeName = _ticketTypeId == null
        ? null
        : _types.where((t) => t.id == _ticketTypeId).map((t) => t.name).firstOrNull;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Raise a ticket',
        subtitle: 'Helpdesk',
        actions: [
          IconButton(
            tooltip: 'Knowledge base',
            icon: const Icon(Icons.menu_book_outlined, size: 21),
            onPressed: () => context.push('/helpdesk/kb'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Ticket'),
                const SizedBox(height: 12),
                ProField(
                  label: 'Title',
                  required: true,
                  child: TextField(
                    controller: _title,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                    onChanged: _onTitleChanged,
                    decoration: const InputDecoration(
                        hintText: 'e.g. Laptop battery drains within an hour'),
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 2, bottom: 4),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('These articles might help',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                        const SizedBox(height: 4),
                        for (final s in _suggestions)
                          InkWell(
                            onTap: () => context.push('/helpdesk/kb/${s.id}'),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Icon(Icons.article_outlined,
                                      size: 16, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(s.title,
                                        style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.primary)),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 18, color: AppColors.primary),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                ProField(
                  label: 'Category',
                  child: _categories.isNotEmpty
                      ? DropdownButtonFormField<int>(
                          value: _categoryId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.category_outlined, size: 20)),
                          hint: const Text('Select category'),
                          items: [
                            for (final c in _categories)
                              DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                      c.departmentName != null
                                          ? '${c.departmentName} · ${c.name}'
                                          : c.name,
                                      overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            setState(() => _categoryId = v);
                            _loadTypes(v);
                          },
                        )
                      : TextField(
                          controller: _category,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          decoration: const InputDecoration(
                              hintText: 'e.g. IT, Payroll, Attendance')),
                ),
                if (_types.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ProField(
                    label: 'Ticket type',
                    child: DropdownButtonFormField<int>(
                      value: _ticketTypeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.label_outline, size: 20)),
                      hint: const Text('Select type'),
                      items: [
                        for (final t in _types)
                          DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (v) {
                        setState(() => _ticketTypeId = v);
                        _loadForm(v);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_form != null && _form!.fields.isNotEmpty) ...[
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title: 'Additional details',
                    trailing: typeName == null
                        ? null
                        : Flexible(
                            child: Text(typeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: AppText.caption),
                          ),
                  ),
                  const SizedBox(height: 12),
                  HelpdeskDynamicForm(
                    fields: _form!.fields,
                    values: _formValues,
                    errors: _formErrors,
                    onChanged: (k, v) => setState(() => _formValues[k] = v),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Priority and description'),
                const SizedBox(height: 12),
                ProField(
                  label: 'Priority',
                  child: _PrioritySegmented(
                    value: _priority,
                    onChanged: (v) => setState(() => _priority = v),
                  ),
                ),
                const SizedBox(height: 14),
                ProField(
                  label: 'Description',
                  child: TextField(
                    controller: _description,
                    minLines: 4,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseTextFormatter()],
                    decoration: const InputDecoration(
                        hintText: 'What happened, since when, and what you have already tried'),
                  ),
                ),
                const SizedBox(height: 14),
                const ProNote(
                  'Your branch, department, region and reporting manager are attached automatically.',
                  tone: ProNoteTone.info,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            ProNote(_error!, tone: ProNoteTone.bad),
          ],
        ],
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Submitting…' : 'Submit ticket'),
          ),
        ],
      ),
    );
  }
}

/// Light segmented priority picker with tone dots (Low → Critical).
class _PrioritySegmented extends StatelessWidget {
  const _PrioritySegmented({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static Color _dot(String p) => switch (p) {
        'CRITICAL' => const Color(0xFFE5484D),
        'HIGH' => const Color(0xFFF2B347),
        'MEDIUM' => const Color(0xFF5AA9F0),
        _ => const Color(0xFFB3C0C3),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDBE3E5)),
      ),
      child: Row(
        children: [
          for (final p in kHelpdeskPriorities)
            Expanded(
              child: Semantics(
                selected: p == value,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: p == value ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: p == value ? AppShadows.card : null,
                      border: p == value ? Border.all(color: AppColors.hairline) : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: _dot(p), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            helpdeskStatusLabel(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: p == value ? FontWeight.w600 : FontWeight.w500,
                              color: p == value ? AppColors.ink : AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
