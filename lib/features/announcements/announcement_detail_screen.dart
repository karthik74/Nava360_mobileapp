import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'announcements_models.dart';
import 'announcements_repository.dart';

/// Opening detail also marks the announcement read (the /read endpoint returns
/// the full announcement), so this doubles as the deep-link target for pushes.
final announcementDetailProvider =
    FutureProvider.autoDispose.family<MyAnnouncement, int>((ref, id) {
  return ref.watch(announcementsRepositoryProvider).markRead(id);
});

Color priorityColor(String p) {
  switch (p) {
    case 'URGENT':
      return AppColors.danger;
    case 'HIGH':
      return AppColors.warning;
    case 'LOW':
      return AppColors.muted;
    default:
      return AppColors.primary;
  }
}

class AnnouncementDetailScreen extends ConsumerWidget {
  const AnnouncementDetailScreen({super.key, required this.announcementId});
  final int announcementId;

  String _fmt(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(d);

  Future<void> _open(BuildContext context, AnnouncementAttachment att) async {
    final url = att.kind == 'LINK' ? att.url : (Env.fileUrl(att.url) ?? att.url);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open attachment')),
      );
    }
  }

  /// Fullscreen in-app viewer with pinch-zoom — announcement posters stay in
  /// the app instead of bouncing to the browser.
  void _viewImage(BuildContext context, AnnouncementAttachment att) {
    final url = Env.fileUrl(att.url) ?? att.url;
    Navigator.of(context).push(PageRouteBuilder(
      fullscreenDialog: true,
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) =>
          _FullscreenImage(url: url, title: att.fileName ?? 'Image'),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Uploaded image files preview inline at the top (poster-style); everything
  /// else stays in the attachment list below the body.
  static bool _isImage(AnnouncementAttachment att) {
    if (att.kind != 'FILE') return false;
    final t = att.fileType?.toLowerCase() ?? '';
    if (t.startsWith('image/')) return true;
    final n = (att.fileName ?? '').toLowerCase();
    return const ['.jpg', '.jpeg', '.jfif', '.png', '.gif', '.webp', '.bmp']
        .any(n.endsWith);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementDetailProvider(announcementId));

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Announcement'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(announcementDetailProvider(announcementId)),
            ),
          ),
          data: (a) {
            final images = a.attachments.where(_isImage).toList();
            final otherAttachments =
                a.attachments.where((t) => !_isImage(t)).toList();
            return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (a.pinned) const StatusPill(label: '📌 Pinned', color: AppColors.pink),
                  StatusPill(label: a.priority, color: priorityColor(a.priority)),
                  StatusPill(label: a.category.replaceAll('_', ' '), color: AppColors.muted),
                  if (a.mandatory) const StatusPill(label: 'Mandatory', color: AppColors.danger),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                a.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              Text('Published ${_fmt(a.publishedAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              // ── Image attachments preview FIRST (poster before the body) ──
              if (images.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final att in images)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ImageAttachment(
                      att: att,
                      // Opens the in-app fullscreen viewer (no browser redirect).
                      onView: () => _viewImage(context, att),
                      onOpenExternally: () => _open(context, att),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              if (a.description != null && a.description!.trim().isNotEmpty)
                GlassCard(
                  shadow: AppShadows.soft,
                  // The body is HTML (rich text with inline styles) — render it so
                  // headings, lists, colours and links show as intended. Links open
                  // in the external browser.
                  child: HtmlWidget(
                    a.description!,
                    textStyle: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkSoft),
                    onTapUrl: (url) =>
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  ),
                ),
              if (otherAttachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                const AppSectionHeader(title: 'Attachments'),
                const SizedBox(height: 8),
                for (final att in otherAttachments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassCard(
                      padding: const EdgeInsets.all(12),
                      shadow: AppShadows.soft,
                      child: InkWell(
                        onTap: () => _open(context, att),
                        child: Row(
                          children: [
                            Icon(att.kind == 'LINK' ? Icons.link_rounded : Icons.description_rounded,
                                color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(att.fileName ?? att.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600, color: AppColors.ink)),
                                  if (att.caption != null && att.caption!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(att.caption!,
                                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              if (a.requiresAcknowledgement)
                a.acknowledged
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: AppColors.success.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Acknowledged on ${_fmt(a.acknowledgedAt)}',
                                  style: const TextStyle(
                                      color: AppColors.success, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      )
                    : _AckButton(announcementId: announcementId),
              if (a.allowComments) ...[
                const SizedBox(height: 20),
                _CommentsSection(announcementId: announcementId),
              ],
            ],
          );
          },
        ),
      ),
    );
  }
}

/// Inline preview of an uploaded image attachment: full width but capped in
/// height, whole poster visible (contain, no cropping). Tap → in-app viewer.
class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({
    required this.att,
    required this.onView,
    required this.onOpenExternally,
  });
  final AnnouncementAttachment att;
  final VoidCallback onView;
  /// Fallback for files the app can't render inline (opens the browser).
  final VoidCallback onOpenExternally;

  static const double _maxHeight = 320;

  @override
  Widget build(BuildContext context) {
    final url = Env.fileUrl(att.url) ?? att.url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onView,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: _maxHeight),
              color: AppColors.surface,
              child: Image.network(
                url,
                width: double.infinity,
                // Whole poster stays visible (announcements are usually A4/portrait
                // artwork — cover-cropping them hides the content).
                fit: BoxFit.contain,
                loadingBuilder: (c, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 200,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                // Unrenderable image (or fetch error) → compact open-in-browser row.
                errorBuilder: (c, e, s) => InkWell(
                  onTap: onOpenExternally,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.image_rounded, color: AppColors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            att.fileName ?? 'Image',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: AppColors.ink),
                          ),
                        ),
                        const Icon(Icons.open_in_new_rounded,
                            size: 16, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (att.caption != null && att.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(att.caption!,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
      ],
    );
  }
}

/// Black fullscreen image view with pinch-zoom and double-tap reset.
class _FullscreenImage extends StatefulWidget {
  const _FullscreenImage({required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<_FullscreenImage> createState() => _FullscreenImageState();
}

class _FullscreenImageState extends State<_FullscreenImage> {
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
      ),
      body: GestureDetector(
        onDoubleTap: () => _controller.value = Matrix4.identity(),
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.network(
              widget.url,
              fit: BoxFit.contain,
              loadingBuilder: (c, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54),
                    ),
              errorBuilder: (c, e, s) => const Center(
                child: Text('Could not load image',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AckButton extends ConsumerStatefulWidget {
  const _AckButton({required this.announcementId});
  final int announcementId;

  @override
  ConsumerState<_AckButton> createState() => _AckButtonState();
}

class _AckButtonState extends ConsumerState<_AckButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(announcementsRepositoryProvider).acknowledge(widget.announcementId);
                  ref.invalidate(announcementDetailProvider(widget.announcementId));
                  messenger.showSnackBar(const SnackBar(content: Text('Acknowledged ✓')));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
        label: Text(_busy ? 'Submitting…' : 'Acknowledge'),
      ),
    );
  }
}

class _CommentsSection extends ConsumerStatefulWidget {
  const _CommentsSection({required this.announcementId});
  final int announcementId;

  @override
  ConsumerState<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<_CommentsSection> {
  final _ctrl = TextEditingController();
  List<AnnouncementComment> _comments = [];
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ref.read(announcementsRepositoryProvider).listComments(widget.announcementId);
      if (mounted) setState(() => _comments = c);
    } catch (_) {
      // non-fatal
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final c = await ref.read(announcementsRepositoryProvider).addComment(widget.announcementId, text);
      setState(() {
        _comments = [..._comments, c];
        _ctrl.clear();
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'Comments'),
        const SizedBox(height: 8),
        if (_loading)
          const AppLoadingBlock(height: 60)
        else if (_comments.isEmpty)
          const Text('No comments yet.', style: TextStyle(color: AppColors.muted))
        else
          for (final c in _comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                shadow: AppShadows.soft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.employeeName ?? 'Someone',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(c.comment, style: const TextStyle(color: AppColors.inkSoft)),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'Write a comment…',
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide: const BorderSide(color: AppColors.hairline),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _posting ? null : _post,
              icon: const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}
