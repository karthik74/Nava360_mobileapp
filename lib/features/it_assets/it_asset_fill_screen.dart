import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
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

  static const _autoTypes = {'auto_region', 'auto_division', 'auto_area', 'auto_branch'};

  /// Presentation only — mirrors the required check in [_submit].
  bool _filled(ItAssetFieldDef f) {
    final value = _valuesDrivenTypes.contains(f.type) ? _values[f.key] : _controllers[f.key]?.text;
    return !(value == null || value.trim().isEmpty || value == '[]');
  }

  /// Rebuilds the progress card as text fields change.
  late final Listenable _textChanges = Listenable.merge(_controllers.values.toList());

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final autoFields = entry.fields.where((f) => _autoTypes.contains(f.type)).toList();
    final formFields = entry.fields.where((f) => !_autoTypes.contains(f.type)).toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: entry.templateName,
        subtitle: 'IT assets · ${entry.period}',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AnimatedBuilder(
            animation: _textChanges,
            builder: (context, _) {
              final required = entry.fields.where((f) => f.required).toList();
              final done = required.where(_filled).length;
              return GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ProIconWell(
                          icon: Icons.inventory_2_outlined,
                          color: AppColors.primary,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Period', style: AppText.caption),
                              Text(
                                entry.period,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.25,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        entry.isSubmitted ? ProPill.ok('Submitted') : ProPill.warn('Pending'),
                      ],
                    ),
                    if (required.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Required answers',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                          Text(
                            '$done of ${required.length}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.muted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ProBar(value: done / required.length),
                    ],
                  ],
                ),
              );
            },
          ),
          if (autoFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProSectionHeader(
                    title: 'Your branch',
                    trailing: Text('Read only', style: AppText.caption),
                  ),
                  const SizedBox(height: 4),
                  // Never typed by the filler — the backend already filled these in
                  // from the assignee's own org placement; shown read-only.
                  ProKeyValue(rows: [
                    for (final f in autoFields)
                      MapEntry(
                        f.label,
                        (_controllers[f.key]?.text.trim().isNotEmpty ?? false)
                            ? _controllers[f.key]!.text
                            : '—',
                      ),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Filled automatically from your branch', style: AppText.caption),
                ],
              ),
            ),
          ],
          if (formFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProSectionHeader(title: 'Form'),
                  const SizedBox(height: 14),
                  for (var i = 0; i < formFields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _fieldWidget(formFields[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Submitting…' : 'Submit'),
          ),
        ],
      ),
    );
  }

  Widget _fieldWidget(ItAssetFieldDef f) {
    switch (f.type) {
      case 'checkbox':
        final checked = (_values[f.key] ?? 'false') == 'true';
        return _ToggleTile(
          label: f.label,
          required: f.required,
          checked: checked,
          onTap: () => setState(() => _values[f.key] = (!checked).toString()),
        );
      case 'dropdown':
        final current = _values[f.key];
        return ProField(
          label: f.label,
          required: f.required,
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(hintText: 'Choose one'),
            isExpanded: true,
            initialValue: (current != null && f.options.contains(current)) ? current : null,
            items: f.options
                .map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _values[f.key] = v ?? ''),
          ),
        );
      case 'radio':
        return ProField(
          label: f.label,
          required: f.required,
          child: Column(
            children: [
              for (final o in f.options)
                _ChoiceTile(
                  label: o,
                  selected: _values[f.key] == o,
                  multi: false,
                  onTap: () => setState(() => _values[f.key] = o),
                ),
            ],
          ),
        );
      case 'multiselect':
        final selected = _multiselectValues(f.key);
        return ProField(
          label: f.label,
          required: f.required,
          child: Column(
            children: [
              for (final o in f.options)
                _ChoiceTile(
                  label: o,
                  selected: selected.contains(o),
                  multi: true,
                  onTap: () {
                    final checked = !selected.contains(o);
                    setState(() {
                      final next = List<String>.from(selected);
                      if (checked) {
                        if (!next.contains(o)) next.add(o);
                      } else {
                        next.remove(o);
                      }
                      _values[f.key] = jsonEncode(next);
                    });
                  },
                ),
            ],
          ),
        );
      case 'photo':
      case 'file':
        final file = _fileRef(f.key);
        final uploading = _uploadingKey == f.key;
        final isPhoto = f.type == 'photo';
        return ProField(
          label: f.label,
          required: f.required,
          child: _UploadTile(
            icon: file != null
                ? (file.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined)
                : (isPhoto ? Icons.photo_camera_outlined : Icons.attach_file_rounded),
            title: uploading
                ? 'Uploading…'
                : file != null
                    ? file.name
                    : (isPhoto ? 'Take photo' : 'Choose file'),
            subtitle: file != null
                ? 'Uploaded'
                : (isPhoto ? 'Opens the camera' : 'Pick a file from your phone'),
            done: file != null,
            uploading: uploading,
            actionLabel: file == null ? null : 'Replace',
            onTap: uploading ? null : () => _pickAndUpload(f.key, isPhoto: isPhoto),
          ),
        );
      case 'number':
        return ProField(
          label: f.label,
          required: f.required,
          child: TextField(
            controller: _controllers[f.key],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '0'),
          ),
        );
      case 'date':
        return ProField(
          label: f.label,
          required: f.required,
          child: TextField(
            controller: _controllers[f.key],
            readOnly: true,
            decoration: const InputDecoration(
              hintText: 'Select date',
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
            ),
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
          ),
        );
      case 'textarea':
        return ProField(
          label: f.label,
          required: f.required,
          child: TextField(
            controller: _controllers[f.key],
            maxLines: 4,
          ),
        );
      case 'auto_region':
      case 'auto_division':
      case 'auto_area':
      case 'auto_branch':
        // Never typed by the filler — the backend already filled this in from the
        // assignee's own org placement (region/division/area/branch); shown read-only.
        return ProField(
          label: f.label,
          helper: 'Filled automatically from your branch',
          child: TextField(
            controller: _controllers[f.key],
            enabled: false,
          ),
        );
      default:
        return ProField(
          label: f.label,
          required: f.required,
          child: TextField(
            controller: _controllers[f.key],
          ),
        );
    }
  }
}

/// Bordered option row with a radio / check mark (radio + multiselect fields).
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.multi,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFF2F8F9) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? primary : const Color(0xFFDBE3E5),
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                _Mark(selected: selected, multi: multi),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width tappable row with a trailing checkbox (checkbox fields).
class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.label,
    required this.required,
    required this.checked,
    required this.onTap,
  });
  final String label;
  final bool required;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: checked ? AppColors.primary : const Color(0xFFDBE3E5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: label),
                    if (required)
                      const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
                  ]),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _Mark(selected: checked, multi: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.selected, required this.multi});
  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    if (multi) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: selected ? null : Border.all(color: const Color(0xFFB9C7CA), width: 1.5),
        ),
        child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? primary : const Color(0xFFB9C7CA),
          width: selected ? 6.5 : 1.5,
        ),
      ),
    );
  }
}

/// Photo / file upload tile: empty state opens the picker; once uploaded it
/// shows the file name with a "Replace" action.
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.uploading,
    required this.actionLabel,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final bool uploading;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: done ? AppColors.surface : AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: done ? AppColors.hairline : const Color(0xFFDBE3E5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: actionLabel == null ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          child: Row(
            children: [
              if (uploading)
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                ProIconWell(
                  icon: icon,
                  color: done ? AppColors.success : AppColors.primary,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: done ? AppColors.success : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
