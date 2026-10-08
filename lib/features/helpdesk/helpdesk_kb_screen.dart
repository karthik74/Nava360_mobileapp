import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';

/// Knowledge base browse + search.
class KnowledgeBaseScreen extends ConsumerStatefulWidget {
  const KnowledgeBaseScreen({super.key});
  @override
  ConsumerState<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends ConsumerState<KnowledgeBaseScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<HdKbArticleSummary> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String? q) async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(helpdeskRepositoryProvider).browseArticles(q: q);
      if (mounted) setState(() { _rows = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(v.trim().isEmpty ? null : v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final votes = _rows.fold<int>(0, (a, r) => a + r.helpfulCount);
    final topics = <String>{
      for (final r in _rows)
        if ((r.tags ?? '').trim().isNotEmpty) r.tags!.split(',').first.trim().toLowerCase(),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge base')),
      body: ProPage(
        hero: ProHero(
          title: 'Knowledge base',
          subtitle: _loading
              ? 'Helpdesk'
              : 'Helpdesk · ${_rows.length} ${_rows.length == 1 ? 'article' : 'articles'}',
          overlap: _SearchBox(controller: _search, onChanged: _onSearch),
          children: [
            ProHeroStats(stats: [
              ProStat(
                label: 'Articles',
                value: _loading ? '—' : '${_rows.length}',
                sub: _loading ? null : '${topics.length} ${topics.length == 1 ? 'topic' : 'topics'}',
                dot: const Color(0xFF5AA9F0),
              ),
              ProStat(
                label: 'Helpful votes',
                value: _loading ? '—' : '$votes',
                sub: 'from colleagues',
                dot: AppColors.live,
              ),
            ]),
          ],
        ),
        children: [
          if (_loading)
            ...const [AppLoadingBlock(height: 72), AppLoadingBlock(height: 72)]
          else if (_rows.isEmpty)
            const ProEmpty(
              icon: Icons.menu_book_rounded,
              title: 'No articles found.',
              message: 'Try another word.',
            )
          else ...[
            ProSectionHeader(
              title: '${_rows.length} ${_rows.length == 1 ? 'article' : 'articles'}',
              small: true,
            ),
            ProListGroup(
              children: [
                for (final a in _rows)
                  ProListRow(
                    leading: ProIconWell(icon: Icons.article_outlined, color: AppColors.primary),
                    title: a.title,
                    titleMaxLines: 2,
                    subtitle: [
                      if (a.tags != null && a.tags!.isNotEmpty) a.tags!,
                      if (a.helpfulCount > 0) '${a.helpfulCount} helpful',
                    ].join(' · ').ifEmptyNull,
                    onTap: () => context.push('/helpdesk/kb/${a.id}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

/// Raised search field that keeps the original title-case input formatter.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: AppColors.hairline),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: AppShadows.lifted,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.words,
        inputFormatters: const [TitleCaseTextFormatter()],
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: 'Search articles…',
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// Single KB article with helpful/not-helpful rating.
class KbArticleScreen extends ConsumerStatefulWidget {
  const KbArticleScreen({super.key, required this.articleId});
  final int articleId;
  @override
  ConsumerState<KbArticleScreen> createState() => _KbArticleScreenState();
}

class _KbArticleScreenState extends ConsumerState<KbArticleScreen> {
  late Future<HdKbArticle> _future;
  bool _rated = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(helpdeskRepositoryProvider).getArticle(widget.articleId);
  }

  Future<void> _rate(bool helpful) async {
    setState(() => _rated = true);
    try { await ref.read(helpdeskRepositoryProvider).rateArticle(widget.articleId, helpful); } catch (_) {}
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your feedback')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Article')),
      body: FutureBuilder<HdKbArticle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: AppErrorPanel(message: '${snap.error}'));
          final a = snap.data!;
          return ProPage(
            hero: ProHero(
              // Full title (no 2-line clamp) — articles often have long names.
              titleWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Knowledge base',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white70)),
                  Text(a.title,
                      style: const TextStyle(
                          fontSize: 22,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.55,
                          color: Colors.white)),
                  if (a.helpfulCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${a.helpfulCount} found this helpful',
                          style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
                    ),
                ],
              ),
            ),
            children: [
              GlassCard(
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.inkSoft),
                  child: HtmlWidget(a.bodyHtml ?? ''),
                ),
              ),
              GlassCard(
                child: !_rated
                    ? Row(
                        children: [
                          const Expanded(
                            child: Text('Was this helpful?',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink)),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => _rate(true),
                            icon: const Icon(Icons.thumb_up_outlined, size: 16),
                            label: const Text('Yes'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => _rate(false),
                            icon: const Icon(Icons.thumb_down_outlined, size: 16),
                            label: const Text('No'),
                          ),
                        ],
                      )
                    : const Row(
                        children: [
                          ProIconWell(icon: Icons.check_rounded, color: AppColors.success),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('Thanks for your feedback!',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.success)),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
