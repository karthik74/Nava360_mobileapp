import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';
import 'helpdesk_tickets_screen.dart' show helpdeskStatusChip, helpdeskPriorityChip;

class HelpdeskTicketDetailScreen extends ConsumerStatefulWidget {
  const HelpdeskTicketDetailScreen({super.key, required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<HelpdeskTicketDetailScreen> createState() => _HelpdeskTicketDetailScreenState();
}

class _HelpdeskTicketDetailScreenState extends ConsumerState<HelpdeskTicketDetailScreen> {
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
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
              decoration: const InputDecoration(hintText: 'Add a note (optional)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_actionLabels[action] ?? action)),
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(helpdeskTicketProvider(_id));
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          title: const Text('Ticket'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: AppErrorPanel(message: '$e')),
          data: (t) => _body(t),
        ),
      ),
    );
  }

  Widget _body(HdTicket t) {
    final s = t.summary;
    final df = DateFormat('d MMM yyyy, h:mm a');
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(s.ticketNumber, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              const SizedBox(height: 2),
              Text(s.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                helpdeskStatusChip(s.status),
                helpdeskPriorityChip(s.priority),
                if (s.slaBreached)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: const Text('SLA breached',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.danger)),
                  ),
              ]),
              const SizedBox(height: 12),

              // Status changer
              GlassCard(
                padding: const EdgeInsets.all(12),
                shadow: AppShadows.soft,
                child: Row(children: [
                  const Text('Status', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                  const Spacer(),
                  DropdownButton<String>(
                    value: s.status,
                    underline: const SizedBox.shrink(),
                    onChanged: _busy ? null : (v) { if (v != null) _changeStatus(v); },
                    items: [for (final st in kHelpdeskStatuses) DropdownMenuItem(value: st, child: Text(st.replaceAll('_', ' ')))],
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              if (t.currentStageName != null || t.availableActions.isNotEmpty) ...[
                GlassCard(
                  padding: const EdgeInsets.all(12),
                  shadow: AppShadows.soft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('Workflow', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                        const Spacer(),
                        if (t.currentStageName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(t.currentStageName!,
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                          ),
                      ]),
                      if (t.availableActions.where((a) => a != 'REASSIGN').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final a in t.availableActions.where((a) => a != 'REASSIGN'))
                            OutlinedButton(
                              onPressed: _busy ? null : () => _workflowAction(a),
                              child: Text(_actionLabels[a] ?? a),
                            ),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if ((t.description ?? '').isNotEmpty) ...[
                const _SectionTitle('Description'),
                Text(t.description!, style: const TextStyle(color: AppColors.inkSoft)),
                const SizedBox(height: 12),
              ],

              const _SectionTitle('Details'),
              _kv('Raised by', s.raisedByName),
              _kv('Assignee', s.assignedToName ?? 'Unassigned'),
              _kv('Branch', s.branchName),
              _kv('Department', s.department),
              _kv('Region', t.regionName),
              _kv('Reporting manager', t.reportingManagerName),
              _kv('Ticket type', t.ticketTypeName),
              _kv('Response due', t.responseDueAt == null ? null : df.format(t.responseDueAt!.toLocal())),
              _kv('Resolution due', s.resolutionDueAt == null ? null : df.format(s.resolutionDueAt!.toLocal())),
              const SizedBox(height: 12),

              if (t.formAnswers.isNotEmpty) ...[
                const _SectionTitle('Form details'),
                for (final a in t.formAnswers) _kv(a.label, a.value),
                const SizedBox(height: 12),
              ],

              const _SectionTitle('Conversation'),
              if (t.comments.isEmpty)
                const Text('No replies yet.', style: TextStyle(color: AppColors.muted))
              else
                for (final c in t.comments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassCard(
                      padding: const EdgeInsets.all(10),
                      shadow: AppShadows.soft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text(c.authorName ?? '—',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                            Text(c.createdAt == null ? '' : df.format(c.createdAt!.toLocal()),
                                style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                          ]),
                          const SizedBox(height: 4),
                          Text(c.body, style: const TextStyle(color: AppColors.inkSoft)),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),

        // Reply bar
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: AppColors.surface,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _comment,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Write a reply…', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _busy ? null : _reply,
                icon: const Icon(Icons.send_rounded, color: AppColors.primary),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(v == null || v.isEmpty ? '—' : v,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink))),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
      );
}
