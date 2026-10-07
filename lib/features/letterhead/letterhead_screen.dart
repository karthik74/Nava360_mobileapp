import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'letterhead_align_screen.dart';
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerTint,
              foregroundColor: AppColors.danger,
            ),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Letter head')),
      body: ProPage(
        onRefresh: () async => ref.invalidate(letterheadProvider),
        hero: const ProHero(
          title: 'Letter head',
          subtitle: 'Admin tools · A4 print guide',
          children: [
            _HeroIntro(
              title: 'Your letterhead guide',
              body: 'Upload a letterhead template (PDF or image). Use it to line up '
                  'your documents when printing — Nava360 stores only this guide '
                  'file; alignment and export happen on your own printer/desktop.',
            ),
          ],
        ),
        children: [
          async.when(
            data: (lh) => lh == null
                ? const ProEmpty(
                    icon: Icons.description_outlined,
                    title: 'No letterhead uploaded yet.',
                    message: 'Upload a PDF, JPG or PNG with the button below.',
                  )
                : _LetterheadCard(letterhead: lh, onDelete: _busy ? null : _delete),
            loading: () => const AppLoadingBlock(height: 160),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(letterheadProvider),
            ),
          ),
          if (_busy)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: AppColors.hairlineSoft,
              ),
            ),
          ProListGroup(
            children: [
              ProListRow(
                leading: ProIconWell(
                  icon: Icons.picture_as_pdf_rounded,
                  color: AppColors.primary,
                ),
                title: 'Align & export PDF',
                subtitle: 'Position a letter PDF on A4 for pre-printed paper',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LetterheadAlignScreen())),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _upload,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(async.value == null ? 'Upload letterhead' : 'Replace letterhead'),
          ),
        ],
      ),
    );
  }
}

/// Heading + explanation on the deep hero.
class _HeroIntro extends StatelessWidget {
  const _HeroIntro({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.24,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
        ),
      ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProIconWell(
                icon: letterhead.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                color: AppColors.primary,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      letterhead.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (letterhead.uploadedAt != null)
                      Text(
                        'Uploaded ${df.format(letterhead.uploadedAt!)}',
                        style: AppText.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                Material(
                  color: AppColors.dangerTint,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onDelete,
                    child: const Tooltip(
                      message: 'Delete',
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.delete_outline_rounded,
                            size: 19, color: AppColors.danger),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (letterhead.isImage) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: AppShadows.card,
                    ),
                    clipBehavior: Clip.antiAlias,
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
                  const SizedBox(height: 10),
                  const Text('A4 portrait · 210 × 297 mm', style: AppText.caption),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
