import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';
import 'helpdesk_tickets_screen.dart'
    show
        helpdeskStatusChip,
        helpdeskStatusLabel,
        helpdeskCategoryIcon;

class HelpdeskTicketDetailScreen extends ConsumerStatefulWidget {
  const HelpdeskTicketDetailScreen({super.key, required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<HelpdeskTicketDetailScreen> createState() => _HelpdeskTicketDetailScreenState();
}

class _HelpdeskTicketDetailScreenState extends ConsumerState<HelpdeskTicketDetailScreen>
    with SingleTickerProviderStateMixin {
  final _comment = TextEditingController();
  final _replyFocus = FocusNode();
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTab);
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    _replyFocus.dispose();
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  int get _id => widget.ticketId;

  Future<void> _reply() async {
    if (_comment.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(helpdeskRepositoryProvider).addComment(_id, _comment.text.trim());
      _comment.clear();
      ref.invalidate(helpdeskTicketProvider(_id));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    setState(() => _busy = true);
    try {
      await ref.read(helpdeskRepositoryProvider).updateStatus(_id, status);
      ref.invalidate(helpdeskTicketProvider(_id));
      ref.invalidate(helpdeskTicketsProvider('mine'));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  static const _actionLabels = {
    'APPROVE': 'Approve', 'REJECT': 'Reject', 'RETURN': 'Return', 'HOLD': 'Hold',
    'REQUEST_INFO': 'Request info', 'ESCALATE': 'Escalate', 'REASSIGN': 'Reassign',
  };

  /// Actions surfaced as hero buttons (the rest live in the Workflow card).
  static const _heroActions = {'APPROVE', 'REQUEST_INFO'};

  Future<void> _workflowAction(String action) async {
    String? note;
    if (action == 'APPROVE') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Approve'),
          content: const Text('Advance this ticket to the next stage?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_actionLabels[action] ?? action),
          content: TextField(controller: ctrl, minLines: 1, maxLines: 4,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              decoration: const InputDecoration(hintText: 'Add a note (optional)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: action == 'REJECT'
                  ? FilledButton.styleFrom(
                      backgroundColor: AppColors.dangerTint,
                      foregroundColor: AppColors.danger)
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_actionLabels[action] ?? action),
            ),
          ],
        ),
      );
      if (ok != true) return;
      note = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
    }
    setState(() => _busy = true);
    try {
      await ref.read(helpdeskRepositoryProvider).workflowAction(_id, action, note: note);
      ref.invalidate(helpdeskTicketProvider(_id));
      ref.invalidate(helpdeskTicketsProvider('assigned'));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Status picker sheet (replaces the inline dropdown; same handler).
  Future<void> _pickStatus(String current) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StatusSheet(current: current),
    );
    if (v != null) _changeStatus(v);
  }

  void _startReply() {
    _tabs.animateTo(1);
    _replyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(helpdeskTicketProvider(_id));
    return Scaffold(
      appBar: AppBar(title: const Text('Ticket')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: AppErrorPanel(message: '$e')),
        data: (t) => _body(t),
      ),
    );
  }

  Widget _body(HdTicket t) {
    final s = t.summary;
    final df = DateFormat('d MMM yyyy, h:mm a');
    final shortDf = DateFormat('d MMM, h:mm a');
    final (icon, _) = helpdeskCategoryIcon(s.category);
    final hasApprove = t.availableActions.contains('APPROVE');
    final hasInfo = t.availableActions.contains('REQUEST_INFO');
    final closed = const {'RESOLVED', 'CLOSED', 'CANCELLED'}.contains(s.status);

    final live = StringBuffer('Raised by ${s.raisedByName ?? '—'}');
    if (s.createdAt != null) live.write(' on ${shortDf.format(s.createdAt!.toLocal())}');
    if (s.responseBreached) {
      live.write(' · response overdue');
    } else if (s.resolutionBreached) {
      live.write(' · resolution overdue');
    } else if (!closed && s.resolutionDueAt != null) {
      live.write(' · resolve by ${shortDf.format(s.resolutionDueAt!.toLocal())}');
    }

    return Column(
      children: [
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: ProPage(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              onRefresh: () async => ref.invalidate(helpdeskTicketProvider(_id)),
              hero: ProHero(
                overlap: ProKpiStrip(cells: [
                  ProKpi(value: '${t.comments.length}', label: 'Replies'),
                  ProKpi(value: '${t.attachments.length}', label: 'Attachments'),
                  ProKpi(
                    value: s.escalationLevel == 0 ? 'None' : 'L${s.escalationLevel}',
                    label: 'Escalation',
                    valueColor: s.escalationLevel > 0 ? AppColors.warning : null,
                  ),
                ]),
                children: [
                  ProHeroIdentity(
                    name: s.title,
                    role: '${s.ticketNumber}${s.category != null ? ' · ${s.category}' : ''}',
                    icon: icon,
                    tags: [
                      ProHeroTag(helpdeskStatusLabel(s.status), tone: _statusTone(s.status)),
                      ProHeroTag(helpdeskStatusLabel(s.priority), tone: _priorityTone(s.priority)),
                      if (s.slaBreached) const ProHeroTag('SLA breached', tone: ProTagTone.bad),
                    ],
                  ),
                  ProLiveLine(
                    text: live.toString(),
                    color: s.slaBreached ? const Color(0xFFF2B347) : null,
                  ),
                  ProHeroActions(actions: [
                    if (hasApprove)
                      ProAction(
                        icon: Icons.check_rounded,
                        label: 'Approve',
                        primary: true,
                        onTap: _busy ? null : () => _workflowAction('APPROVE'),
                      ),
                    ProAction(
                      icon: Icons.reply_rounded,
                      label: 'Reply',
                      primary: !hasApprove,
                      onTap: _startReply,
                    ),
                    if (hasInfo)
                      ProAction(
                        icon: Icons.help_outline_rounded,
                        label: 'Request info',
                        onTap: _busy ? null : () => _workflowAction('REQUEST_INFO'),
                      ),
                    ProAction(
                      icon: Icons.sync_alt_rounded,
                      label: 'Status',
                      onTap: _busy ? null : () => _pickStatus(s.status),
                    ),
                  ]),
                ],
              ),
              children: [
                TabBar(
                  controller: _tabs,
                  tabs: [
                    const Tab(text: 'Details'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Conversation'),
                          if (t.comments.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            ProPill.neutral('${t.comments.length}'),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (_tabs.index == 0)
                  ..._details(t, df)
                else
                  ..._conversation(t, shortDf),
              ],
            ),
          ),
        ),

        // Reply bar
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      focusNode: _replyFocus,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: const [TitleCaseTextFormatter()],
                      decoration: InputDecoration(
                        hintText: 'Write a reply…',
                        isDense: true,
                        fillColor: AppColors.bg,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFFDBE3E5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFFDBE3E5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Send reply',
                    child: Material(
                      color: _busy ? AppColors.neutralTint : AppColors.primary,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _busy ? null : _reply,
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(Icons.send_rounded,
                              size: 20, color: _busy ? AppColors.faint : Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _details(HdTicket t, DateFormat df) {
    final s = t.summary;
    final cardActions =
        t.availableActions.where((a) => a != 'REASSIGN' && !_heroActions.contains(a)).toList();
    return [
      if (t.currentStageName != null || t.availableActions.isNotEmpty)
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProSectionHeader(
                title: 'Workflow',
                trailing: t.currentStageName == null
                    ? null
                    : Flexible(child: _StagePill(t.currentStageName!)),
              ),
              if (cardActions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in cardActions)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        foregroundColor: a == 'REJECT' ? AppColors.danger : null,
                        side: a == 'REJECT' ? const BorderSide(color: Color(0xFFF2C4C1)) : null,
                      ),
                      onPressed: _busy ? null : () => _workflowAction(a),
                      child: Text(_actionLabels[a] ?? a),
                    ),
                ]),
              ],
            ],
          ),
        ),

      if ((t.description ?? '').isNotEmpty)
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Description'),
              const SizedBox(height: 8),
              Text(t.description!,
                  style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.inkSoft)),
            ],
          ),
        ),

      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ProSectionHeader(title: 'Details'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _busy ? null : () => _pickStatus(s.status),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Text('Status',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted)),
                    const Spacer(),
                    helpdeskStatusChip(s.status),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded,
                        size: 18, color: _busy ? AppColors.faint : AppColors.muted),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.hairlineSoft),
            ProKeyValue(rows: [
              _kv('Raised by', s.raisedByName),
              _kv('Assignee', s.assignedToName ?? 'Unassigned'),
              _kv(Branding.current.term('branch'), s.branchName),
              _kv(Branding.current.term('department'), s.department),
              _kv(Branding.current.term('region'), t.regionName),
              _kv('Reporting manager', t.reportingManagerName),
              _kv('Ticket type', t.ticketTypeName),
              _kv('Response due', t.responseDueAt == null ? null : df.format(t.responseDueAt!.toLocal())),
              _kv('Resolution due', s.resolutionDueAt == null ? null : df.format(s.resolutionDueAt!.toLocal())),
            ]),
          ],
        ),
      ),

      if (t.formAnswers.isNotEmpty)
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Form details'),
              const SizedBox(height: 6),
              ProKeyValue(rows: [for (final a in t.formAnswers) _kv(a.label, a.value)]),
            ],
          ),
        ),
    ];
  }

  List<Widget> _conversation(HdTicket t, DateFormat df) {
    final s = t.summary;
    return [
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.neutralTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Ticket raised by ${s.raisedByName ?? '—'}'
            '${s.createdAt != null ? ' · ${df.format(s.createdAt!.toLocal())}' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
      if (t.comments.isEmpty)
        const ProEmpty(
          icon: Icons.forum_outlined,
          title: 'No replies yet.',
          message: 'Start the conversation below.',
        )
      else
        for (final c in t.comments) _CommentBubble(c: c, df: df),
    ];
  }

  static ProTagTone _statusTone(String status) => switch (status) {
        'RESOLVED' => ProTagTone.ok,
        'ON_HOLD' => ProTagTone.warn,
        'CANCELLED' => ProTagTone.bad,
        _ => ProTagTone.neutral,
      };

  static ProTagTone _priorityTone(String priority) => switch (priority) {
        'CRITICAL' => ProTagTone.bad,
        'HIGH' => ProTagTone.warn,
        _ => ProTagTone.neutral,
      };

  MapEntry<String, String> _kv(String k, String? v) =>
      MapEntry(k, v == null || v.isEmpty ? '—' : v);
}

/// One reply in the ticket thread (white hairline bubble, author avatar).
class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.c, required this.df});
  final HdComment c;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final author = c.authorName ?? '—';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProAvatar(name: author, size: 32),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: c.internalNote ? const Color(0xFFFFFAF0) : AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(
                  color: c.internalNote ? const Color(0xFFF3DFB8) : AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    ),
                    if (c.internalNote) ...[
                      const SizedBox(width: 6),
                      ProPill.warn('Internal note'),
                    ],
                    const Spacer(),
                    if (c.createdAt != null)
                      Text(df.format(c.createdAt!.toLocal()),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.faint,
                            fontFeatures: [FontFeature.tabularFigures()],
                          )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(c.body,
                    style: const TextStyle(fontSize: 14.5, height: 1.45, color: AppColors.inkSoft)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Workflow stage pill (ellipsizes long stage names).
class _StagePill extends StatelessWidget {
  const _StagePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// White status picker sheet.
class _StatusSheet extends StatelessWidget {
  const _StatusSheet({required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFC6D3D6),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('Status',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.35,
                    color: AppColors.ink)),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: ProListGroup(
                dividerIndent: 48,
                children: [
                  for (final st in kHelpdeskStatuses)
                    ProListRow(
                      dense: true,
                      chevron: false,
                      leading: Icon(
                        st == current
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 22,
                        color: st == current ? AppColors.primary : const Color(0xFFB9C7CA),
                      ),
                      title: helpdeskStatusLabel(st),
                      trailing: helpdeskStatusChip(st),
                      onTap: () => Navigator.of(context).pop(st),
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
