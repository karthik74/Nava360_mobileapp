// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — pipeline hero + stage filter chips + scoped candidate list.
//  Route: /np. Mirrors the web `/np` page: tiles filter the list by status,
//  search by name/code/mobile, "New candidate" for NP_CANDIDATE_CREATE.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pro_ui.dart';
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
      builder: (_) => NpSheetFrame(
        title: 'Filter by status',
        subtitle: 'Show candidates at one workflow status',
        child: SafeArea(
          top: false,
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 6, 8, 12), children: [
            _StatusOption(
              leading: const ProIconWell(icon: Icons.clear_all_rounded),
              label: 'All statuses',
              selected: _filter.statuses.isEmpty,
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final s in kNpStatuses)
              _StatusOption(
                leading: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: npStatusColor(s), shape: BoxShape.circle),
                    ),
                  ),
                ),
                label: npStatusLabel(s),
                selected: _filter.statuses.length == 1 && _filter.statuses.first == s,
                onTap: () => Navigator.pop(context, s),
              ),
          ]),
        ),
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
    final d = dash.asData?.value;
    final cardIndex = kNpDashboardCards.indexWhere((c) => c.key == _selectedCard);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NP onboarding'),
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
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // The stage chips scroll sideways — only the page scroll pages the list.
          if (n.metrics.axis == Axis.vertical && n.metrics.pixels > n.metrics.maxScrollExtent - 300) _loadMore();
          return false;
        },
        child: ProPage(
          onRefresh: _reload,
          padding: EdgeInsets.fromLTRB(16, 16, 16, canCreate ? 96 : 24),
          hero: ProHero(
            title: 'Prathinidhi pipeline',
            subtitle: 'Candidates you can see, by workflow stage',
            overlap: Row(children: [
              Expanded(
                child: ProSearchField(
                  raised: true,
                  controller: _search,
                  onChanged: _onSearchChanged,
                  hint: 'Name, code or mobile',
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(active: _filter.statuses.isNotEmpty, onTap: _pickStatus),
            ]),
            children: [
              if (d != null) _PipelineSummary(d: d),
              if (dash.isLoading && d == null)
                const SizedBox(
                  height: 56,
                  child: Center(
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  ),
                ),
            ],
          ),
          children: [
            // ── stage filter (dashboard cards) ──
            ProChipBar(
              labels: [for (final c in kNpDashboardCards) c.label],
              counts: d == null ? null : [for (final c in kNpDashboardCards) d.valueOf(c.key)],
              selected: cardIndex,
              onSelected: (i) => _selectCard(kNpDashboardCards[i]),
              bleed: 0,
            ),
            if (dash.hasError && d == null) AppErrorPanel(message: '${dash.error}', onRetry: _reload),
            if (_filter.statuses.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Showing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
                for (final s in _filter.statuses) NpStatusPill(status: s),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedCard = 'total';
                      _filter = _filter.copyWith(statuses: const []);
                    });
                    _reload();
                  },
                  icon: const Icon(Icons.close_rounded, size: 15),
                  label: const Text('Clear'),
                ),
              ]),
            ProSectionHeader(
              title: 'Candidates',
              small: true,
              trailing: _total == 0
                  ? null
                  : Text('$_total matching',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      )),
            ),
            if (_error != null) AppErrorPanel(message: _error!, onRetry: _reload),
            if (_items.isEmpty && !_loading && _error == null)
              ProEmpty(
                icon: Icons.person_search_rounded,
                title: 'Nothing to show',
                message: _filter.q.isEmpty && _filter.statuses.isEmpty
                    ? 'No NP candidates yet.${canCreate ? ' Tap "New candidate" to start one.' : ''}'
                    : 'No candidates match this filter.',
              ),
            if (_items.isNotEmpty)
              ProListGroup(
                dividerIndent: 66,
                children: [
                  for (final c in _items)
                    _CandidateRow(
                      c: c,
                      query: _filter.q,
                      onTap: () async {
                        await context.push('/np/candidates/${c.id}');
                        _reload();
                      },
                    ),
                ],
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
          ],
        ),
      ),
    );
  }
}

/// Hero summary: total in view, the pipeline split by phase and the
/// rejected / sent-back counts — all from the dashboard counts.
class _PipelineSummary extends StatelessWidget {
  const _PipelineSummary({required this.d});
  final NpDashboard d;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.primary;
    final phases = <(String, int, Color)>[
      ('Identification', d.draft + d.identificationInProgress, Color.lerp(p, Colors.white, 0.55)!),
      ('Verification', d.cbPending + d.bgvPending + d.dmPending, Color.lerp(p, Colors.white, 0.32)!),
      ('Agreement & OPS', d.agreementPending + d.opsPending, Color.lerp(p, Colors.white, 0.14)!),
      ('Activation', d.activationPending + d.esafPending, p),
      ('Active NP', d.activeNp, AppColors.live),
    ];
    final any = phases.any((ph) => ph.$2 > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${d.total}',
            style: const TextStyle(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: 3),
              child: Text('candidates in view', style: TextStyle(fontSize: 13, color: Colors.white70)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (any)
          ProStackBar(parts: [for (final ph in phases) MapEntry(ph.$2.toDouble(), ph.$3)])
        else
          Container(
            height: 8,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (final ph in phases)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: ph.$3, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(ph.$1, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(width: 4),
              Text('${ph.$2}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
            ]),
        ]),
        if (d.rejected > 0 || d.sentBack > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.undo_rounded, size: 14, color: Colors.white60),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${d.rejected} rejected · ${d.sentBack} sent back for correction',
                style: const TextStyle(fontSize: 12.5, color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ]),
        ],
      ],
    );
  }
}

/// 50px white square beside the raised search: opens the status filter.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Filter by status',
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), boxShadow: AppShadows.lifted),
        child: Material(
          color: active ? AppColors.ink : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: active ? AppColors.ink : AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 50,
              height: 50,
              child: Stack(alignment: Alignment.center, children: [
                Icon(Icons.filter_list_rounded, size: 21, color: active ? Colors.white : AppColors.inkSoft),
                if (active)
                  Positioned(
                    top: 11,
                    right: 11,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.live,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ink, width: 1.5),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({required this.leading, required this.label, required this.selected, required this.onTap});
  final Widget leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: selected,
      selectedTileColor: AppColors.surfaceAlt,
      leading: leading,
      title: Text(label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: AppColors.ink,
          )),
      trailing: selected ? Icon(Icons.check_rounded, size: 20, color: AppColors.primary) : null,
      onTap: onTap,
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.c, required this.query, required this.onTap});
  final NpCandidateSummary c;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProAvatar(name: c.fullName.isEmpty ? '?' : c.fullName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _highlighted(c.fullName, query),
                Text(
                  '${c.candidateCode} · ${c.mobileNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                if (c.orgLine.isNotEmpty)
                  Text(c.orgLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.muted)),
                const SizedBox(height: 7),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  NpStatusPill(status: c.status, label: c.statusLabel),
                  if (c.npId != null) ProPill('NP ${c.npId}', color: AppColors.primary),
                  if (c.esafId != null) ProPill.info('ESAF ${c.esafId}'),
                ]),
              ]),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFB3C0C3)),
            ),
          ]),
        ),
      ),
    );
  }

  /// Name with the search text (if it appears in the name) highlighted.
  static Widget _highlighted(String name, String query) {
    const base = TextStyle(fontSize: 15, height: 1.33, fontWeight: FontWeight.w500, letterSpacing: -0.15, color: AppColors.ink);
    final q = query.trim().toLowerCase();
    final at = q.isEmpty ? -1 : name.toLowerCase().indexOf(q);
    if (at < 0) return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: name.substring(0, at)),
        TextSpan(
          text: name.substring(at, at + q.length),
          style: const TextStyle(backgroundColor: Color(0xFFE6F3C9), fontWeight: FontWeight.w600),
        ),
        TextSpan(text: name.substring(at + q.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}
