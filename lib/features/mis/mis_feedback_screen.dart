// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Feedback (route /mis/feedback). Compose new feedback (POST /feedback)
//  and read the team timeline (GET /feedback). Ports FeedbackScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

const _categories = <(String, Color)>[
  ('General', AppColors.success),
  ('Bug', Color(0xFFF43F5E)),
  ('Suggestion', Color(0xFF8B5CF6)),
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

String _initials(String? name) {
  final parts = (name ?? '?').trim().split(RegExp(r'\s+'));
  final letters =
      parts.where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join();
  return letters.isEmpty ? '?' : letters.toUpperCase();
}

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Feedback')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => ref.invalidate(misFeedbackProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
          children: [
            const AppPageHeader(
              title: 'Feedback',
              subtitle:
                  'Raise an issue or suggestion. Managers see their team\'s feedback.',
            ),
            const SizedBox(height: 16),
            _compose(),
            const SizedBox(height: 20),
            const MisSectionTitle('Recent feedback'),
            listAsync.when(
              loading: () => const AppLoadingBlock(height: 140),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(misFeedbackProvider),
              ),
              data: (items) => items.isEmpty
                  ? const MisInlineEmpty(
                      'No feedback yet — be the first to share.')
                  : Column(
                      children: [
                        for (final f in items) ...[
                          _FeedbackTile(item: f),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compose() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.forum_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New feedback',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    Text('We read every message.',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_ok != null) ...[
            _banner(_ok!, AppColors.success),
            const SizedBox(height: 12),
          ],
          if (_err != null) ...[
            _banner(_err!, AppColors.danger),
            const SizedBox(height: 12),
          ],
          const Text('Category',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _categories)
                GestureDetector(
                  onTap: () => setState(() => _category = c.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _category == c.$1
                          ? c.$2.withOpacity(0.14)
                          : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                          color: _category == c.$1
                              ? c.$2.withOpacity(0.5)
                              : AppColors.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: c.$2, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(c.$1,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _category == c.$1
                                    ? c.$2
                                    : AppColors.inkSoft)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Title', hintText: 'Short summary'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
                labelText: 'Details', hintText: 'Describe it…'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_busy || _body.text.trim().isEmpty) ? null : _send,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(_busy ? 'Sending…' : 'Submit feedback'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({required this.item});
  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final color = _catColor(item.category);
    return GlassCard(
      padding: EdgeInsets.zero,
      shadow: AppShadows.soft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(_initials(item.name),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: color)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name ?? 'Unknown',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink)),
                            Text(item.branch ?? '—',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: item.status ?? 'open',
                        color: item.isOpen ? AppColors.warning : AppColors.success,
                        icon: item.isOpen
                            ? Icons.schedule_rounded
                            : Icons.check_circle_rounded,
                      ),
                    ],
                  ),
                  if (item.title != null && item.title!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.title!,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                  ],
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(item.body!,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                            height: 1.4)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(item.category ?? 'General',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ),
                      const Spacer(),
                      Text(misPrettyDate(item.createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
