import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';

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
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: AppColors.surface, foregroundColor: AppColors.ink, elevation: 0.5,
          title: const Text('Knowledge Base'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search articles…'),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? const AppEmptyState(icon: Icons.menu_book_rounded, message: 'No articles found.')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final a = _rows[i];
                            return GlassCard(
                              padding: const EdgeInsets.all(12),
                              shadow: AppShadows.soft,
                              child: InkWell(
                                onTap: () => context.push('/helpdesk/kb/${a.id}'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                                    if (a.tags != null && a.tags!.isNotEmpty)
                                      Padding(padding: const EdgeInsets.only(top: 4),
                                          child: Text(a.tags!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
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
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: AppColors.surface, foregroundColor: AppColors.ink, elevation: 0.5, title: const Text('Article')),
        body: FutureBuilder<HdKbArticle>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: AppErrorPanel(message: '${snap.error}'));
            final a = snap.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(a.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 12),
                HtmlWidget(a.bodyHtml ?? ''),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                if (!_rated) ...[
                  const Text('Was this helpful?', style: TextStyle(color: AppColors.inkSoft)),
                  const SizedBox(height: 8),
                  Row(children: [
                    OutlinedButton.icon(onPressed: () => _rate(true), icon: const Icon(Icons.thumb_up_outlined, size: 16), label: const Text('Yes')),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(onPressed: () => _rate(false), icon: const Icon(Icons.thumb_down_outlined, size: 16), label: const Text('No')),
                  ]),
                ] else
                  const Text('Thanks for your feedback!', style: TextStyle(color: AppColors.success)),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}
