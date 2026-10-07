import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../files/file_repository.dart';
import 'form_field_widgets.dart';
import 'task_models.dart';
import 'task_status_ui.dart' show TaskSheetHeader, kTaskSheetShape;
import 'video_qa/video_qa_field.dart';

/// Resolves a stored relative file url (`/api/files/{id}`) to an absolute URL.
String absoluteFileUrl(String url) {
  if (url.startsWith('http')) return url;
  final base = Env.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$base$url';
}

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
    this.ownerFillsAssigned = false,
    this.sectionCards = false,
  });

  final FormSchema schema;
  final FormValues values;
  final void Function(String name, dynamic value) onChanged;
  final bool readOnly;
  final Map<String, String> errors;

  /// When true, fields the assigner normally pre-fills (`assigned: true`) are
  /// editable and validated — used for self-tasks, where the assignee is also
  /// the assigner and must fill those fields themselves.
  final bool ownerFillsAssigned;

  /// Lay the form out as white cards, one per `section` field (numbered),
  /// instead of a flat column. Use on a canvas background; leave off when the
  /// form already sits inside a card.
  final bool sectionCards;

  Widget _block(FormFieldDef f) => _FieldBlock(
        field: f,
        value: values[f.name],
        onChanged: (v) => onChanged(f.name, v),
        readOnly: readOnly,
        ownerFillsAssigned: ownerFillsAssigned,
        error: errors[f.name],
      );

  @override
  Widget build(BuildContext context) {
    final visible = schema.fields.where((f) => isFieldVisible(f, values)).toList();
    if (visible.isEmpty) {
      const empty = Text(
        'This task has no form fields.',
        style: TextStyle(fontSize: 14, color: AppColors.muted),
      );
      return sectionCards
          ? const GlassCard(child: empty)
          : empty;
    }
    if (!sectionCards) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _block(visible[i]),
          ],
        ],
      );
    }

    // One card per section: a `section` field opens a new card and becomes its
    // numbered header; fields before the first section share an untitled card.
    final groups = <({FormFieldDef? head, int number, List<FormFieldDef> fields})>[];
    var sections = 0;
    for (final f in visible) {
      if (f.type == FieldType.section) {
        sections++;
        groups.add((head: f, number: sections, fields: <FormFieldDef>[]));
      } else {
        if (groups.isEmpty) {
          groups.add((head: null, number: 0, fields: <FormFieldDef>[]));
        }
        groups.last.fields.add(f);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0) const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (groups[g].head != null) ...[
                  _SectionHead(
                    number: groups[g].number,
                    title: groups[g].head!.label,
                    help: groups[g].head!.helpText,
                  ),
                  if (groups[g].fields.isNotEmpty) const SizedBox(height: 16),
                ],
                for (var i = 0; i < groups[g].fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  _block(groups[g].fields[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Numbered card header for a form section.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.number, required this.title, this.help});
  final int number;
  final String title;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.section),
              if (help != null && help!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(help!, style: AppText.caption),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Validates [values] against [schema]. Returns a map of fieldName → error message.
/// Empty map means valid. Hidden fields are skipped.
///
/// [includeAssigned] validates assigner-owned (`assigned: true`) fields too —
/// set for self-tasks, where the assignee fills those fields themselves.
Map<String, String> validateForm(
  FormSchema schema,
  FormValues values, {
  bool includeAssigned = false,
}) {
  final out = <String, String>{};
  for (final f in schema.fields) {
    if (!isFieldVisible(f, values)) continue;
    // Assigned fields are owned by the assigner — skip unless the assignee is
    // also the assigner (self-task).
    if (f.assigned && !includeAssigned) continue;
    // Display-only fields are shown, never filled, never required.
    if (f.readOnly) continue;
    // A section header asks nothing, and a system field is filled for the user.
    // Marking either "required" in the builder must not block a submission the
    // user has no way to complete.
    if (f.type.isLayout || f.type.isSystem) continue;
    final v = values[f.name];
    // A video Q&A answer counts only once the recording has been uploaded: until
    // it carries a url there is nothing attached to the task.
    final empty = f.type == FieldType.videoQa
        ? !(v is Map && ((v['url'] as String?) ?? '').isNotEmpty)
        : (v == null || v == '' || (v is List && v.isEmpty));
    if (f.required && empty) {
      out[f.name] = 'Required';
      continue;
    }
    if (empty) continue;
    if (v is String && !f.type.isCaptured) {
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
    required this.ownerFillsAssigned,
    this.error,
  });

  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  final bool readOnly;
  final bool ownerFillsAssigned;
  final String? error;

  @override
  Widget build(BuildContext context) {
    // Checkbox lists draw their own legend, and layout fields (a section header,
    // a divider) are the label — giving them one too would print it twice.
    final showInlineLabel = field.type != FieldType.checkbox &&
        field.type != FieldType.checklistApproval &&
        !field.type.isLayout &&
        field.type != FieldType.hidden;
    // Assigned fields are normally locked to the assignee. For a self-task the
    // assignee is also the assigner, so they fill these fields themselves.
    final lockedAssigned = field.assigned && !ownerFillsAssigned;
    final effectiveReadOnly = readOnly || lockedAssigned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showInlineLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: _FieldLabel(
                    label: field.label,
                    required:
                        field.required && !lockedAssigned && !field.readOnly,
                  ),
                ),
                if (lockedAssigned)
                  const ProPill(
                    'Provided',
                    color: AppColors.pink,
                    background: Color(0xFFF0EBF7),
                  ),
              ],
            ),
          ),
        if (field.readOnly)
          // Display only, as designed on the template: the placeholder is the fixed
          // note; nothing to type, nothing validated, nothing submitted.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border.all(color: AppColors.hairline),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(
              (field.placeholder ?? '').trim().isEmpty ? '—' : field.placeholder!.trim(),
              style: const TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.4),
            ),
          )
        else
          _FieldInput(
            field: field,
            value: value,
            onChanged: onChanged,
            readOnly: effectiveReadOnly,
          ),
        if (field.helpText != null && field.helpText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(field.helpText!, style: AppText.caption),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 14, color: AppColors.danger),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Field label in the [ProField] style (label above the input, red asterisk).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.required});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: label),
        if (required)
          const TextSpan(
            text: ' *',
            style: TextStyle(color: AppColors.danger),
          ),
      ]),
      style: AppText.label,
    );
  }
}

/// Hairline box holding a list of radio / checkbox options, with dividers.
class _OptionBox extends StatelessWidget {
  const _OptionBox({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.hairlineSoft),
            children[i],
          ],
        ],
      ),
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
          textCapitalization: field.type == FieldType.email
              ? TextCapitalization.none
              : TextCapitalization.words,
          inputFormatters: field.type == FieldType.email
              ? null
              : const [TitleCaseTextFormatter()],
          decoration: InputDecoration(
            hintText: field.placeholder,
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
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          decoration: InputDecoration(
            hintText: field.placeholder,
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
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      case FieldType.date:
      case FieldType.dateofbirth:
        return _DateField(
          value: _asString(),
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.time:
      case FieldType.duration:
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
        return _OptionBox(
          children: [
            for (final o in field.options)
              RadioListTile<String>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                dense: true,
                title: Text(o, style: const TextStyle(fontSize: 14.5)),
                value: o,
                groupValue: _asString().isEmpty ? null : _asString(),
                onChanged: readOnly ? null : (v) => onChanged(v),
              ),
          ],
        );

      case FieldType.checkbox:
      case FieldType.checklistApproval:
        final selected = (value is List)
            ? (value as List).cast<String>().toSet()
            : <String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _FieldLabel(
                        label: field.label, required: field.required),
                  ),
                  if (selected.isNotEmpty)
                    ProPill.neutral('${selected.length} selected'),
                ],
              ),
            ),
            _OptionBox(
              children: [
                for (final o in field.options)
                  CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(o, style: const TextStyle(fontSize: 14.5)),
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

      case FieldType.image:
      case FieldType.webcam:
        // Single image; the template decides gallery / live camera / either.
        return _FileField(
          value: value,
          multi: false,
          imageOnly: true,
          mediaSource: field.mediaSource,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.multiimage:
        return _FileField(
          value: value,
          multi: true,
          imageOnly: true,
          mediaSource: field.mediaSource,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.video:
        return _FileField(
          value: value,
          multi: false,
          video: true,
          mediaSource: field.mediaSource,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.videoQa:
        return VideoQaField(
          label: field.label,
          config: field.videoQa,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.file:
      case FieldType.audio:
        return _FileField(
          value: value,
          multi: false,
          imageOnly: false,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      // ── Basic ──────────────────────────────────────────────────────────
      case FieldType.url:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: field.placeholder ?? 'https://',
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      case FieldType.password:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          obscureText: true,
          decoration: InputDecoration(
            hintText: field.placeholder,
            isDense: true,
          ),
          maxLength: field.maxLength,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.otp:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: field.maxLength ?? 6,
          style: const TextStyle(letterSpacing: 6, fontSize: 18),
          decoration: const InputDecoration(
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      case FieldType.decimal:
        return _NumberField(
          value: _asString(),
          readOnly: readOnly,
          decimal: true,
          hint: field.placeholder,
          onChanged: onChanged,
        );

      // ── Date & time ────────────────────────────────────────────────────
      case FieldType.datetime:
        return _DateTimeField(
          value: _asString(),
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.month:
        return _MonthField(
          value: _asString(),
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.year:
        return _NumberField(
          value: _asString(),
          readOnly: readOnly,
          decimal: false,
          hint: field.placeholder ?? 'YYYY',
          maxLength: 4,
          onChanged: onChanged,
        );

      // ── Selection ──────────────────────────────────────────────────────
      case FieldType.multiselect:
        return TfMultiSelect(
          options: field.options,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.toggle:
        return TfToggle(value: value, readOnly: readOnly, onChanged: onChanged);

      case FieldType.buttongroup:
      case FieldType.likert:
        return TfChoiceChips(
          options: field.options,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.emojiRating:
        return TfChoiceChips(
          options: field.options.isEmpty
              ? const ['😞', '😐', '🙂', '😀', '🤩']
              : field.options,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          big: true,
        );

      // ── Master-data pickers ────────────────────────────────────────────
      // The builder supplies the choices as options; with none configured a
      // dropdown would be an empty menu, so it falls back to typing — which is
      // exactly what the web does for these.
      case FieldType.departmentSelector:
      case FieldType.branchSelector:
      case FieldType.designationSelector:
      case FieldType.roleSelector:
      case FieldType.leaveTypeSelector:
      case FieldType.shiftSelector:
      case FieldType.locationSelector:
      case FieldType.taskStatusField:
      case FieldType.taskPriorityField:
      case FieldType.taskCategoryField:
      case FieldType.uomSelector:
        if (field.options.isEmpty) {
          return TextFormField(
            initialValue: _asString(),
            readOnly: readOnly,
            decoration: InputDecoration(
              hintText: field.placeholder ?? 'Enter ${field.label.toLowerCase()}',
              isDense: true,
            ),
            onChanged: (s) => onChanged(s),
          );
        }
        return _Dropdown(
          value: _asString().isEmpty ? null : _asString(),
          items: field.options,
          placeholder: field.placeholder ?? 'Select',
          readOnly: readOnly,
          onChanged: (s) => onChanged(s),
        );

      case FieldType.employeeSelector:
      case FieldType.taskSelector:
      case FieldType.witness:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: field.placeholder ?? 'Search ${field.label.toLowerCase()}',
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      // ── Approval ───────────────────────────────────────────────────────
      case FieldType.approval:
        return TfApproval(value: value, readOnly: readOnly, onChanged: onChanged);

      case FieldType.signature:
      case FieldType.esignature:
        return TfSignaturePad(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.drawing:
        return TfSignaturePad(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          hint: 'Draw above',
        );

      // ── Rating ─────────────────────────────────────────────────────────
      case FieldType.starRating:
        return TfStarRating(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          max: field.max?.toInt() ?? 5,
        );

      case FieldType.npsScore:
        return TfNpsScore(value: value, readOnly: readOnly, onChanged: onChanged);

      case FieldType.sliderRating:
        return TfSliderRating(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          min: field.min?.toDouble() ?? 0,
          max: field.max?.toDouble() ?? 10,
        );

      case FieldType.ranking:
        return TfRanking(
          options: field.options,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      // ── Finance ────────────────────────────────────────────────────────
      case FieldType.currency:
        return _NumberField(
          value: _asString(),
          readOnly: readOnly,
          decimal: true,
          prefix: field.currencyCode == null || field.currencyCode == 'INR'
              ? '₹ '
              : '${field.currencyCode} ',
          hint: field.placeholder ?? '0.00',
          onChanged: onChanged,
        );

      case FieldType.percentage:
        return _NumberField(
          value: _asString(),
          readOnly: readOnly,
          decimal: true,
          suffix: '%',
          hint: field.placeholder,
          onChanged: onChanged,
        );

      case FieldType.quantity:
        return _NumberField(
          value: _asString(),
          readOnly: readOnly,
          decimal: true,
          hint: field.placeholder ?? 'Qty',
          onChanged: onChanged,
        );

      case FieldType.panNumber:
      case FieldType.gstNumber:
      case FieldType.ifscLookup:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseTextFormatter()],
          maxLength: field.maxLength ??
              (field.type == FieldType.panNumber
                  ? 10
                  : field.type == FieldType.gstNumber
                      ? 15
                      : 11),
          decoration: InputDecoration(
            hintText: field.placeholder,
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      case FieldType.aadhaarNumber:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 12,
          decoration: InputDecoration(
            hintText: field.placeholder ?? '12 digits',
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      case FieldType.bankAccount:
        return TextFormField(
          initialValue: _asString(),
          readOnly: readOnly,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: field.maxLength ?? 20,
          decoration: InputDecoration(
            hintText: field.placeholder ?? 'Account number',
            isDense: true,
          ),
          onChanged: (s) => onChanged(s),
        );

      // ── Location & scanner ─────────────────────────────────────────────
      case FieldType.mapPoint:
        return TfMapPointField(
          value: _asString(),
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.qrScanner:
        return TfScannerField(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          label: 'QR code',
        );

      case FieldType.barcodeScanner:
        return TfScannerField(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          label: 'Barcode',
        );

      case FieldType.nfcTag:
        return TfScannerField(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          label: 'NFC tag',
          canScan: false,
          note: 'Reading NFC tags is not supported in this build — enter the tag id.',
        );

      // ── Table / repeatable ─────────────────────────────────────────────
      case FieldType.table:
      case FieldType.repeatableSection:
        return TfRepeatableRows(
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          addLabel: field.type == FieldType.table ? 'Add row' : 'Add entry',
        );

      case FieldType.matrix:
        return TfMatrixField(
          rows: field.options,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      // ── Layout ─────────────────────────────────────────────────────────
      case FieldType.section:
      case FieldType.divider:
      case FieldType.heading:
      case FieldType.paragraph:
      case FieldType.spacer:
        return TfLayoutBlock(
          kind: field.type.name,
          label: field.label,
          helpText: field.helpText,
        );

      // ── Calculation & system ───────────────────────────────────────────
      case FieldType.hidden:
        return const SizedBox.shrink();

      case FieldType.readOnly:
        return TfAutoFilled(text: field.placeholder ?? field.label);

      case FieldType.formula:
        return TfAutoFilled(
          text: field.expression == null
              ? 'Calculated automatically'
              : '= ${field.expression}',
          mono: true,
        );

      case FieldType.sequenceNumber:
        return const TfAutoFilled(text: 'Numbered automatically');

      case FieldType.timestampField:
        return const TfAutoFilled(text: 'Stamped when you submit');

      case FieldType.currentUserField:
        return const TfAutoFilled(text: 'Filled with your name');

      case FieldType.currentBranchField:
        return const TfAutoFilled(text: 'Filled with your branch');

      case FieldType.gpsLocation:
        return _GpsField(
          value: _asString(),
          readOnly: readOnly,
          onChanged: onChanged,
        );
    }
  }
}

// ─────────────────────────── File / photo upload ───────────────────────────

/// Normalises a stored file value into a list of descriptor maps. Tolerates a
/// bare url string, a single object, or a list of objects/strings.
List<Map<String, dynamic>> _asFileList(dynamic value) {
  Map<String, dynamic> one(dynamic e) {
    if (e is Map) return Map<String, dynamic>.from(e);
    return {'url': e.toString(), 'name': 'file'};
  }

  if (value == null) return [];
  if (value is List) return value.map(one).toList();
  return [one(value)];
}

class _FileField extends ConsumerStatefulWidget {
  const _FileField({
    required this.value,
    required this.multi,
    required this.readOnly,
    required this.onChanged,
    this.imageOnly = false,
    this.video = false,
    this.mediaSource = MediaSource.both,
  });

  final dynamic value;
  final bool multi;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  /// When true the picker offers only camera + gallery (no document picker).
  final bool imageOnly;

  /// A `video` field: "camera" records a clip and "gallery" picks an existing one.
  final bool video;

  /// Which sources the template allows for an image / multiimage / video field.
  /// [MediaSource.both] keeps the classic camera-or-gallery sheet; a single source
  /// skips the sheet and opens that source directly.
  final MediaSource mediaSource;

  @override
  ConsumerState<_FileField> createState() => _FileFieldState();
}

class _FileFieldState extends ConsumerState<_FileField> {
  bool _busy = false;

  List<Map<String, dynamic>> get _files => _asFileList(widget.value);

  void _emit(List<Map<String, dynamic>> files) {
    if (widget.multi) {
      widget.onChanged(files.isEmpty ? null : files);
    } else {
      widget.onChanged(files.isEmpty ? null : files.first);
    }
  }

  Future<void> _addFromCamera() async {
    final picker = ImagePicker();
    if (widget.video) {
      final clip = await picker.pickVideo(source: ImageSource.camera);
      if (clip != null) await _uploadPaths([(clip.path, clip.name)]);
      return;
    }
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 2000,
    );
    if (shot != null) await _uploadPaths([(shot.path, shot.name)]);
  }

  Future<void> _addFromGallery() async {
    final picker = ImagePicker();
    if (widget.video) {
      final clip = await picker.pickVideo(source: ImageSource.gallery);
      if (clip != null) await _uploadPaths([(clip.path, clip.name)]);
      return;
    }
    if (widget.multi) {
      final shots = await picker.pickMultiImage(imageQuality: 70, maxWidth: 2000);
      await _uploadPaths(shots.map((x) => (x.path, x.name)).toList());
    } else {
      final shot = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 2000,
      );
      if (shot != null) await _uploadPaths([(shot.path, shot.name)]);
    }
  }

  Future<void> _addDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: widget.multi,
      withData: false,
    );
    if (result == null) return;
    final paths = <(String, String)>[];
    for (final f in result.files) {
      if (f.path != null) paths.add((f.path!, f.name));
    }
    await _uploadPaths(paths);
  }

  Future<void> _uploadPaths(List<(String, String)> paths) async {
    if (paths.isEmpty) return;
    setState(() => _busy = true);
    final repo = ref.read(fileRepositoryProvider);
    final next = [..._files];
    try {
      for (final (path, name) in paths) {
        final up = await repo.upload(path, filename: name);
        if (widget.multi) {
          next.add(up.toJson());
        } else {
          next
            ..clear()
            ..add(up.toJson());
        }
      }
      _emit(next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(int index) {
    final next = [..._files]..removeAt(index);
    _emit(next);
  }

  bool get _mediaOnly => widget.imageOnly || widget.video;

  Future<void> _showAddSheet() async {
    final allowCamera = widget.mediaSource.allowsCamera;
    final allowGallery = widget.mediaSource.allowsGallery;

    // A template that fixes the source gets no sheet: the camera (or gallery)
    // opens straight away, exactly as designed.
    if (_mediaOnly && allowCamera && !allowGallery) {
      await _addFromCamera();
      return;
    }
    if (_mediaOnly && allowGallery && !allowCamera) {
      await _addFromGallery();
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: kTaskSheetShape,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TaskSheetHeader(
                title: widget.video
                    ? 'Add a video'
                    : _mediaOnly
                        ? (widget.multi ? 'Add photos' : 'Add a photo')
                        : (widget.multi ? 'Add files' : 'Add a file'),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ProListGroup(
                  children: [
                    if (allowCamera)
                      ProListRow(
                        leading: ProIconWell(
                          icon: widget.video
                              ? Icons.videocam_outlined
                              : Icons.photo_camera_outlined,
                          color: AppColors.primary,
                        ),
                        title: widget.video ? 'Record a video' : 'Take a photo',
                        onTap: () => Navigator.pop(ctx, 'camera'),
                      ),
                    if (allowGallery)
                      ProListRow(
                        leading: ProIconWell(
                          icon: widget.video
                              ? Icons.video_library_outlined
                              : Icons.photo_library_outlined,
                          color: AppColors.info,
                        ),
                        title: widget.video
                            ? 'Choose a video'
                            : (widget.multi ? 'Choose photos' : 'Choose a photo'),
                        onTap: () => Navigator.pop(ctx, 'gallery'),
                      ),
                    if (!_mediaOnly)
                      ProListRow(
                        leading: const ProIconWell(
                          icon: Icons.attach_file_rounded,
                          color: AppColors.pink,
                        ),
                        title: widget.multi ? 'Attach files' : 'Attach a file',
                        onTap: () => Navigator.pop(ctx, 'file'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    switch (action) {
      case 'camera':
        await _addFromCamera();
        break;
      case 'gallery':
        await _addFromGallery();
        break;
      case 'file':
        await _addDocuments();
        break;
    }
  }

  /// Button icon: names the fixed source when the template chose one.
  IconData get _addIcon {
    if (!_mediaOnly || widget.mediaSource == MediaSource.both) return Icons.add_rounded;
    if (widget.mediaSource == MediaSource.camera) {
      return widget.video ? Icons.videocam_outlined : Icons.photo_camera_outlined;
    }
    return widget.video ? Icons.video_library_outlined : Icons.photo_library_outlined;
  }

  String _addLabel(bool empty) {
    if (!_mediaOnly || widget.mediaSource == MediaSource.both) {
      return empty ? 'Add attachment' : 'Add more';
    }
    if (widget.mediaSource == MediaSource.camera) {
      if (widget.video) return empty ? 'Record video' : 'Record another';
      return empty ? 'Take photo' : 'Take another';
    }
    if (widget.video) return empty ? 'Choose video' : 'Choose another';
    return empty ? (widget.multi ? 'Choose photos' : 'Choose photo') : 'Choose more';
  }

  /// Drop-zone icon for an empty field.
  IconData get _dropIcon {
    if (!_mediaOnly) return Icons.upload_file_rounded;
    if (widget.mediaSource == MediaSource.both) {
      return widget.video ? Icons.videocam_outlined : Icons.add_a_photo_outlined;
    }
    return _addIcon;
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final canAdd = !widget.readOnly && (widget.multi || files.isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (files.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < files.length; i++)
                _FilePreview(
                  file: files[i],
                  onRemove: widget.readOnly ? null : () => _remove(i),
                ),
            ],
          ),
        if (files.isNotEmpty) const SizedBox(height: 10),
        if (canAdd)
          files.isEmpty
              ? _DropZone(
                  icon: _dropIcon,
                  label: _busy ? 'Uploading…' : _addLabel(true),
                  busy: _busy,
                  onTap: _busy ? null : _showAddSheet,
                )
              : OutlinedButton.icon(
                  onPressed: _busy ? null : _showAddSheet,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_addIcon, size: 18),
                  label: Text(_busy ? 'Uploading…' : _addLabel(false)),
                )
        else if (files.isEmpty)
          const Text(
            'No attachment.',
            style: TextStyle(color: AppColors.muted, fontSize: 13.5),
          ),
      ],
    );
  }
}

/// Dashed tap target shown while a file / photo / video field is empty.
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: CustomPaint(
            painter: _DashedBoxPainter(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Column(
                children: [
                  if (busy)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  else
                    ProIconWell(icon: icon, color: AppColors.primary, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(14),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = const Color(0xFFC6D3D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.file, this.onRemove});
  final Map<String, dynamic> file;
  final VoidCallback? onRemove;

  bool get _isImage {
    final ct = (file['contentType'] as String?) ?? '';
    if (ct.startsWith('image/')) return true;
    final name = (file['name'] as String?) ?? (file['url'] as String?) ?? '';
    return RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false)
        .hasMatch(name);
  }

  @override
  Widget build(BuildContext context) {
    final url = (file['url'] as String?) ?? '';
    final name = (file['name'] as String?) ?? 'file';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: _isImage && url.isNotEmpty
              ? Image.network(
                  absoluteFileUrl(url),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.faint),
                )
              : Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const ProIconWell(
                        icon: Icons.insert_drive_file_outlined,
                        size: 32,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
        ),
        if (onRemove != null)
          Positioned(
            top: -6,
            right: -6,
            child: Semantics(
              button: true,
              label: 'Remove',
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.close_rounded,
                      size: 13, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
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
        isDense: true,
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
      borderRadius: BorderRadius.circular(AppRadii.md),
      dropdownColor: AppColors.surface,
      hint: Text(placeholder),
      items: items
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: readOnly ? null : onChanged,
    );
  }
}

/// Numeric entry shared by decimal, year, currency, percentage and quantity.
///
/// Stores a `num` rather than the typed string, matching the web renderer — a
/// number that arrives as text sorts and sums wrongly everywhere downstream.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.value,
    required this.readOnly,
    required this.decimal,
    required this.onChanged,
    this.hint,
    this.prefix,
    this.suffix,
    this.maxLength,
  });

  final String value;
  final bool readOnly;
  final bool decimal;
  final void Function(dynamic) onChanged;
  final String? hint;
  final String? prefix;
  final String? suffix;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      readOnly: readOnly,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: decimal
          ? null
          : [FilteringTextInputFormatter.digitsOnly],
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefix,
        suffixText: suffix,
        isDense: true,
        counterText: maxLength == null ? null : '',
      ),
      onChanged: (s) {
        if (s.isEmpty) return onChanged(null);
        final n = num.tryParse(s);
        onChanged(n ?? s);
      },
    );
  }
}

/// Tap-to-pick box shared by the date, time, date-time and month fields.
class _PickerBox extends StatelessWidget {
  const _PickerBox({
    required this.text,
    required this.placeholder,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          suffixIcon: Icon(icon, size: 19),
        ),
        child: Text(
          text.isEmpty ? placeholder : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            color: text.isEmpty ? AppColors.faint : AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Date and time in one field. Stores `yyyy-MM-ddTHH:mm`, the value the web's
/// `datetime-local` input produces.
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String value;
  final bool readOnly;
  final void Function(String) onChanged;

  Future<void> _pick(BuildContext context) async {
    if (readOnly) return;
    final current = DateTime.tryParse(value) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 5),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    final combined =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    onChanged(DateFormat("yyyy-MM-dd'T'HH:mm").format(combined));
  }

  @override
  Widget build(BuildContext context) {
    final shown = value.isEmpty ? '' : value.replaceFirst('T', ' ');
    return _PickerBox(
      text: shown,
      placeholder: 'Select date & time',
      icon: Icons.event_rounded,
      onTap: () => _pick(context),
    );
  }
}

/// Month picker. Stores `yyyy-MM`, matching the web's `month` input.
class _MonthField extends StatelessWidget {
  const _MonthField({
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String value;
  final bool readOnly;
  final void Function(String) onChanged;

  Future<void> _pick(BuildContext context) async {
    if (readOnly) return;
    final now = DateTime.now();
    final current = DateTime.tryParse('$value-01') ?? now;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        var year = current.year;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => setLocal(() => year--),
                ),
                Text('$year', style: const TextStyle(fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => setLocal(() => year++),
                ),
              ],
            ),
            content: SizedBox(
              width: 300,
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                children: [
                  for (var m = 1; m <= 12; m++)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, DateTime(year, m)),
                      child: Text(
                          DateFormat('MMM').format(DateTime(year, m))),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked != null) onChanged(DateFormat('yyyy-MM').format(picked));
  }

  @override
  Widget build(BuildContext context) {
    return _PickerBox(
      text: value,
      placeholder: 'Select month',
      icon: Icons.calendar_month_rounded,
      onTap: () => _pick(context),
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
    return _PickerBox(
      text: value,
      placeholder: 'Select date',
      icon: Icons.calendar_today_rounded,
      onTap: () => _pick(context),
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
    return _PickerBox(
      text: value,
      placeholder: 'Select time',
      icon: Icons.schedule_rounded,
      onTap: () => _pick(context),
    );
  }
}

// ─────────────────────────── GPS location capture ───────────────────────────

/// Reads the device's position for a `gps_location` field.
///
/// The web form builder renders this type as "Location capture — available on
/// mobile app" over a manual Lat, Long box, so the phone is the side expected to
/// fill it from the GPS rather than ask somebody to type coordinates.
///
/// The value is stored as a plain `"lat, lng"` string — the same shape the web's
/// manual box writes — so a field filled on either side reads back on the other
/// and in reports. Accuracy describes the fix rather than the answer, so it is
/// shown after capturing but not stored.
class _GpsField extends StatefulWidget {
  const _GpsField({
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String value;
  final bool readOnly;
  final void Function(String?) onChanged;

  @override
  State<_GpsField> createState() => _GpsFieldState();
}

class _GpsFieldState extends State<_GpsField> {
  bool _busy = false;
  String? _error;
  double? _accuracy;

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _fail('Location is switched off. Turn it on and try again.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        return _fail('Location permission is blocked for this app. '
            'Allow it in Settings and try again.');
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return _fail('Location permission is needed to record this field.');
      }

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (_) {
        // A fix can time out indoors; the last known position is a better answer
        // than sending somebody back to typing coordinates by hand.
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) {
          return _fail('Could not get a GPS fix. Move to an open area and retry.');
        }
        pos = last;
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _accuracy = pos.accuracy;
      });
      widget.onChanged(
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
    } catch (e) {
      _fail('Could not read your location: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final captured = widget.value.trim().isNotEmpty;

    if (widget.readOnly) {
      return Row(
        children: [
          const Icon(Icons.place_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              captured ? widget.value : 'Not captured',
              style: TextStyle(
                fontSize: 14,
                color: captured ? AppColors.ink : AppColors.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (captured) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: AppColors.successTint,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.place_rounded,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (_accuracy != null)
                        Text(
                          'Accurate to about ${_accuracy!.round()} m',
                          style: AppText.caption,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.muted),
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _accuracy = null);
                          widget.onChanged(null);
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _capture,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded, size: 18),
            label: Text(
              _busy
                  ? 'Getting your location…'
                  : captured
                      ? 'Update location'
                      : 'Use my current location',
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}
