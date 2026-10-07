import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import 'helpdesk_models.dart';

const _numeric = {'number', 'currency', 'percentage', 'rating'};

bool hdFieldVisible(HdFormField f, Map<String, dynamic> values) {
  if (f.hidden) return false;
  if (f.visibleWhenField == null || f.visibleWhenField!.isEmpty) return true;
  return (values[f.visibleWhenField]?.toString() ?? '') == (f.visibleWhenEquals ?? '');
}

String _asString(dynamic raw) {
  if (raw == null) return '';
  if (raw is List) return raw.join(', ');
  return raw.toString().trim();
}

/// Validate visible fields; returns { key: message } (empty = valid).
Map<String, String> hdValidateForm(List<HdFormField> fields, Map<String, dynamic> values) {
  final errors = <String, String>{};
  for (final f in fields) {
    if (!hdFieldVisible(f, values)) continue;
    final val = _asString(values[f.key]);
    if (f.required && val.isEmpty) { errors[f.key] = '${f.label} is required.'; continue; }
    if (val.isEmpty) continue;
    if (f.regex != null && f.regex!.isNotEmpty) {
      try { if (!RegExp(f.regex!).hasMatch(val)) errors[f.key] = '${f.label} is invalid.'; } catch (_) {}
    }
    if (errors[f.key] == null && _numeric.contains(f.type)) {
      final n = double.tryParse(val);
      if (n == null) {
        errors[f.key] = '${f.label} must be a number.';
      } else if (f.min != null && n < f.min!) {
        errors[f.key] = '${f.label} must be at least ${f.min}.';
      } else if (f.max != null && n > f.max!) {
        errors[f.key] = '${f.label} must be at most ${f.max}.';
      }
    }
  }
  return errors;
}

/// Only the values for currently-visible fields (what we submit).
Map<String, dynamic> hdVisibleValues(List<HdFormField> fields, Map<String, dynamic> values) {
  final out = <String, dynamic>{};
  for (final f in fields) { if (hdFieldVisible(f, values)) out[f.key] = values[f.key]; }
  return out;
}

/// Renders a dynamic form schema. Parent owns [values]; changes flow via [onChanged].
class HelpdeskDynamicForm extends StatelessWidget {
  const HelpdeskDynamicForm({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.errors = const {},
  });

  final List<HdFormField> fields;
  final Map<String, dynamic> values;
  final void Function(String key, dynamic value) onChanged;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    final visible = fields.where((f) => hdFieldVisible(f, values)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: visible[i].label),
              if (visible[i].required)
                const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
            ]),
            style: AppText.label,
          ),
          const SizedBox(height: 6),
          _input(context, visible[i]),
          if (visible[i].helpText != null && visible[i].helpText!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 5),
                child: Text(visible[i].helpText!, style: AppText.caption)),
          if (errors[visible[i].key] != null)
            Padding(padding: const EdgeInsets.only(top: 5),
                child: Text(errors[visible[i].key]!,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.danger))),
        ],
      ],
    );
  }

  Widget _input(BuildContext context, HdFormField f) {
    final str = _asString(values[f.key]);
    switch (f.type) {
      case 'textarea':
      case 'richtext':
        return TextFormField(
          key: ValueKey('${f.key}_ta'),
          initialValue: str,
          minLines: 3, maxLines: 6,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          onChanged: (v) => onChanged(f.key, v),
        );
      case 'number':
      case 'currency':
      case 'percentage':
        return TextFormField(
          key: ValueKey('${f.key}_num'),
          initialValue: str,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => onChanged(f.key, v),
        );
      case 'email':
        return _text(f, str, keyboard: TextInputType.emailAddress);
      case 'mobile':
        return _text(f, str, keyboard: TextInputType.phone);
      case 'url':
        return _text(f, str, keyboard: TextInputType.url);
      case 'rating':
        final maxN = (f.max ?? 5).toInt();
        final minN = (f.min ?? 1).toInt();
        return DropdownButtonFormField<String>(
          value: str.isEmpty ? null : str,
          isExpanded: true,
          items: [for (var n = minN; n <= maxN; n++) DropdownMenuItem(value: '$n', child: Text('$n'))],
          onChanged: (v) => onChanged(f.key, v),
        );
      case 'dropdown':
        return DropdownButtonFormField<String>(
          value: str.isEmpty ? null : str,
          isExpanded: true,
          hint: Text(f.placeholder ?? 'Select…'),
          items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => onChanged(f.key, v),
        );
      case 'radio':
        return Column(
          children: [
            for (final o in f.options)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero, dense: true,
                title: Text(o), value: o, groupValue: str.isEmpty ? null : str,
                onChanged: (v) => onChanged(f.key, v),
              ),
          ],
        );
      case 'checkbox':
        if (f.options.isEmpty) {
          final b = values[f.key] == true;
          return CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true,
              title: const Text('Yes'), value: b, onChanged: (v) => onChanged(f.key, v ?? false));
        }
        final sel = (values[f.key] is List) ? List<String>.from(values[f.key] as List) : <String>[];
        return Column(children: [
          for (final o in f.options)
            CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true,
                title: Text(o), value: sel.contains(o),
                onChanged: (v) {
                  final next = [...sel];
                  if (v == true) { next.add(o); } else { next.remove(o); }
                  onChanged(f.key, next);
                }),
        ]);
      case 'date':
        return _DateField(value: str, onPick: (d) => onChanged(f.key, d));
      case 'time':
        return _text(f, str, hint: 'HH:mm');
      case 'file':
      case 'image':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Icon(f.type == 'image' ? Icons.image_outlined : Icons.attach_file_rounded,
                  size: 18, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Use the ticket attachments to add ${f.type == 'image' ? 'images' : 'files'}.',
                    style: AppText.caption),
              ),
            ],
          ),
        );
      default:
        return _text(f, str, titleCase: true);
    }
  }

  Widget _text(HdFormField f, String str,
          {TextInputType? keyboard, String? hint, bool titleCase = false}) =>
      TextFormField(
        key: ValueKey('${f.key}_t'),
        initialValue: str,
        keyboardType: keyboard,
        textCapitalization:
            titleCase ? TextCapitalization.words : TextCapitalization.none,
        inputFormatters: titleCase ? const [TitleCaseTextFormatter()] : null,
        decoration: InputDecoration(hintText: hint ?? f.placeholder),
        onChanged: (v) => onChanged(f.key, v),
      );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onPick});
  final String value;
  final void Function(String iso) onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final init = DateTime.tryParse(value) ?? DateTime.now();
        final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2015), lastDate: DateTime(2035));
        if (d != null) onPick(DateFormat('yyyy-MM-dd').format(d));
      },
      child: InputDecorator(
        decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_rounded, size: 18)),
        child: Text(value.isEmpty ? 'Select date' : value,
            style: TextStyle(fontSize: 15, color: value.isEmpty ? AppColors.faint : AppColors.ink)),
      ),
    );
  }
}
