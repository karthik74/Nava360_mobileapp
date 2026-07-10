import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';

/// Renders one structured assistant card natively. Unknown types render
/// nothing — older app versions simply skip cards a newer backend emits.
class AssistantCardView extends StatelessWidget {
  const AssistantCardView({super.key, required this.card});

  final AssistantCard card;

  @override
  Widget build(BuildContext context) {
    // The confirmation card is interactive and renders itself.
    if (card.type == 'approval_action') {
      final actions = AssistantCardView._list(card.data['pendingActions']);
      if (actions.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in actions) ApprovalConfirmCard(action: a),
        ],
      );
    }

    final body = switch (card.type) {
      'leave_balance' => _leaveBalance(card.data),
      'attendance' => _attendance(card.data),
      'payslips' => _payslips(card.data),
      'approvals' => _approvals(card.data),
      'holidays' => _holidays(card.data),
      'assets' => _assets(card.data),
      'policy_sources' => _policySources(card.data),
      'location' => _location(card.data),
      _ => null,
    };
    if (body == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: body,
    );
  }

  // ── renderers ─────────────────────────────────────────────────────────────

  Widget _leaveBalance(Map<String, dynamic> d) {
    final rows = _list(d['balances']);
    return _card(
      icon: Icons.event_available_rounded,
      title: 'Leave balance ${d['year'] ?? ''}'.trim(),
      children: [
        for (final b in rows.take(5))
          _BalanceRow(
            label: '${b['type'] ?? b['code'] ?? ''}',
            used: (b['used'] as num?)?.toInt() ?? 0,
            allowance: (b['allowance'] as num?)?.toInt(),
            remaining: (b['remaining'] as num?)?.toInt(),
          ),
        _more(rows.length, 5),
      ],
    );
  }

  Widget _attendance(Map<String, dynamic> d) {
    final days = _list(d['days']);
    final present = days.where((x) => x['status'] == 'PRESENT').length;
    final absent = days.where((x) => x['status'] == 'ABSENT').length;
    final leave = days.where((x) => x['status'] == 'ON_LEAVE').length;
    return _card(
      icon: Icons.fingerprint_rounded,
      title: 'Attendance ${d['from'] ?? ''} → ${d['to'] ?? ''}',
      children: [
        Row(
          children: [
            _Stat(label: 'Present', value: '$present', color: AppColors.success),
            _Stat(label: 'Absent', value: '$absent', color: AppColors.danger),
            _Stat(label: 'On leave', value: '$leave', color: AppColors.info),
          ],
        ),
      ],
    );
  }

  Widget _payslips(Map<String, dynamic> d) {
    final rows = _list(d['payslips']);
    return _card(
      icon: Icons.receipt_long_rounded,
      title: 'Your payslips',
      children: [
        for (final p in rows.take(4))
          _kv('${_month(p['month'])} ${p['year'] ?? ''}',
              p['netSalary'] == null ? '—' : '₹ ${p['netSalary']}'),
        _more(rows.length, 4),
      ],
    );
  }

  Widget _approvals(Map<String, dynamic> d) {
    final leaves = _list(d['leaves']);
    final regs = _list(d['regularizations']);
    return _card(
      icon: Icons.fact_check_rounded,
      title: 'Waiting on you',
      children: [
        if (leaves.isEmpty && regs.isEmpty)
          const Text('Nothing pending — all clear!',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        for (final l in leaves.take(3))
          _kv('${l['employee'] ?? ''}',
              '${l['type'] ?? 'Leave'} · ${l['from'] ?? ''} → ${l['to'] ?? ''}'),
        _more(leaves.length, 3),
        for (final r in regs.take(3))
          _kv('${r['employee'] ?? ''}',
              'Regularization · ${r['date'] ?? ''}'),
        _more(regs.length, 3),
      ],
    );
  }

  Widget _holidays(Map<String, dynamic> d) {
    final rows = _list(d['holidays']);
    return _card(
      icon: Icons.celebration_rounded,
      title: 'Holidays',
      children: [
        for (final h in rows.take(5))
          _kv('${h['name'] ?? ''}',
              '${h['date'] ?? ''}${h['optional'] == true ? ' · optional' : ''}'),
        _more(rows.length, 5),
      ],
    );
  }

  Widget _assets(Map<String, dynamic> d) {
    final rows = _list(d['assets']);
    return _card(
      icon: Icons.devices_other_rounded,
      title: 'Your assets',
      children: [
        for (final a in rows.take(4))
          _kv('${a['asset'] ?? ''}',
              '${a['tag'] ?? ''}${a['since'] != null ? ' · since ${a['since']}' : ''}'),
        _more(rows.length, 4),
      ],
    );
  }

  /// Last-known GPS position of a direct report (null when unavailable).
  Widget? _location(Map<String, dynamic> d) {
    if (d['error'] != null || d['latitude'] == null) return null;
    final lat = (d['latitude'] as num).toDouble();
    final lng = (d['longitude'] as num).toDouble();
    final mins = (d['ageMinutes'] as num?)?.toInt() ?? -1;
    final ago = mins < 0
        ? '${d['recordedAt'] ?? ''}'
        : (mins < 60 ? '$mins min ago' : '${(mins / 60).round()} h ago');
    return _card(
      icon: Icons.location_on_rounded,
      title: 'Last known location — ${d['employee'] ?? ''}',
      children: [
        _kv('Coordinates',
            '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'),
        _kv('Captured', ago),
        if (d['accuracyMeters'] != null)
          _kv('Accuracy', '±${(d['accuracyMeters'] as num).round()} m'),
      ],
    );
  }

  Widget _policySources(Map<String, dynamic> d) {
    final rows = _list(d['sources']);
    // Dedup: several passages often come from the same policy.
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final s in rows) {
      final key = '${s['policy']}|${s['page']}';
      if (seen.add(key)) unique.add(s);
    }
    return _card(
      icon: Icons.menu_book_rounded,
      title: 'Sources',
      children: [
        for (final s in unique.take(4))
          _kv('${s['policy'] ?? ''}',
              'v${s['version'] ?? '?'}${s['page'] != null ? ', p.${s['page']}' : ''}'),
      ],
    );
  }

  // ── shared pieces ─────────────────────────────────────────────────────────

  static Widget _card({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(k,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft)),
            ),
            const SizedBox(width: 8),
            Text(v,
                style:
                    const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );

  static Widget _more(int total, int shown) => total > shown
      ? Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('+${total - shown} more',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        )
      : const SizedBox.shrink();

  static List<Map<String, dynamic>> _list(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
      : const [];

  static String _month(dynamic m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final i = (m as num?)?.toInt() ?? 0;
    return i >= 1 && i <= 12 ? names[i - 1] : '$m';
  }
}

/// The human confirmation gate for an approve/reject. The model only surfaced
/// this card; the write happens on the user's tap via a plain REST endpoint
/// that re-checks authority. Once acted on, the card locks to its outcome.
class ApprovalConfirmCard extends ConsumerStatefulWidget {
  const ApprovalConfirmCard({super.key, required this.action});

  final Map<String, dynamic> action;

  @override
  ConsumerState<ApprovalConfirmCard> createState() => _ApprovalConfirmCardState();
}

class _ApprovalConfirmCardState extends ConsumerState<ApprovalConfirmCard> {
  bool _busy = false;
  String? _outcome;

  Future<void> _act(bool approve) async {
    if (_busy || _outcome != null) return;
    final employee = '${widget.action['employee'] ?? 'Employee'}';
    final summary = '${widget.action['summary'] ?? ''}';
    final label = approve ? 'Approve' : 'Reject';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label this request?'),
        content: Text('$employee — $summary'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: approve ? AppColors.success : AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final message = await ref.read(assistantRepositoryProvider).executeApproval(
            kind: '${widget.action['kind']}',
            id: (widget.action['id'] as num).toInt(),
            approve: approve,
          );
      if (!mounted) return;
      setState(() => _outcome = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final reason = a['reason'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text('Confirm action',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 6),
          Text('${a['employee'] ?? ''}',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
          Text('${a['summary'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (reason != null && reason.isNotEmpty)
            Text('“$reason”',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: AppColors.inkSoft)),
          const SizedBox(height: 10),
          if (_outcome != null)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 15, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_outcome!,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success)),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _act(false),
                    icon: const Icon(Icons.close_rounded,
                        size: 15, color: AppColors.danger),
                    label: const Text('Reject',
                        style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _act(true),
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text('Approve', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.used,
    this.allowance,
    this.remaining,
  });

  final String label;
  final int used;
  final int? allowance;
  final int? remaining;

  @override
  Widget build(BuildContext context) {
    final total = allowance ?? (remaining == null ? null : used + remaining!);
    final fraction =
        total == null || total <= 0 ? null : (used / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft)),
              ),
              Text(
                remaining != null
                    ? '$remaining left'
                    : '$used used',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 1 - fraction,
                minHeight: 5,
                backgroundColor: AppColors.hairline,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
        ],
      ),
    );
  }
}
