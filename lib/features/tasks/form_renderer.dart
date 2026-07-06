import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../files/file_repository.dart';
import 'task_models.dart';

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
            ownerFillsAssigned: ownerFillsAssigned,
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
    final showInlineLabel =
        field.type != FieldType.checkbox; // checkbox renders own legend
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
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      children: [
                        TextSpan(text: field.label),
                        if (field.required && !lockedAssigned)
                          const TextSpan(
                            text: ' *',
                            style: TextStyle(color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                ),
                if (lockedAssigned)
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
          textCapitalization: field.type == FieldType.email
              ? TextCapitalization.none
              : TextCapitalization.words,
          inputFormatters: field.type == FieldType.email
              ? null
              : const [TitleCaseTextFormatter()],
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
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
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

      case FieldType.image:
      case FieldType.webcam:
        // Single image, camera-first.
        return _FileField(
          value: value,
          multi: false,
          imageOnly: true,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.multiimage:
        return _FileField(
          value: value,
          multi: true,
          imageOnly: true,
          readOnly: readOnly,
          onChanged: onChanged,
        );

      case FieldType.file:
      case FieldType.video:
      case FieldType.audio:
        return _FileField(
          value: value,
          multi: false,
          imageOnly: false,
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
  });

  final dynamic value;
  final bool multi;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  /// When true the picker offers only camera + gallery (no document picker).
  final bool imageOnly;

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
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 2000,
    );
    if (shot != null) await _uploadPaths([(shot.path, shot.name)]);
  }

  Future<void> _addFromGallery() async {
    final picker = ImagePicker();
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

  Future<void> _showAddSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(widget.multi ? 'Choose photos' : 'Choose a photo'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (!widget.imageOnly)
              ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: Text(widget.multi ? 'Attach files' : 'Attach a file'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
          ],
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
        if (files.isNotEmpty) const SizedBox(height: 8),
        if (canAdd)
          OutlinedButton.icon(
            onPressed: _busy ? null : _showAddSheet,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded, size: 18),
            label: Text(_busy
                ? 'Uploading…'
                : (files.isEmpty ? 'Add attachment' : 'Add more')),
          )
        else if (files.isEmpty)
          Text(
            'No attachment.',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12.5),
          ),
      ],
    );
  }
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
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          clipBehavior: Clip.antiAlias,
          child: _isImage && url.isNotEmpty
              ? Image.network(
                  absoluteFileUrl(url),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.grey),
                )
              : Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.insert_drive_file_outlined,
                          size: 26, color: AppColors.muted),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
        ),
        if (onRemove != null)
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
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
