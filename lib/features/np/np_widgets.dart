// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — shared presentational widgets + dialogs + document upload.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import 'np_models.dart';
import 'np_repository.dart';

// ── formatting ──

String npFmtDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d.toLocal());
String npFmtDateTime(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());

void npToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.danger : AppColors.success,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Opens a backend file (image / PDF / HTML report) in the external viewer.
Future<void> npOpenFile(BuildContext context, NpFileRef? file) async {
  final url = Env.fileUrl(file?.url);
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) npToast(context, 'Could not open the file.', error: true);
}

Future<void> npOpenMaps(double lat, double lng) async {
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ── dialogs ──

Future<bool> npConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r == true;
}

/// Multi-line text prompt. Returns null when cancelled; empty string is only
/// possible when [required] is false.
Future<String?> npPrompt(
  BuildContext context, {
  required String title,
  String? label,
  String? hint,
  bool required = true,
  String confirmLabel = 'Save',
  bool danger = false,
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  String? err;
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint ?? (required ? 'Required' : 'Optional'), errorText: err),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
            onPressed: () {
              final v = ctrl.text.trim();
              if (required && v.isEmpty) {
                setState(() => err = 'This is required.');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return r;
}

// ── small presentational pieces ──

class NpStatusPill extends StatelessWidget {
  const NpStatusPill({super.key, required this.status, this.label});
  final String status;
  final String? label;
  @override
  Widget build(BuildContext context) => StatusPill(label: label ?? npStatusLabel(status), color: npStatusColor(status));
}

class NpFieldLabel extends StatelessWidget {
  const NpFieldLabel(this.text, {super.key, this.required = false});
  final String text;
  final bool required;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 8),
        child: Text.rich(TextSpan(
          text: text,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
          children: [if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger))],
        )),
      );
}

class NpInfoRow extends StatelessWidget {
  const NpInfoRow(this.label, this.value, {super.key});
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) {
    final v = (value == null || value!.trim().isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// "By Name · 3 Sep 2026, 10:15 AM"
class NpPersonStamp extends StatelessWidget {
  const NpPersonStamp({super.key, this.person, this.at, this.prefix = 'By'});
  final NpPerson? person;
  final DateTime? at;
  final String prefix;
  @override
  Widget build(BuildContext context) {
    if (person == null && at == null) return const SizedBox.shrink();
    final parts = <String>[];
    if (person != null) parts.add('$prefix ${person!.name}');
    if (at != null) parts.add(npFmtDateTime(at));
    return Text(parts.join(' · '), style: const TextStyle(fontSize: 11.5, color: AppColors.muted));
  }
}

class NpChip extends StatelessWidget {
  const NpChip(this.label, {super.key, this.on = false, this.color});
  final String label;
  final bool on;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? (on ? AppColors.success : AppColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(on ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: c.withOpacity(on ? 0.35 : 0.2)),
      ),
      child: Text('${on ? '✓' : '○'} $label',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: on ? c : AppColors.inkSoft)),
    );
  }
}

class NpCheckLine extends StatelessWidget {
  const NpCheckLine({super.key, required this.ok, required this.label, this.failColor});
  final bool ok;
  final String label;
  final Color? failColor;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 16, color: ok ? AppColors.success : (failColor ?? AppColors.muted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, color: ok ? AppColors.ink : AppColors.inkSoft, fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

/// A bordered, subtly-filled box for an action form inside a step panel.
class NpActionBox extends StatelessWidget {
  const NpActionBox({super.key, required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
            ],
            child,
          ],
        ),
      );
}

class NpBanner extends StatelessWidget {
  const NpBanner({super.key, required this.icon, required this.color, required this.title, this.body, this.action});
  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(14),
        color: color.withOpacity(0.07),
        border: Border.all(color: color.withOpacity(0.35)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
                  if (body != null && body!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(body!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4)),
                  ],
                ]),
              ),
            ]),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      );
}

// ── stepper + step panel ──

Color npStepStateColor(String state) {
  switch (state) {
    case 'DONE':
      return AppColors.success;
    case 'CURRENT':
      return AppColors.primary;
    case 'REJECTED':
      return AppColors.danger;
    case 'SENT_BACK':
      return const Color(0xFFEA580C);
    case 'SKIPPED':
      return AppColors.muted;
    default:
      return AppColors.hairline;
  }
}

/// Horizontal 13-dot stepper. Tapping a dot scrolls/opens that panel.
class NpStepper extends StatelessWidget {
  const NpStepper({super.key, required this.steps, required this.selected, required this.onSelect});
  final List<NpStepView> steps;
  final String selected;
  final void Function(String step) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < kNpSteps.length; i++) ...[
            _dot(i),
            if (i < kNpSteps.length - 1)
              Container(width: 14, height: 2, color: _stateOf(kNpSteps[i].step) == 'DONE' ? AppColors.success : AppColors.hairline),
          ],
        ],
      ),
    );
  }

  String _stateOf(String step) {
    for (final s in steps) {
      if (s.step == step) return s.state;
    }
    return 'PENDING';
  }

  Widget _dot(int i) {
    final info = kNpSteps[i];
    final state = _stateOf(info.step);
    final color = npStepStateColor(state);
    final isSel = info.step == selected;
    final filled = state == 'DONE' || state == 'CURRENT' || state == 'REJECTED' || state == 'SENT_BACK';
    return InkWell(
      onTap: () => onSelect(info.step),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : AppColors.surface,
              border: Border.all(color: isSel ? AppColors.ink : color, width: isSel ? 2 : 1.5),
            ),
            alignment: Alignment.center,
            child: state == 'DONE'
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text('${i + 1}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: filled ? Colors.white : AppColors.muted)),
          ),
          const SizedBox(height: 3),
          Text(info.short,
              style: TextStyle(fontSize: 9.5, fontWeight: isSel ? FontWeight.w800 : FontWeight.w600, color: isSel ? AppColors.ink : AppColors.muted)),
        ]),
      ),
    );
  }
}

/// One collapsible workflow step card.
class NpStepPanel extends StatelessWidget {
  const NpStepPanel({
    super.key,
    required this.index,
    required this.title,
    required this.view,
    required this.open,
    required this.onToggle,
    required this.children,
  });
  final int index;
  final String title;
  final NpStepView? view;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final state = view?.state ?? 'PENDING';
    final color = npStepStateColor(state);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(state == 'PENDING' ? 0.5 : 0.15),
                    border: Border.all(color: color.withOpacity(0.6)),
                  ),
                  alignment: Alignment.center,
                  child: state == 'DONE'
                      ? Icon(Icons.check_rounded, size: 15, color: color)
                      : Text('$index',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: state == 'PENDING' ? AppColors.muted : color)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    if (view != null && (view!.completedBy != null || view!.completedAt != null))
                      NpPersonStamp(person: view!.completedBy, at: view!.completedAt)
                    else if (state != 'PENDING')
                      Text(npTitle(state), style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
                  ]),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.muted),
              ]),
            ),
          ),
          if (open) ...[
            const Divider(height: 1, color: AppColors.hairline),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (view?.remarks != null && view!.remarks!.isNotEmpty) ...[
                    Text(view!.remarks!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 10),
                  ],
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── documents ──

class NpDocumentTile extends StatelessWidget {
  const NpDocumentTile({super.key, required this.doc, this.onDelete, this.onVerify, this.busy = false});
  final NpDocument doc;
  final VoidCallback? onDelete;
  final VoidCallback? onVerify;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final imgUrl = doc.file.isImage ? Env.fileUrl(doc.file.url) : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => npOpenFile(context, doc.file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 52,
                child: imgUrl != null
                    ? Image.network(imgUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fileIcon())
                    : _fileIcon(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(doc.docTypeLabel,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                if (doc.verified)
                  const Icon(Icons.verified_rounded, size: 16, color: AppColors.success)
                else if (doc.superseded)
                  const Icon(Icons.history_rounded, size: 16, color: AppColors.muted),
              ]),
              if (doc.documentNumber != null && doc.documentNumber!.isNotEmpty)
                Text('No. ${doc.documentNumber}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
              if (doc.caption != null && doc.caption!.isNotEmpty)
                Text(doc.caption!, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
              NpPersonStamp(person: doc.uploadedBy, at: doc.uploadedAt),
              if (doc.verified && doc.verifiedBy != null)
                NpPersonStamp(person: doc.verifiedBy, at: doc.verifiedAt, prefix: 'Verified by'),
              Row(children: [
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28), visualDensity: VisualDensity.compact),
                  onPressed: () => npOpenFile(context, doc.file),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('Open', style: TextStyle(fontSize: 12)),
                ),
                if (doc.latitude != null && doc.longitude != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28), visualDensity: VisualDensity.compact),
                    onPressed: () => npOpenMaps(doc.latitude!, doc.longitude!),
                    icon: const Icon(Icons.place_rounded, size: 14),
                    label: const Text('Map', style: TextStyle(fontSize: 12)),
                  ),
                ],
                const Spacer(),
                if (onVerify != null && !doc.verified)
                  TextButton(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 28), visualDensity: VisualDensity.compact),
                    onPressed: busy ? null : onVerify,
                    child: const Text('Verify', style: TextStyle(fontSize: 12)),
                  ),
                if (onDelete != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                  ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _fileIcon() => Container(
        color: AppColors.surfaceAlt,
        alignment: Alignment.center,
        child: Icon(doc.file.isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
            color: AppColors.muted, size: 22),
      );
}

class NpDocumentList extends StatelessWidget {
  const NpDocumentList({
    super.key,
    required this.documents,
    this.emptyText = 'No documents.',
    this.onDelete,
    this.onVerify,
    this.busy = false,
  });
  final List<NpDocument> documents;
  final String emptyText;
  final void Function(NpDocument doc)? onDelete;
  final void Function(NpDocument doc)? onVerify;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Text(emptyText, style: const TextStyle(fontSize: 12.5, color: AppColors.muted));
    }
    return Column(children: [
      for (final d in documents)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NpDocumentTile(
            doc: d,
            busy: busy,
            onDelete: onDelete == null ? null : () => onDelete!(d),
            onVerify: onVerify == null ? null : () => onVerify!(d),
          ),
        ),
    ]);
  }
}

/// Tries to read a current GPS fix, falling back to the last known position.
/// Returns nulls silently when location is unavailable or denied.
Future<({double? lat, double? lng, double? accuracy})> npTryLocation({bool request = true}) async {
  try {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied && request) {
      perm = await Geolocator.requestPermission();
    }
    final granted = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    if (!granted || !serviceOn) return (lat: null, lng: null, accuracy: null);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return (lat: pos.latitude, lng: pos.longitude, accuracy: pos.accuracy);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return (lat: last?.latitude, lng: last?.longitude, accuracy: last?.accuracy);
    }
  } catch (_) {
    return (lat: null, lng: null, accuracy: null);
  }
}

class NpPickedRef {
  final String path;
  final String name;
  const NpPickedRef(this.path, this.name);
}

/// Camera / gallery / PDF chooser. Returns null when dismissed.
Future<NpPickedRef?> npPickFile(BuildContext context, {bool allowPdf = true, bool imagesOnly = false}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(Icons.photo_camera_rounded, color: AppColors.primary),
          title: const Text('Take a photo'),
          onTap: () => Navigator.pop(context, 'camera'),
        ),
        ListTile(
          leading: Icon(Icons.photo_library_rounded, color: AppColors.primary),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(context, 'gallery'),
        ),
        if (allowPdf && !imagesOnly)
          ListTile(
            leading: Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
            title: const Text('Pick a PDF / document'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
      ]),
    ),
  );
  if (choice == null) return null;
  if (choice == 'file') {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: false,
    );
    final f = r?.files.single;
    if (f?.path == null) return null;
    return NpPickedRef(f!.path!, f.name);
  }
  final picked = await ImagePicker().pickImage(
    source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 70,
    maxWidth: 1800,
  );
  if (picked == null) return null;
  final name = picked.name.contains('.') ? picked.name : '${picked.name}.jpg';
  return NpPickedRef(picked.path, name);
}

/// Bottom-sheet uploader for one NP stage: doc type + number + caption +
/// file. With [captureGps] the phone position is attached to the upload —
/// that is how BGV visit photos are geotagged. Returns true when a document
/// was uploaded.
Future<bool> npUploadDocumentSheet(
  BuildContext context,
  WidgetRef ref, {
  required int candidateId,
  required List<NpDocumentTypeConfig> docTypes,
  String? initialDocType,
  bool captureGps = false,
  String? parentType,
  int? parentId,
}) async {
  if (docTypes.isEmpty) {
    npToast(context, 'No document types are configured for this stage.', error: true);
    return false;
  }
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _UploadSheet(
      candidateId: candidateId,
      docTypes: docTypes,
      initialDocType: initialDocType,
      captureGps: captureGps,
      parentType: parentType,
      parentId: parentId,
      ref: ref,
    ),
  );
  return result == true;
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({
    required this.candidateId,
    required this.docTypes,
    this.initialDocType,
    required this.captureGps,
    this.parentType,
    this.parentId,
    required this.ref,
  });
  final int candidateId;
  final List<NpDocumentTypeConfig> docTypes;
  final String? initialDocType;
  final bool captureGps;
  final String? parentType;
  final int? parentId;
  final WidgetRef ref;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  late String _docType;
  final _number = TextEditingController();
  final _caption = TextEditingController();
  NpPickedRef? _file;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _docType = widget.docTypes.any((t) => t.code == widget.initialDocType)
        ? widget.initialDocType!
        : widget.docTypes.first.code;
  }

  @override
  void dispose() {
    _number.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (_file == null) {
      setState(() => _error = 'Pick a file first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      double? lat, lng;
      if (widget.captureGps) {
        final loc = await npTryLocation();
        lat = loc.lat;
        lng = loc.lng;
      }
      await widget.ref.read(npRepositoryProvider).uploadDocument(
            widget.candidateId,
            filePath: _file!.path,
            fileName: _file!.name,
            docType: _docType,
            documentNumber: _number.text,
            caption: _caption.text,
            latitude: lat,
            longitude: lng,
            capturedAt: DateTime.now(),
            parentType: widget.parentType,
            parentId: widget.parentId,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Upload document', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            if (widget.captureGps)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Your current location is attached to the photo.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            const NpFieldLabel('Document type', required: true),
            DropdownButtonFormField<String>(
              value: _docType,
              isExpanded: true,
              items: [
                for (final t in widget.docTypes)
                  DropdownMenuItem(value: t.code, child: Text(t.mandatory ? '${t.label} *' : t.label)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _docType = v ?? _docType),
            ),
            const NpFieldLabel('Document number'),
            TextField(controller: _number, decoration: const InputDecoration(hintText: 'Optional')),
            const NpFieldLabel('Caption'),
            TextField(
              controller: _caption,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Optional'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final f = await npPickFile(context);
                      if (f != null) setState(() => _file = f);
                    },
              icon: Icon(_file == null ? Icons.attach_file_rounded : Icons.check_rounded, size: 18),
              label: Text(_file == null ? 'Choose file (photo or PDF)' : _file!.name, overflow: TextOverflow.ellipsis),
            ),
            if (_file != null && !_file!.name.toLowerCase().endsWith('.pdf')) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(_file!.path), height: 140, fit: BoxFit.cover),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(_busy ? 'Uploading…' : 'Upload'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple "pick a file" field for the agreement / PDC scans.
class NpFilePickField extends StatelessWidget {
  const NpFilePickField({super.key, required this.label, required this.fileName, required this.onPick, this.required = true});
  final String label;
  final String? fileName;
  final VoidCallback onPick;
  final bool required;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NpFieldLabel(label, required: required),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: Icon(fileName == null ? Icons.attach_file_rounded : Icons.check_circle_rounded,
              size: 18, color: fileName == null ? null : AppColors.success),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(fileName ?? 'Choose photo or PDF', overflow: TextOverflow.ellipsis),
          ),
        ),
      ]);
}

/// Exposes the picker's result type for callers outside this file.
typedef NpPickedFile = ({String path, String name});

Future<NpPickedFile?> npPickAnyFile(BuildContext context) async {
  final f = await npPickFile(context);
  return f == null ? null : (path: f.path, name: f.name);
}
