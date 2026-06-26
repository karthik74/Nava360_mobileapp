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
          data: (a) => ListView(
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
              if (a.attachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                const AppSectionHeader(title: 'Attachments'),
                const SizedBox(height: 8),
                for (final att in a.attachments)
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
