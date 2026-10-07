import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';

/// Helpdesk ticket lists — My Tickets + Assigned to Me.
class HelpdeskTicketsScreen extends ConsumerStatefulWidget {
  const HelpdeskTicketsScreen({super.key});

  @override
  ConsumerState<HelpdeskTicketsScreen> createState() =>
      _HelpdeskTicketsScreenState();
}

class _HelpdeskTicketsScreenState extends ConsumerState<HelpdeskTicketsScreen> {
  static const _scopes = ['mine', 'assigned'];

  /// Status chips (first = all).
  static const _chipKeys = <String>[
    'ALL', 'OPEN', 'IN_PROGRESS', 'ON_HOLD', 'RESOLVED', 'CLOSED', 'REOPENED',
    'CANCELLED',
  ];

  /// Hero stat groups (tap to filter by the whole group).
  static const _groups = <String, Set<String>>{
    'G_OPEN': {'OPEN', 'REOPENED'},
    'G_PENDING': {'IN_PROGRESS', 'ON_HOLD'},
    'G_DONE': {'RESOLVED', 'CLOSED'},
  };
  static const _groupLabels = {
    'G_OPEN': 'Open',
    'G_PENDING': 'Pending',
    'G_DONE': 'Resolved',
  };

  final _search = TextEditingController();
  int _tab = 0;
  String _filter = 'ALL';
  String _query = '';
  bool _byPriority = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _scope => _scopes[_tab];

  bool _matchesFilter(HdTicketSummary t) {
    if (_filter == 'ALL') return true;
    final g = _groups[_filter];
    return g != null ? g.contains(t.status) : t.status == _filter;
  }

  bool _matchesQuery(HdTicketSummary t) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q) ||
        t.ticketNumber.toLowerCase().contains(q) ||
        (t.category ?? '').toLowerCase().contains(q);
  }

  String _filterLabel() =>
      _groupLabels[_filter] ??
      (_filter == 'ALL' ? 'All' : helpdeskStatusLabel(_filter));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(helpdeskTicketsProvider(_scope));
    final rows = async.valueOrNull;

    ProStat stat(String key, String label, Color dot) {
      final inGroup = (rows ?? const <HdTicketSummary>[])
          .where((t) => _groups[key]!.contains(t.status));
      final urgent = inGroup
          .where((t) => t.priority == 'HIGH' || t.priority == 'CRITICAL')
          .length;
      return ProStat(
        label: label,
        value: rows == null ? '—' : '${inGroup.length}',
        sub: rows == null ? null : '$urgent high priority',
        dot: dot,
        selected: _filter == key,
        onTap: rows == null
            ? null
            : () => setState(() => _filter = _filter == key ? 'ALL' : key),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Helpdesk')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/helpdesk/raise'),
        icon: const Icon(Icons.add),
        label: const Text('Raise'),
      ),
      body: ProPage(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        onRefresh: () async => ref.invalidate(helpdeskTicketsProvider(_scope)),
        hero: ProHero(
          title: _tab == 0 ? 'My tickets' : 'Assigned to me',
          subtitle: rows == null
              ? (_tab == 0 ? 'Raised by you' : 'Assigned to you')
              : '${_tab == 0 ? 'Raised by you' : 'Assigned to you'} · '
                  '${rows.length} ${rows.length == 1 ? 'ticket' : 'tickets'}',
          actions: [
            ProHeroIconButton(
              icon: Icons.menu_book_outlined,
              tooltip: 'Knowledge base',
              onTap: () => context.push('/helpdesk/kb'),
            ),
          ],
          overlap: ProSearchField(
            raised: true,
            controller: _search,
            hint: 'Title, ticket number or category',
            onChanged: (v) => setState(() => _query = v),
          ),
          children: [
            ProHeroSegmented(
              labels: const ['My tickets', 'Assigned'],
              selected: _tab,
              onChanged: (i) => setState(() {
                _tab = i;
                _filter = 'ALL';
              }),
            ),
            ProHeroStats(stats: [
              stat('G_OPEN', 'Open', const Color(0xFF5AA9F0)),
              stat('G_PENDING', 'Pending', const Color(0xFFF2B347)),
              stat('G_DONE', 'Resolved', AppColors.live),
            ]),
          ],
        ),
        children: async.when(
          loading: () => const [
            AppLoadingBlock(height: 72),
            AppLoadingBlock(height: 72),
            AppLoadingBlock(height: 72),
          ],
          error: (e, _) => [
            AppErrorPanel(
              message: '$e',
              onRetry: () => ref.invalidate(helpdeskTicketsProvider(_scope)),
            ),
          ],
          data: (all) => _listSection(all),
        ),
      ),
    );
  }

  List<Widget> _listSection(List<HdTicketSummary> all) {
    var shown = all.where((t) => _matchesFilter(t) && _matchesQuery(t)).toList();
    if (_byPriority) {
      final idx = {for (var i = 0; i < shown.length; i++) shown[i]: i};
      shown.sort((a, b) {
        final r = _priorityRank(a.priority).compareTo(_priorityRank(b.priority));
        return r != 0 ? r : idx[a]!.compareTo(idx[b]!);
      });
    }
    final q = _query.trim();
    return [
      ProChipBar(
        bleed: 0,
        labels: [
          for (final k in _chipKeys) k == 'ALL' ? 'All' : helpdeskStatusLabel(k),
        ],
        counts: [
          for (final k in _chipKeys)
            k == 'ALL' ? all.length : all.where((t) => t.status == k).length,
        ],
        selected: _chipKeys.indexOf(_filter),
        onSelected: (i) => setState(() => _filter = _chipKeys[i]),
      ),
      ProSectionHeader(
        title: '${_filterLabel()} · ${shown.length}',
        small: true,
        trailing: TextButton.icon(
          onPressed: () => setState(() => _byPriority = !_byPriority),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: AppColors.inkSoft,
          ),
          icon: const Icon(Icons.swap_vert_rounded, size: 17),
          label: Text(_byPriority ? 'Priority' : 'Recent first',
              style: const TextStyle(fontSize: 13)),
        ),
      ),
      if (shown.isEmpty)
        ProEmpty(
          icon: Icons.confirmation_number_outlined,
          title: q.isNotEmpty
              ? 'No tickets match “$q”.'
              : 'No tickets here yet.',
          message: q.isNotEmpty
              ? 'Search by title, ticket number or category.'
              : (_tab == 0
                  ? 'Tickets you raise show up here.'
                  : 'Tickets assigned to you show up here.'),
        )
      else
        ProListGroup(
          children: [for (final t in shown) _TicketRow(t: t)],
        ),
    ];
  }

  static int _priorityRank(String p) => switch (p) {
        'CRITICAL' => 0,
        'HIGH' => 1,
        'MEDIUM' => 2,
        _ => 3,
      };
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.t});
  final HdTicketSummary t;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = helpdeskCategoryIcon(t.category);
    final updated = t.updatedAt == null
        ? null
        : 'Updated ${DateFormat('d MMM, h:mm a').format(t.updatedAt!.toLocal())}';
    return ProListRow(
      leading: ProIconWell(icon: icon, color: color),
      title: t.title,
      subtitle: '${t.ticketNumber}${t.category != null ? ' · ${t.category}' : ''}',
      meta: [
        if (t.slaBreached) 'SLA breached',
        if (updated != null) updated,
      ].join(' · '),
      pill: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          helpdeskStatusChip(t.status),
          const SizedBox(height: 4),
          helpdeskPriorityChip(t.priority),
        ],
      ),
      onTap: () => context.push('/helpdesk/tickets/${t.id}'),
    );
  }
}

// ── Shared chips / labels (reused by the detail screen) ──

/// "IN_PROGRESS" → "In progress".
String helpdeskStatusLabel(String status) {
  final s = status.replaceAll('_', ' ').toLowerCase();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

Widget helpdeskStatusChip(String status) {
  final label = helpdeskStatusLabel(status);
  switch (status) {
    case 'OPEN':
      return ProPill.info(label);
    case 'IN_PROGRESS':
      return ProPill(label, color: AppColors.primary);
    case 'ON_HOLD':
      return ProPill.warn(label);
    case 'RESOLVED':
      return ProPill.ok(label);
    case 'CLOSED':
      return ProPill.neutral(label);
    case 'REOPENED':
      return ProPill(label, color: AppColors.pink);
    case 'CANCELLED':
      return ProPill.bad(label);
    default:
      return ProPill(label, color: AppColors.primary);
  }
}

Widget helpdeskPriorityChip(String priority) {
  final label = helpdeskStatusLabel(priority);
  switch (priority) {
    case 'CRITICAL':
      return ProPill(label,
          color: AppColors.danger, background: AppColors.dangerTint, dot: true);
    case 'HIGH':
      return ProPill(label,
          color: const Color(0xFF9A5B00),
          background: AppColors.warningTint,
          dot: true);
    case 'MEDIUM':
      return ProPill(label,
          color: AppColors.info, background: AppColors.infoTint, dot: true);
    default:
      return ProPill(label,
          color: AppColors.muted, background: AppColors.neutralTint, dot: true);
  }
}

/// Icon + tint for a ticket category (keyword match on the free-text name).
(IconData, Color) helpdeskCategoryIcon(String? category) {
  final c = (category ?? '').toLowerCase();
  bool has(String k) => c.contains(k);
  if (c.startsWith('it') || has(' it') || has('laptop') || has('access')) {
    return (Icons.laptop_mac_rounded, AppColors.primary);
  }
  if (has('payroll') || has('salary')) {
    return (Icons.payments_outlined, AppColors.success);
  }
  if (c.startsWith('hr') || has('attendance') || has('leave')) {
    return (Icons.badge_outlined, const Color(0xFF4253A8));
  }
  if (has('finance') || has('travel') || has('claim')) {
    return (Icons.account_balance_wallet_outlined, AppColors.pink);
  }
  if (has('admin') || has('facilit')) {
    return (Icons.apartment_rounded, AppColors.inkSoft);
  }
  return (Icons.confirmation_number_outlined, AppColors.primary);
}
