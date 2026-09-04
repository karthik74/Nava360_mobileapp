import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'letterhead_models.dart';
import 'letterhead_repository.dart';

/// Resolves a stored relative file url (`/api/files/{id}` style) to an
/// absolute URL, mirroring `absoluteFileUrl` in `form_renderer.dart`.
String _absoluteUrl(String url) {
  if (url.startsWith('http')) return url;
  final base = Env.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$base$url';
}

final letterheadProvider = FutureProvider.autoDispose<AdminLetterhead?>((ref) {
  return ref.watch(letterheadRepositoryProvider).mine();
});

/// Admin Tools · Letter Head — mirrors `LetterHeadPage.tsx`, but scoped down
/// for mobile.
///
/// The web page lets a user upload a PDF, drag/scale it over a letterhead
/// guide image, and export a merged A4 PDF client-side using pdf-lib/pdf.js.
/// The backend (`AdminLetterheadController` / `AdminLetterheadTemplate`)
/// never actually persists that alignment (offset/scale) — it only stores
/// ONE guide file per user (`GET/POST/DELETE /api/admin/letterhead`), and
/// the aligned PDF the web builds is only ever downloaded locally, never
/// uploaded. Since there's no server-side alignment state to edit, and
/// Flutter has no PDF-composition library in this project (only the
/// view-only `flutter_pdfview`), building a drag/scale canvas here would
/// have nothing to save and nowhere to send its output — so this screen
/// intentionally limits itself to what the backend actually supports:
/// viewing, uploading, and deleting the saved guide file.
class LetterheadScreen extends ConsumerStatefulWidget {
  const LetterheadScreen({super.key});

  @override
  ConsumerState<LetterheadScreen> createState() => _LetterheadScreenState();
}

class _LetterheadScreenState extends ConsumerState<LetterheadScreen> {
  bool _busy = false;

  Future<void> _upload() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final path = res?.files.single.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(letterheadRepositoryProvider)
          .upload(path, filename: res!.files.single.name);
      ref.invalidate(letterheadProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Letterhead uploaded')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete letterhead?'),
        content: const Text('This removes your saved letterhead guide file.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(letterheadRepositoryProvider).delete();
      ref.invalidate(letterheadProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Letterhead deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(letterheadProvider);
    final mq = MediaQuery.of(context);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Letter Head'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(letterheadProvider),
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 24),
            children: [
              const AppSectionHeader(
                title: 'Your letterhead guide',
                subtitle:
                    'Upload a letterhead template (PDF or image). Use it to line up '
                    'your documents when printing — Nava360 stores only this guide '
                    'file; alignment and export happen on your own printer/desktop.',
              ),
              const SizedBox(height: 12),
              async.when(
                data: (lh) => lh == null
                    ? const AppEmptyState(
                        icon: Icons.description_outlined,
                        message: 'No letterhead uploaded yet.',
                      )
                    : _LetterheadCard(letterhead: lh, onDelete: _busy ? null : _delete),
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(letterheadProvider),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(async.value == null ? 'Upload letterhead' : 'Replace letterhead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LetterheadCard extends StatelessWidget {
  const _LetterheadCard({required this.letterhead, required this.onDelete});
  final AdminLetterhead letterhead;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy, HH:mm');
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.primary.withOpacity(0.22)),
                ),
                alignment: Alignment.center,
                child: Icon(
                  letterhead.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                  color: AppColors.primary,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      letterhead.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink),
                    ),
                    if (letterhead.uploadedAt != null)
                      Text(
                        'Uploaded ${df.format(letterhead.uploadedAt!)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 19, color: AppColors.danger),
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          if (letterhead.isImage) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: AspectRatio(
                aspectRatio: 1 / 1.414, // A4 portrait
                child: Image.network(
                  _absoluteUrl(letterhead.url),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: AppColors.surface,
                    child: Center(
                      child: Icon(Icons.broken_image_outlined, color: AppColors.muted),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
