import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../files/file_repository.dart';
import 'it_asset_models.dart';
import 'it_asset_repository.dart';

/// Field types whose current answer lives in [_ItAssetFillScreenState._values]
/// (a raw string, a JSON array, or a JSON file ref) rather than a [TextEditingController].
const _valuesDrivenTypes = {'checkbox', 'multiselect', 'photo', 'file'};

/// Fills one assigned IT Asset form. Fields render from the template's
/// schema (carried on the entry as `templateFormSchema`) so the employee
/// sees exactly the fields the admin defined — laptops, keyboards, cameras,
/// whatever the form was built with — not a raw key/value editor.
class ItAssetFillScreen extends ConsumerStatefulWidget {
  const ItAssetFillScreen({super.key, required this.entry});
  final ItAssetFormEntry entry;

  @override
  ConsumerState<ItAssetFillScreen> createState() => _ItAssetFillScreenState();
}

class _ItAssetFillScreenState extends ConsumerState<ItAssetFillScreen> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _values;
  bool _saving = false;
  String? _uploadingKey;

  @override
  void initState() {
    super.initState();
    _values = Map.of(widget.entry.responseData);
    _controllers = {
      for (final f in widget.entry.fields)
        f.key: TextEditingController(text: _values[f.key] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    for (final f in widget.entry.fields) {
      final value = _valuesDrivenTypes.contains(f.type) ? _values[f.key] : _controllers[f.key]?.text;
      if (f.required && (value == null || value.trim().isEmpty || value == '[]')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${f.label}" is required')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final answers = <String, String>{};
      for (final f in widget.entry.fields) {
        answers[f.key] = _valuesDrivenTypes.contains(f.type)
            ? (_values[f.key] ?? (f.type == 'checkbox' ? 'false' : ''))
            : (_controllers[f.key]?.text ?? '');
      }
      await ref.read(itAssetRepositoryProvider).fill(widget.entry.id, answers);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _multiselectValues(String key) {
    final raw = _values[key];
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.map((e) => e.toString()).toList() : [];
    } catch (_) {
      return [];
    }
  }

  UploadedFile? _fileRef(String key) {
    final raw = _values[key];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? UploadedFile.fromJson(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickAndUpload(String key, {required bool isPhoto}) async {
    String? path;
    String? name;
    if (isPhoto) {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      path = picked?.path;
      name = picked?.name;
    } else {
      final picked = await FilePicker.platform.pickFiles();
      path = picked?.files.single.path;
      name = picked?.files.single.name;
    }
    if (path == null) return;
    setState(() => _uploadingKey = key);
    try {
      final uploaded = await ref.read(fileRepositoryProvider).upload(path, filename: name);
      setState(() {
        _values[key] = jsonEncode(uploaded.toJson());
        _uploadingKey = null;
      });
    } catch (e) {
      setState(() => _uploadingKey = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Scaffold(
      appBar: AppBar(title: Text('${entry.templateName} — ${entry.period}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in entry.fields) ...[
            _fieldWidget(f),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Submitting…' : 'Submit'),
          ),
        ],
      ),
    );
  }

  Widget _fieldWidget(ItAssetFieldDef f) {
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.type) {
      case 'checkbox':
        return CheckboxListTile(
          title: Text(label),
          value: (_values[f.key] ?? 'false') == 'true',
          onChanged: (v) => setState(() => _values[f.key] = (v ?? false).toString()),
        );
      case 'dropdown':
        final current = _values[f.key];
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          initialValue: (current != null && f.options.contains(current)) ? current : null,
          items: f.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _values[f.key] = v ?? ''),
        );
      case 'radio':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            for (final o in f.options)
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(o),
                value: o,
                groupValue: _values[f.key],
                onChanged: (v) => setState(() => _values[f.key] = v ?? ''),
              ),
          ],
        );
      case 'multiselect':
        final selected = _multiselectValues(f.key);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            for (final o in f.options)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(o),
                value: selected.contains(o),
                onChanged: (checked) => setState(() {
                  final next = List<String>.from(selected);
                  if (checked == true) {
                    if (!next.contains(o)) next.add(o);
                  } else {
                    next.remove(o);
                  }
                  _values[f.key] = jsonEncode(next);
                }),
              ),
          ],
        );
      case 'photo':
      case 'file':
        final ref = _fileRef(f.key);
        final uploading = _uploadingKey == f.key;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            if (ref != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(ref.isImage ? Icons.image : Icons.insert_drive_file, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(ref.name, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            OutlinedButton.icon(
              onPressed: uploading ? null : () => _pickAndUpload(f.key, isPhoto: f.type == 'photo'),
              icon: uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(f.type == 'photo' ? Icons.camera_alt : Icons.attach_file),
              label: Text(uploading ? 'Uploading…' : (ref == null ? 'Choose' : 'Replace')),
            ),
          ],
        );
      case 'number':
        return TextField(
          controller: _controllers[f.key],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        );
      case 'date':
        return TextField(
          controller: _controllers[f.key],
          readOnly: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_today)),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              _controllers[f.key]!.text = picked.toIso8601String().substring(0, 10);
            }
          },
        );
      case 'textarea':
        return TextField(
          controller: _controllers[f.key],
          maxLines: 4,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        );
      case 'auto_region':
      case 'auto_division':
      case 'auto_area':
      case 'auto_branch':
        // Never typed by the filler — the backend already filled this in from the
        // assignee's own org placement (region/division/area/branch); shown read-only.
        return TextField(
          controller: _controllers[f.key],
          enabled: false,
          decoration: InputDecoration(
            labelText: f.label,
            border: const OutlineInputBorder(),
            helperText: 'Filled automatically from your branch',
          ),
        );
      default:
        return TextField(
          controller: _controllers[f.key],
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        );
    }
  }
}
