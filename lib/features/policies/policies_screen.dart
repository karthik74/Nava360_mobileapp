import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'policies_models.dart';
import 'policies_repository.dart';

final myPoliciesProvider = FutureProvider.autoDispose<List<MyPolicy>>(
  (ref) => ref.watch(policiesRepositoryProvider).myPolicies(),
);

const _amber = Color(0xFFF2B347);

class PoliciesScreen extends ConsumerStatefulWidget {
  const PoliciesScreen({super.key});

  @override
  ConsumerState<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends ConsumerState<PoliciesScreen> {
  final _q = TextEditingController();
  String _query = '';

  /// Selected category chip (0 = all).
  int _cat = 0;

  /// Hero filter: null = all, false = action needed, true = read.
  bool? _show;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static String _category(MyPolicy p) => p.category ?? 'General';

  void _resetAll() {
    _q.clear();
    setState(() {
      _query = '';
      _cat = 0;
      _show = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myPoliciesProvider);
    final policies = async.valueOrNull;
    final all = policies ?? const <MyPolicy>[];
    final total = all.length;
    final readCount = all.where((p) => p.read).length;
    final pending = total - readCount;

    final cats = <String>['All', ...{for (final p in all) _category(p)}];
    final cat = _cat < cats.length ? _cat : 0;
    final q = _query.trim().toLowerCase();
    final shown = all.where((p) {
      if (cat > 0 && _category(p) != cats[cat]) return false;
      if (_show != null && p.read != _show) return false;
      if (q.isNotEmpty &&
          !p.title.toLowerCase().contains(q) &&
          !_category(p).toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    final shownPending = shown.where((p) => !p.read).toList();
    final shownRead = shown.where((p) => p.read).toList();

    final children = <Widget>[
      ...async.when<List<Widget>>(
        loading: () => const [AppLoadingBlock(height: 200)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(myPoliciesProvider),
          ),
        ],
        data: (policies) {
          if (policies.isEmpty) {
            return const [
              ProEmpty(
                icon: Icons.description_outlined,
                title: 'No policies',
                message: 'No policies are currently assigned to you.',
              ),
            ];
          }
          return [
            if (cats.length > 2)
              ProChipBar(
                labels: cats,
                counts: [
                  for (final c in cats)
                    c == 'All' ? policies.length : policies.where((p) => _category(p) == c).length,
                ],
                selected: cat,
                onSelected: (i) => setState(() => _cat = i),
                bleed: 0,
              ),
            if (shownPending.isNotEmpty) ...[
              ProSectionHeader(title: 'Action needed · ${shownPending.length}', small: true),
              ProListGroup(children: [for (final p in shownPending) _PolicyRow(policy: p)]),
            ],
            if (shownRead.isNotEmpty) ...[
              ProSectionHeader(title: 'Read · ${shownRead.length}', small: true),
              ProListGroup(children: [for (final p in shownRead) _PolicyRow(policy: p)]),
            ],
            if (shown.isEmpty)
              ProEmpty(
                icon: Icons.search_off_rounded,
                title: 'No matching policies',
                message: 'Try another category or clear the search.',
                action: OutlinedButton(
                  onPressed: _resetAll,
                  child: const Text('Show all policies'),
                ),
              ),
          ];
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Policies')),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myPoliciesProvider),
        hero: ProHero(
          title: 'Company policies',
          subtitle: policies == null ? 'Company info' : 'Company info · $total assigned to you',
          overlap: policies == null || policies.isEmpty
              ? null
              : ProSearchField(
                  raised: true,
                  controller: _q,
                  hint: 'Search policies',
                  onChanged: (v) => setState(() => _query = v),
                ),
          children: [
            if (policies != null && total > 0) _ReadProgress(read: readCount, total: total),
            ProHeroStats(stats: [
              ProStat(
                label: 'Action needed',
                value: policies == null ? '—' : '$pending',
                sub: policies == null ? null : 'to acknowledge',
                dot: _amber,
                selected: _show == false,
                onTap: policies == null
                    ? null
                    : () => setState(() => _show = _show == false ? null : false),
              ),
              ProStat(
                label: 'Read',
                value: policies == null ? '—' : '$readCount',
                sub: policies == null ? null : 'up to date',
                dot: AppColors.live,
                selected: _show == true,
                onTap: policies == null
                    ? null
                    : () => setState(() => _show = _show == true ? null : true),
              ),
              ProStat(
                label: 'Assigned',
                value: policies == null ? '—' : '$total',
                sub: policies == null || total == 0
                    ? null
                    : '${(readCount / total * 100).round()}% read',
                dot: const Color(0xFF7FD3E3),
              ),
            ]),
          ],
        ),
        children: children,
      ),
    );
  }
}

/// "3 of 5 read" line + thin bar on the deep hero.
class _ReadProgress extends StatelessWidget {
  const _ReadProgress({required this.read, required this.total});
  final int read;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$read of $total read',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Text(
              'A new version asks again',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProBar(
          value: total == 0 ? 0 : read / total,
          color: AppColors.live,
          track: Colors.white.withValues(alpha: 0.14),
          height: 6,
        ),
      ],
    );
  }
}

class _PolicyRow extends StatelessWidget {
  const _PolicyRow({required this.policy});
  final MyPolicy policy;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final meta = [
      policy.category ?? 'General',
      if (policy.versionNumber != null) 'v${policy.versionNumber}',
      if (policy.effectiveDate != null) 'Effective ${df.format(policy.effectiveDate!)}',
    ].join(' · ');

    return ProListRow(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          ProIconWell(
            icon: Icons.picture_as_pdf_rounded,
            color: policy.read ? AppColors.primary : const Color(0xFF9A5B00),
          ),
          if (!policy.read)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: policy.title,
      titleMaxLines: 2,
      subtitle: meta,
      pill: policy.read ? ProPill.ok('Read') : ProPill.warn('Action needed'),
      onTap: () => context.push('/policies/${policy.id}'),
    );
  }
}
