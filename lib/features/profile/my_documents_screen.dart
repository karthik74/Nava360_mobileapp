import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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
  List<DocTypeOption>? _types;
  String? _selectedType;
  PlatformFile? _file;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _label.dispose();
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
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Upload failed. Please try again.';
        });
      }
    }
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
              onChanged:
                  _busy ? null : (v) => setState(() => _selectedType = v),
              decoration: const InputDecoration(
                labelText: 'Document type *',
                border: OutlineInputBorder(),
              ),
            ),
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
