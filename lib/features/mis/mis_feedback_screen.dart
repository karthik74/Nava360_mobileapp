// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Feedback (route /mis/feedback). Compose new feedback (POST /feedback)
//  and read the team timeline (GET /feedback). Ports FeedbackScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';

const _categories = <(String, Color)>[
  ('General', AppColors.success),
  ('Bug', AppColors.danger),
  ('Suggestion', AppColors.pink),
  ('Data issue', AppColors.warning),
  ('Request', AppColors.accent),
  ('Other', AppColors.muted),
];

Color _catColor(String? name) {
  for (final c in _categories) {
    if (c.$1 == (name ?? 'General')) return c.$2;
  }
  return AppColors.success;
}

String _sentence(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class MisFeedbackScreen extends ConsumerStatefulWidget {
  const MisFeedbackScreen({super.key});

  @override
  ConsumerState<MisFeedbackScreen> createState() => _MisFeedbackScreenState();
}

class _MisFeedbackScreenState extends ConsumerState<MisFeedbackScreen> {
  String _category = 'General';
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _ok;
  String? _err;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _ok = null;
      _err = null;
    });
    try {
      await ref
          .read(misRepositoryProvider)
          .submitFeedback(_category, _title.text, _body.text);
      if (!mounted) return;
      setState(() {
        _ok = 'Feedback submitted. Thank you!';
        _title.clear();
        _body.clear();
      });
      ref.invalidate(misFeedbackProvider);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(misFeedbackProvider);
    final items = listAsync.asData?.value;
    final open = items?.where((f) => f.isOpen).length ?? 0;
    final done = (items?.length ?? 0) - open;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Feedback',
        subtitle: 'Raise an issue or suggestion',
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white,
        onRefresh: () async => ref.invalidate(misFeedbackProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _compose(),
            const SizedBox(height: 22),
            ProSectionHeader(
              title: 'Recent feedback',
              subtitle: items == null || items.isEmpty
                  ? 'Managers see their team\'s feedback.'
                  : '$open open · $done resolved · managers see their team\'s feedback',
            ),
            const SizedBox(height: 10),
            listAsync.when(
              loading: () => const AppLoadingBlock(height: 140),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(misFeedbackProvider),
              ),
              data: (items) => items.isEmpty
                  ? const ProEmpty(
                      icon: Icons.forum_outlined,
                      title: 'No feedback yet',
                      message: 'No feedback yet — be the first to share.',
                    )
                  : ProListGroup(
                      dividerIndent: 0,
                      children: [
                        for (final f in items) _FeedbackTile(item: f),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton.icon(
            onPressed: (_busy || _body.text.trim().isEmpty) ? null : _send,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(_busy ? 'Sending…' : 'Submit feedback'),
          ),
        ],
      ),
    );
  }

  Widget _compose() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProIconWell(icon: Icons.forum_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: ProSectionHeader(
                  title: 'New feedback',
                  subtitle: 'We read every message.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_ok != null) ...[
            ProNote(_ok!, tone: ProNoteTone.ok),
            const SizedBox(height: 12),
          ],
          if (_err != null) ...[
            ProNote(_err!, tone: ProNoteTone.bad),
            const SizedBox(height: 12),
          ],
          ProField(
            label: 'Category',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _categories)
                  _CategoryChip(
                    label: c.$1,
                    color: c.$2,
                    selected: _category == c.$1,
                    onTap: () => setState(() => _category = c.$1),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ProField(
            label: 'Title',
            child: TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Short summary'),
            ),
          ),
          const SizedBox(height: 14),
          ProField(
            label: 'Details',
            required: true,
            child: TextField(
              controller: _body,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Describe it…'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}

/// Category choice: ink when selected, category colour as a dot.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
              color: selected ? AppColors.ink : const Color(0xFFDBE3E5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: Colors.white, width: 1.2)
                    : null,
              ),
            ),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({required this.item});
  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final color = _catColor(item.category);
    final status = _sentence(item.status ?? 'open');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProAvatar(name: item.name ?? '?', size: 38, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.name ?? 'Unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.15,
                              color: AppColors.ink)),
                    ),
                    const SizedBox(width: 8),
                    item.isOpen ? ProPill.warn(status) : ProPill.ok(status),
                  ],
                ),
                Text('${item.branch ?? '—'} · ${misPrettyDate(item.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption),
                if (item.title != null && item.title!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(item.title!,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                ],
                if (item.body != null && item.body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(item.body!,
                      style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.inkSoft,
                          height: 1.45)),
                ],
                const SizedBox(height: 9),
                ProPill(item.category ?? 'General', color: color, dot: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
