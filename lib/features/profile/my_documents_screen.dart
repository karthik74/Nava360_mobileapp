import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import 'profile_repository.dart';

/// My Profile → My documents: lists the signed-in employee's documents and
/// lets them upload new ones (type + optional label + file).
class MyDocumentsScreen extends ConsumerStatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  ConsumerState<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends ConsumerState<MyDocumentsScreen> {
  List<EmployeeDocument>? _docs;
  String? _error;
  int? _openingId; // document currently being downloaded for preview

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final docs = await ref.read(profileRepositoryProvider).myDocuments();
      if (mounted) setState(() => _docs = docs);
    } catch (e) {
      if (mounted) {
        setState(() {
          _docs ??= [];
          _error = 'Could not load documents. Pull down to retry.';
        });
      }
    }
  }

  Future<void> _openDocument(EmployeeDocument doc) async {
    if (_openingId != null) return;
    setState(() => _openingId = doc.id);
    try {
      final bytes =
          await ref.read(profileRepositoryProvider).downloadFile(doc.url);
      final dir = await getTemporaryDirectory();
      final safeName = doc.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/${doc.id}_$safeName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the document.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _startUpload() async {
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UploadDocumentSheet(),
    );
    if (uploaded == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = _docs;
    return Scaffold(
      appBar: AppBar(title: const Text('My documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startUpload,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Upload'),
      ),
      body: docs == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: docs.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Icon(Icons.folder_open_rounded,
                            size: 56, color: AppColors.muted.withOpacity(0.6)),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _error ?? 'No documents yet.\nTap Upload to add one.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.muted, fontSize: 14),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: docs.length + (_error != null ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (_error != null && i == 0) {
                          return Text(_error!,
                              style: const TextStyle(color: AppColors.danger));
                        }
                        final doc = docs[i - (_error != null ? 1 : 0)];
                        return _DocumentCard(
                          doc: doc,
                          opening: _openingId == doc.id,
                          onTap: () => _openDocument(doc),
                        );
                      },
                    ),
            ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.doc,
    required this.opening,
    required this.onTap,
  });

  final EmployeeDocument doc;
  final bool opening;
  final VoidCallback onTap;

  IconData get _icon {
    if (doc.isImage) return Icons.image_outlined;
    if (doc.isPdf) return Icons.picture_as_pdf_outlined;
    return Icons.description_outlined;
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final date = doc.createdAt != null
        ? DateFormat('dd MMM yyyy').format(doc.createdAt!)
        : null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.muted.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: opening
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(_icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.docTypeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doc.label?.isNotEmpty == true
                          ? '${doc.label} · ${doc.fileName}'
                          : doc.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _size(doc.sizeBytes),
                        if (date != null) date,
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: pick a document type, optional label and a file, then upload.
class _UploadDocumentSheet extends ConsumerStatefulWidget {
  const _UploadDocumentSheet();

  @override
  ConsumerState<_UploadDocumentSheet> createState() =>
      _UploadDocumentSheetState();
}

class _UploadDocumentSheetState extends ConsumerState<_UploadDocumentSheet> {
  final _label = TextEditingController();
  final _documentNumber = TextEditingController();
  List<DocTypeOption>? _types;
  String? _selectedType;
  PlatformFile? _file;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _busy = false;
  String? _error;

  /// Configuration of the selected type — decides which extra inputs to show.
  DocTypeOption? get _selected {
    final list = _types;
    if (list == null || _selectedType == null) return null;
    for (final t in list) {
      if (t.code == _selectedType) return t;
    }
    return null;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _label.dispose();
    _documentNumber.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await ref.read(profileRepositoryProvider).documentTypes();
      if (mounted) {
        setState(() {
          _types = types;
          if (types.length == 1) _selectedType = types.first.code;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _types = [];
          _error = 'Could not load document types.';
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _file = result.files.single);
    }
  }

  Future<void> _upload() async {
    final type = _selectedType;
    final file = _file;
    if (type == null) {
      setState(() => _error = 'Please select a document type.');
      return;
    }
    if (file == null || file.path == null) {
      setState(() => _error = 'Please choose a file to upload.');
      return;
    }
    // Mirrors the server rule so the employee is told what is missing before
    // the file is sent over a mobile connection.
    final cfg = _selected;
    if (cfg != null) {
      if (cfg.requiresDocumentNumber && _documentNumber.text.trim().isEmpty) {
        setState(() => _error = 'Document number is required.');
        return;
      }
      if (cfg.requiresStartDate && _startDate == null) {
        setState(() => _error = 'Start date is required.');
        return;
      }
      if (cfg.requiresEndDate && _endDate == null) {
        setState(() => _error = 'End date is required.');
        return;
      }
      if (_startDate != null && _endDate != null && _endDate!.isBefore(_startDate!)) {
        setState(() => _error = 'End date cannot be before the start date.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).uploadMyDocument(
            filePath: file.path!,
            filename: file.name,
            docType: type,
            label: _label.text,
            documentNumber:
                cfg?.requiresDocumentNumber == true ? _documentNumber.text : null,
            startDate: cfg?.requiresStartDate == true && _startDate != null
                ? _iso(_startDate!)
                : null,
            endDate: cfg?.requiresEndDate == true && _endDate != null
                ? _iso(_endDate!)
                : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          // Surface the server's reason — a rejected upload is usually a missing
          // required detail, and "please try again" gives the employee nothing
          // to act on.
          _error = e is ApiException ? e.message : 'Upload failed. Please try again.';
        });
      }
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start ? (_startDate ?? now) : (_endDate ?? _startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 50),
      lastDate: DateTime(now.year + 50),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final types = _types;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Upload document',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 16),
          if (types == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _selectedType,
              items: types
                  .map((t) => DropdownMenuItem(
                        value: t.code,
                        child: Text(t.label,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        _selectedType = v;
                        // The new type may ask for different details, or none.
                        _documentNumber.clear();
                        _startDate = null;
                        _endDate = null;
                        _error = null;
                      }),
              decoration: const InputDecoration(
                labelText: 'Document type *',
                border: OutlineInputBorder(),
              ),
            ),

            // Extra details this document type is configured to capture. The
            // server rejects the upload without them, so they are mandatory here.
            if (_selected?.capturesExtraFields == true) ...[
              const SizedBox(height: 14),
              if (_selected!.requiresDocumentNumber)
                TextField(
                  controller: _documentNumber,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Document number *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              if (_selected!.requiresStartDate) ...[
                const SizedBox(height: 12),
                _DateRow(
                  label: 'Start date *',
                  value: _startDate == null ? null : _iso(_startDate!),
                  enabled: !_busy,
                  onTap: () => _pickDate(start: true),
                ),
              ],
              if (_selected!.requiresEndDate) ...[
                const SizedBox(height: 12),
                _DateRow(
                  label: 'End date *',
                  value: _endDate == null ? null : _iso(_endDate!),
                  enabled: !_busy,
                  onTap: () => _pickDate(start: false),
                ),
              ],
            ],

            const SizedBox(height: 14),
            TextField(
              controller: _label,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'e.g. Front Side',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.attach_file_rounded, size: 19),
              label: Text(
                _file?.name ?? 'Choose file',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.centerLeft,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _upload,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.upload_file_rounded, size: 19),
              label: Text(_busy ? 'Uploading…' : 'Upload'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable, read-only date field matching the surrounding OutlineInputBorder
/// inputs. Used for the start/end dates a document type requires.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          value ?? 'Select a date',
          style: TextStyle(
            color: value == null ? AppColors.muted : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
