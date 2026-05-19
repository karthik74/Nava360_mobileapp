import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'task_models.dart';

/// Renders a [FormSchema] into editable widgets.
/// The caller owns `values` and gets a callback per change.
class FormRenderer extends StatelessWidget {
  const FormRenderer({
    super.key,
    required this.schema,
    required this.values,
    required this.onChanged,
    this.readOnly = false,
    this.errors = const {},
  });

  final FormSchema schema;
  final FormValues values;
  final void Function(String name, dynamic value) onChanged;
  final bool readOnly;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    final visible = schema.fields.where((f) => isFieldVisible(f, values)).toList();
    if (visible.isEmpty) {
      return Text(
        'This task has no form fields.',
        style: TextStyle(color: Theme.of(context).hintColor),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in visible) ...[
          _FieldBlock(
            field: f,
            value: values[f.name],
            onChanged: (v) => onChanged(f.name, v),
            readOnly: readOnly,
            error: errors[f.name],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// Validates [values] against [schema]. Returns a map of fieldName → error message.
/// Empty map means valid. Hidden fields are skipped.
Map<String, String> validateForm(FormSchema schema, FormValues values) {
  final out = <String, String>{};
  for (final f in schema.fields) {
    if (!isFieldVisible(f, values)) continue;
    // Assigned fields are owned by the admin — skip validation here.
    if (f.assigned) continue;
    final v = values[f.name];
    final empty = v == null || v == '' || (v is List && v.isEmpty);
    if (f.required && empty) {
      out[f.name] = 'Required';
      continue;
    }
    if (empty) continue;
    if (v is String) {
      if (f.minLength != null && v.length < f.minLength!) {
        out[f.name] = 'Must be at least ${f.minLength} characters';
        continue;
      }
      if (f.maxLength != null && v.length > f.maxLength!) {
        out[f.name] = 'Must be at most ${f.maxLength} characters';
        continue;
      }
    }
    if (f.type == FieldType.number) {
      final n = v is num ? v : num.tryParse('$v');
      if (n != null) {
        if (f.min != null && n < f.min!) {
          out[f.name] = 'Must be ≥ ${f.min}';
          continue;
        }
        if (f.max != null && n > f.max!) {
          out[f.name] = 'Must be ≤ ${f.max}';
          continue;
        }
      }
    }
    if (f.type == FieldType.mobile && v is String && !RegExp(r'^\d+$').hasMatch(v)) {
      out[f.name] = 'Digits only';
      continue;
    }
    if (f.type == FieldType.daterange && v is Map) {
      final from = v['from'] as String?;
      final to = v['to'] as String?;
      if (from != null && to != null && from.compareTo(to) > 0) {
        out[f.name] = 'End date must be after start date';
        continue;
      }
    }
  }
  return out;
}

class _FieldBlock extends StatelessWidget {
  const _FieldBlock({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.readOnly,
    this.error,
  });

  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  final bool readOnly;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final showInlineLabel =
        field.type != FieldType.checkbox; // checkbox renders own legend
    // Assigned fields are locked to the assignee — force read-only here.
    final effectiveReadOnly = readOnly || field.assigned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showInlineLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      children: [
                        TextSpan(text: field.label),
                        if (field.required && !field.assigned)
                          const TextSpan(
                            text: ' *',
                            style: TextStyle(color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                ),
                if (field.assigned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Provided',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4F46E5),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        _FieldInput(
          field: field,
          value: value,
          onChanged: onChanged,
          readOnly: effectiveReadOnly,
        ),
        if (field.helpText != null && field.helpText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              field.helpText!,
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.readOnly,
  });

  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  final bool readOnly;

  String _asString() => value == null ? '' : value.toString();

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case FieldType.text:
      case FieldType.email:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          keyboardType: field.type == FieldType.email
              ? TextInputType.emailAddress
              : TextInputType.text,
          decoration: InputDecoration(
            hintText: field.placeholder,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          maxLength: field.maxLength,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.textarea:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: field.placeholder,
            border: const OutlineInputBorder(),
          ),
          maxLength: field.maxLength,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.number:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(
            hintText: field.placeholder,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (s) {
            if (s.isEmpty) return onChanged(null);
            final n = num.tryParse(s);
            onChanged(n ?? s);
          },
        );

      case FieldType.mobile:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: field.maxLength ?? 15,
          decoration: InputDecoration(
            hintText: field.placeholder ?? '10-digit mobile number',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      case FieldType.date:
        return _DateField(
          value: _asString(),
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.time:
        return _TimeField(
          value: _asString(),
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.day:
        return _Dropdown(
          value: _asString().isEmpty ? null : _asString(),
          items: const [
            'Monday', 'Tuesday', 'Wednesday', 'Thursday',
            'Friday', 'Saturday', 'Sunday',
          ],
          placeholder: field.placeholder ?? 'Select day',
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.select:
        return _Dropdown(
          value: _asString().isEmpty ? null : _asString(),
          items: field.options,
          placeholder: field.placeholder ?? 'Select',
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.radio:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final o in field.options)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(o),
                value: o,
                groupValue: _asString().isEmpty ? null : _asString(),
                onChanged: readOnly ? null : (v) => onChanged(v),
              ),
          ],
        );

      case FieldType.checkbox:
        final selected = (value is List)
            ? (value as List).cast<String>().toSet()
            : <String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  children: [
                    TextSpan(text: field.label),
                    if (field.required)
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),
            ),
            for (final o in field.options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(o),
                value: selected.contains(o),
                onChanged: readOnly
                    ? null
                    : (v) {
                        final next = {...selected};
                        if (v == true) {
                          next.add(o);
                        } else {
                          next.remove(o);
                        }
                        onChanged(next.toList());
                      },
              ),
          ],
        );

      case FieldType.daterange:
        final m = (value is Map) ? Map<String, dynamic>.from(value) : {'from': '', 'to': ''};
        return Row(
          children: [
            Expanded(
              child: _DateField(
                value: (m['from'] ?? '') as String,
                readOnly: readOnly,
                onChanged: (s) => onChanged({'from': s, 'to': m['to'] ?? ''}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DateField(
                value: (m['to'] ?? '') as String,
                readOnly: readOnly,
                onChanged: (s) => onChanged({'from': m['from'] ?? '', 'to': s}),
              ),
            ),
          ],
        );

      case FieldType.file:
      case FieldType.multiimage:
        // First-pass mobile: file/image upload is not yet wired up.
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.10),
            border: Border.all(color: Colors.amber.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'File upload for "${field.label}" — use the web app for now.',
            style: const TextStyle(fontSize: 12),
          ),
        );
    }
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.placeholder,
    required this.readOnly,
    required this.onChanged,
  });

  final String? value;
  final List<String> items;
  final String placeholder;
  final bool readOnly;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      hint: Text(placeholder),
      items: items
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: readOnly ? null : onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String value;
  final bool readOnly;
  final void Function(String) onChanged;

  String _format(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pick(BuildContext context) async {
    if (readOnly) return;
    final initial = DateTime.tryParse(value) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5),
    );
    if (picked != null) onChanged(_format(picked));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          value.isEmpty ? 'Select date' : value,
          style: TextStyle(
            color: value.isEmpty ? Theme.of(context).hintColor : null,
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String value;
  final bool readOnly;
  final void Function(String) onChanged;

  Future<void> _pick(BuildContext context) async {
    if (readOnly) return;
    TimeOfDay initial = TimeOfDay.now();
    if (value.isNotEmpty) {
      final parts = value.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
      }
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      onChanged('$hh:$mm');
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.schedule, size: 18),
        ),
        child: Text(
          value.isEmpty ? 'Select time' : value,
          style: TextStyle(
            color: value.isEmpty ? Theme.of(context).hintColor : null,
          ),
        ),
      ),
    );
  }
}
