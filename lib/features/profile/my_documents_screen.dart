import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
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
  int _filter = 0; // 0 all · 1 PDF · 2 images · 3 other (in-memory filter)

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
    final all = docs ?? const <EmployeeDocument>[];
    final pdfs = all.where((d) => d.isPdf).length;
    final images = all.where((d) => d.isImage).length;
    final others = all.length - pdfs - images;
    final latest = all.isEmpty
        ? null
        : all.reduce((a, b) {
            final ad = a.createdAt, bd = b.createdAt;
            if (ad == null) return b;
            if (bd == null) return a;
            return bd.isAfter(ad) ? b : a;
          });
    final shown = switch (_filter) {
      1 => all.where((d) => d.isPdf).toList(),
      2 => all.where((d) => d.isImage).toList(),
      3 => all.where((d) => !d.isPdf && !d.isImage).toList(),
      _ => all,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton.icon(
            onPressed: _startUpload,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.upload_file_rounded, size: 19),
            label: const Text('Upload document'),
          ),
        ],
      ),
      body: ProPage(
        onRefresh: _load,
        hero: ProHero(
          title: 'My documents',
          subtitle: docs == null
              ? 'In your employee file'
              : 'In your employee file · ${all.length} '
                  '${all.length == 1 ? 'document' : 'documents'}',
          children: [
            ProHeroStats(
              stats: [
                ProStat(
                  label: 'Uploaded',
                  value: docs == null ? '–' : '${all.length}',
                  sub: 'on file',
                  dot: AppColors.live,
                ),
                ProStat(
                  label: 'PDFs',
                  value: docs == null ? '–' : '$pdfs',
                  sub: 'PDF files',
                  dot: const Color(0xFFF2B347),
                ),
                ProStat(
                  label: 'Latest',
                  value: latest?.createdAt == null
                      ? '—'
                      : DateFormat('dd MMM').format(latest!.createdAt!),
                  sub: latest?.docTypeLabel ?? 'nothing yet',
                  dot: const Color(0xFF6CC3D5),
                ),
              ],
            ),
          ],
        ),
        children: [
          if (docs == null) ...const [
            AppLoadingBlock(height: 72),
            AppLoadingBlock(height: 72),
          ] else ...[
            if (_error != null) ProNote(_error!, tone: ProNoteTone.bad),
            if (all.isEmpty)
              ProEmpty(
                icon: Icons.folder_open_rounded,
                title: 'No documents yet',
                message: _error == null ? 'Tap Upload to add one.' : null,
              )
            else ...[
              ProChipBar(
                labels: const ['All', 'PDF', 'Images', 'Other'],
                counts: [all.length, pdfs, images, others],
                selected: _filter,
                onSelected: (i) => setState(() => _filter = i),
                bleed: 0,
              ),
              ProSectionHeader(
                title: '${const ['All documents', 'PDF', 'Images', 'Other'][_filter]} · ${shown.length}',
                small: true,
              ),
              if (shown.isEmpty)
                const ProEmpty(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'Nothing in this filter',
                  message: 'Switch to All to see every document.',
                )
              else
                ProListGroup(
                  children: [
                    for (final doc in shown)
                      _DocumentCard(
                        doc: doc,
                        opening: _openingId == doc.id,
                        onTap: () => _openDocument(doc),
                      ),
                  ],
                ),
            ],
          ],
        ],
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

  Color get _tone {
    if (doc.isImage) return AppColors.info;
    if (doc.isPdf) return AppColors.danger;
    return AppColors.primary;
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
    return ProListRow(
      leading: opening
          ? Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _tone.withOpacity(0.11),
                borderRadius: BorderRadius.circular(10),
              ),
              child: CircularProgressIndicator(strokeWidth: 2, color: _tone),
            )
          : ProIconWell(icon: _icon, color: _tone),
      title: doc.docTypeLabel,
      subtitle: doc.label?.isNotEmpty == true
          ? '${doc.label} · ${doc.fileName}'
          : doc.fileName,
      meta: [
        _size(doc.sizeBytes),
        if (date != null) date,
      ].join(' · '),
      onTap: onTap,
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
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottomInset + safeBottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFC6D3D6),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Upload document',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.35,
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
              ProField(
                label: 'Document type',
                required: true,
                child: DropdownButtonFormField<String>(
                  value: _selectedType,
                  isExpanded: true,
                  hint: const Text('Select a document type'),
                  borderRadius: BorderRadius.circular(14),
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
                ),
              ),

              // Extra details this document type is configured to capture. The
              // server rejects the upload without them, so they are mandatory here.
              if (_selected?.capturesExtraFields == true) ...[
                if (_selected!.requiresDocumentNumber) ...[
                  const SizedBox(height: 14),
                  ProField(
                    label: 'Document number',
                    required: true,
                    child: TextField(
                      controller: _documentNumber,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                ],
                if (_selected!.requiresStartDate) ...[
                  const SizedBox(height: 14),
                  ProField(
                    label: 'Start date',
                    required: true,
                    child: _DateRow(
                      value: _startDate == null ? null : _iso(_startDate!),
                      enabled: !_busy,
                      onTap: () => _pickDate(start: true),
                    ),
                  ),
                ],
                if (_selected!.requiresEndDate) ...[
                  const SizedBox(height: 14),
                  ProField(
                    label: 'End date',
                    required: true,
                    child: _DateRow(
                      value: _endDate == null ? null : _iso(_endDate!),
                      enabled: !_busy,
                      onTap: () => _pickDate(start: false),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 14),
              ProField(
                label: 'Label (optional)',
                child: TextField(
                  controller: _label,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [TitleCaseTextFormatter()],
                  decoration: const InputDecoration(
                    hintText: 'e.g. Front Side',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ProField(
                label: 'File',
                required: true,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: Icon(
                    _file == null
                        ? Icons.attach_file_rounded
                        : Icons.insert_drive_file_outlined,
                    size: 19,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    _file?.name ?? 'Choose file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                ProNote(_error!, tone: ProNoteTone.bad),
              ],
              const SizedBox(height: 18),
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
                  minimumSize: const Size.fromHeight(52),
                  disabledBackgroundColor: _busy ? AppColors.primary : null,
                  disabledForegroundColor: _busy ? Colors.white : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tappable, read-only date field styled like the surrounding inputs. Used
/// for the start/end dates a document type requires.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          enabled: enabled,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          value ?? 'Select a date',
          style: TextStyle(
            fontSize: 15,
            color: value == null ? AppColors.faint : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
