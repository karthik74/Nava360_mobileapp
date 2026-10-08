import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
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
    final loaded = async.valueOrNull;
    // Sticky acknowledge bar while an acknowledgement is still owed.
    final showAckBar = loaded != null &&
        loaded.requiresAcknowledgement &&
        !loaded.acknowledged;

    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
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
          final p = a.priority;
          return ProPage(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            hero: ProHero(
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (a.pinned)
                      const ProHeroTag('Pinned',
                          tone: ProTagTone.ok, icon: Icons.push_pin_rounded),
                    ProHeroTag(
                      _sentence(p),
                      tone: p == 'URGENT'
                          ? ProTagTone.bad
                          : (p == 'HIGH' ? ProTagTone.warn : ProTagTone.neutral),
                    ),
                    ProHeroTag(_sentence(a.category)),
                    if (a.mandatory)
                      const ProHeroTag('Mandatory', tone: ProTagTone.bad),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.55,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Published ${_fmt(a.publishedAt)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (a.requiresAcknowledgement)
                  ProLiveLine(
                    text: a.acknowledged
                        ? 'Acknowledged on ${_fmt(a.acknowledgedAt)}'
                        : 'Please read and acknowledge this announcement',
                    color: a.acknowledged
                        ? AppColors.live
                        : const Color(0xFFF2B347),
                  ),
              ],
            ),
            children: [
              // ── Image attachments preview FIRST (poster before the body) ──
              for (final att in images)
                _ImageAttachment(
                  att: att,
                  // Opens the in-app fullscreen viewer (no browser redirect).
                  onView: () => _viewImage(context, att),
                  onOpenExternally: () => _open(context, att),
                ),
              if (a.description != null && a.description!.trim().isNotEmpty)
                GlassCard(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  // The body is HTML (rich text with inline styles) — render it so
                  // headings, lists, colours and links show as intended. Links open
                  // in the external browser.
                  child: HtmlWidget(
                    a.description!,
                    textStyle: const TextStyle(
                        fontSize: 15, height: 1.6, color: AppColors.inkSoft),
                    onTapUrl: (url) =>
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  ),
                ),
              if (otherAttachments.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProSectionHeader(
                      title: 'Attachments · ${otherAttachments.length}',
                      small: true,
                    ),
                    const SizedBox(height: 10),
                    ProListGroup(
                      children: [
                        for (final att in otherAttachments)
                          ProListRow(
                            leading: ProIconWell(
                              icon: att.kind == 'LINK'
                                  ? Icons.link_rounded
                                  : Icons.description_rounded,
                              color: att.kind == 'LINK'
                                  ? AppColors.info
                                  : AppColors.danger,
                            ),
                            title: att.fileName ?? att.url,
                            subtitle: att.caption != null &&
                                    att.caption!.isNotEmpty
                                ? att.caption
                                : null,
                            chevron: false,
                            trailing: const Icon(Icons.open_in_new_rounded,
                                size: 18, color: AppColors.faint),
                            onTap: () => _open(context, att),
                          ),
                      ],
                    ),
                  ],
                ),
              if (a.requiresAcknowledgement && a.acknowledged)
                ProNote(
                  'Acknowledged on ${_fmt(a.acknowledgedAt)}',
                  tone: ProNoteTone.ok,
                  icon: Icons.verified_rounded,
                ),
              if (a.allowComments)
                _CommentsSection(announcementId: announcementId),
            ],
          );
        },
      ),
      bottomNavigationBar: showAckBar
          ? ProBottomBar(
              children: [_AckButton(announcementId: announcementId)],
            )
          : null,
    );
  }

  /// "HR_NOTICE" → "HR notice", "URGENT" → "Urgent".
  static String _sentence(String code) {
    var t = code.replaceAll('_', ' ').toLowerCase();
    t = t.replaceFirst(RegExp(r'^hr\b'), 'HR');
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
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
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
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
                        const ProIconWell(
                            icon: Icons.image_rounded, color: AppColors.info),
                        const SizedBox(width: 10),
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
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(att.caption!, style: AppText.caption),
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
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: 'Comments',
            trailing: _loading ? null : ProPill.neutral('${_comments.length}'),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const AppLoadingBlock(height: 60)
          else if (_comments.isEmpty)
            const Text('No comments yet.', style: AppText.caption)
          else
            for (final c in _comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProAvatar(name: c.employeeName ?? 'Someone', size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(5),
                            topRight: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                            bottomLeft: Radius.circular(14),
                          ),
                          border: Border.all(color: AppColors.hairlineSoft),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.employeeName ?? 'Someone',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.comment,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [TitleCaseTextFormatter()],
                  decoration: const InputDecoration(
                    hintText: 'Write a comment…',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Post comment',
                onPressed: _posting ? null : _post,
                icon: const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
