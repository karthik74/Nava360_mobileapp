// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — dashboard (KPI tiles) + scoped candidate list.
//  Route: /np. Mirrors the web `/np` page: tiles filter the list by status,
//  search by name/code/mobile, "New candidate" for NP_CANDIDATE_CREATE.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'np_models.dart';
import 'np_repository.dart';
import 'np_widgets.dart';

class NpDashboardScreen extends ConsumerStatefulWidget {
  const NpDashboardScreen({super.key});

  @override
  ConsumerState<NpDashboardScreen> createState() => _NpDashboardScreenState();
}

class _NpDashboardScreenState extends ConsumerState<NpDashboardScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  NpListFilter _filter = const NpListFilter();
  String? _selectedCard = 'total';

  final _items = <NpCandidateSummary>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    ref.invalidate(npDashboardProvider(_filter));
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final p = await ref.read(npRepositoryProvider).list(_filter, page: _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(p.content);
        _page = p.page + 1;
        _hasMore = p.hasMore;
        _total = p.totalElements;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _filter = _filter.copyWith(q: v);
      _reload();
    });
  }

  void _selectCard(NpDashboardCard c) {
    setState(() {
      _selectedCard = c.key;
      _filter = _filter.copyWith(statuses: c.statuses);
    });
    _reload();
  }

  Future<void> _pickStatus() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: const Text('All statuses'),
            leading: const Icon(Icons.clear_all_rounded),
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final s in kNpStatuses)
            ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 10, color: npStatusColor(s)),
              title: Text(npStatusLabel(s)),
              selected: _filter.statuses.length == 1 && _filter.statuses.first == s,
              onTap: () => Navigator.pop(context, s),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    setState(() {
      _selectedCard = picked.isEmpty ? 'total' : null;
      _filter = _filter.copyWith(statuses: picked.isEmpty ? const [] : [picked]);
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final canCreate = user?.hasPermission('NP_CANDIDATE_CREATE') ?? false;
    final dash = ref.watch(npDashboardProvider(_filter));

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('NP Onboarding'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          actions: [
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
          ],
        ),
        floatingActionButton: canCreate
            ? FloatingActionButton.extended(
                onPressed: () async {
                  final changed = await context.push<bool>('/np/candidates/new');
                  if (changed == true) _reload();
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('New candidate'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: _reload,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _loadMore();
              return false;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                const AppPageHeader(title: 'Prathinidhi pipeline', subtitle: 'Candidates you can see, by workflow stage'),
                const SizedBox(height: 12),
                // ── KPI tiles ──
                SizedBox(
                  height: 92,
                  child: dash.when(
                    data: (d) => ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: kNpDashboardCards.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final c = kNpDashboardCards[i];
                        final sel = _selectedCard == c.key;
                        return SizedBox(
                          width: 128,
                          child: _KpiTile(card: c, value: d.valueOf(c.key), selected: sel, onTap: () => _selectCard(c)),
                        );
                      },
                    ),
                    loading: () => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                    error: (e, _) => AppErrorPanel(message: '$e', onRetry: _reload),
                  ),
                ),
                const SizedBox(height: 14),
                // ── search + status filter ──
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search name, code or mobile',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _search.clear();
                                  _onSearchChanged('');
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppIconButton(
                    icon: Icons.filter_list_rounded,
                    onTap: _pickStatus,
                    color: _filter.statuses.isEmpty ? null : AppColors.primary,
                  ),
                ]),
                if (_filter.statuses.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in _filter.statuses) NpStatusPill(status: s),
                    ActionChip(
                      label: const Text('Clear'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _selectedCard = 'total';
                          _filter = _filter.copyWith(statuses: const []);
                        });
                        _reload();
                      },
                    ),
                  ]),
                ],
                const SizedBox(height: 12),
                AppSectionHeader(
                  title: 'Candidates',
                  subtitle: _total == 0 ? null : '$_total matching',
                ),
                const SizedBox(height: 8),
                if (_error != null) AppErrorPanel(message: _error!, onRetry: _reload),
                if (_items.isEmpty && !_loading && _error == null)
                  AppEmptyState(
                    icon: Icons.person_search_rounded,
                    message: _filter.q.isEmpty && _filter.statuses.isEmpty
                        ? 'No NP candidates yet.${canCreate ? ' Tap "New candidate" to start one.' : ''}'
                        : 'No candidates match this filter.',
                  ),
                for (final c in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CandidateTile(
                      c: c,
                      onTap: () async {
                        await context.push('/np/candidates/${c.id}');
                        _reload();
                      },
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.card, required this.value, required this.selected, required this.onTap});
  final NpDashboardCard card;
  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? card.color.withOpacity(0.1) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: selected ? card.color.withOpacity(0.5) : AppColors.hairline, width: selected ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(card.icon, size: 16, color: card.color),
              const Spacer(),
              Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: card.color, height: 1)),
            ]),
            Text(card.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          ]),
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.c, required this.onTap});
  final NpCandidateSummary c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = npStatusColor(c.status);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              alignment: Alignment.center,
              child: Text(
                c.fullName.isEmpty ? '?' : c.fullName.trim()[0].toUpperCase(),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.fullName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('${c.candidateCode} · ${c.mobileNumber}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                if (c.orgLine.isNotEmpty)
                  Text(c.orgLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  NpStatusPill(status: c.status, label: c.statusLabel),
                  if (c.npId != null) StatusPill(label: 'NP ${c.npId}', color: AppColors.primary, icon: Icons.badge_rounded),
                  if (c.esafId != null) StatusPill(label: 'ESAF ${c.esafId}', color: AppColors.info),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}
