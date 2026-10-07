import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'mail_models.dart';
import 'mail_repository.dart';
import 'mail_status_ui.dart';

/// One complaint's detail + history. Only a full-access admin sees the status actions — and only the moves the
/// server allows from the current status ([MailComplaint.allowedNext]); resolving or rejecting needs a note, which
/// the person who raised the complaint is notified with. Everyone else just follows their own complaint. There is
/// no `GET /complaints/{id}`, so this lists and finds [complaintId], same source as the complaints tab.
class MailComplaintScreen extends ConsumerStatefulWidget {
  const MailComplaintScreen({super.key, required this.complaintId});
  final int complaintId;

  @override
  ConsumerState<MailComplaintScreen> createState() => _MailComplaintScreenState();
}

class _MailComplaintScreenState extends ConsumerState<MailComplaintScreen> {
  MailComplaint? _complaint;
  List<MailComplaintLog>? _history;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(mailRepositoryProvider);
      final rows = await repo.listComplaints(size: 200);
      final match = rows.where((c) => c.id == widget.complaintId);
      final history = await repo.complaintHistory(widget.complaintId);
      if (!mounted) return;
      setState(() {
        _complaint = match.isNotEmpty ? match.first : null;
        _history = history;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    String? note;
    if (status == MailComplaintStatus.resolved || status == MailComplaintStatus.rejected) {
      note = await _promptText(
        title: 'Status note',
        label: 'Note for marking "${_complaint!.subject}" as ${mailComplaintStatusLabel(status)}',
      );
      if (note == null) return; // cancelled
      if (note.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a note — the person who raised it will see it.')));
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(mailRepositoryProvider);
      final updated = await repo.changeComplaintStatus(_complaint!.id, status, note: note?.isEmpty == true ? null : note);
      final history = await repo.complaintHistory(_complaint!.id);
      if (!mounted) return;
      setState(() {
        _complaint = updated;
        _history = history;
        _changed = true;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptText({required String title, required String label}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  bool get _canResolve {
    final user = ref.read(authUserProvider);
    return (user?.hasPermission('ADMIN_MAIL_COMPLAINT_MANAGE') ?? false) &&
        (user?.hasPermission('DATA_SCOPE_ALL') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _complaint;
    final df = DateFormat('d MMM yyyy');
    final dfTime = DateFormat('d MMM yyyy, HH:mm');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complaint'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : c == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AppErrorPanel(message: _error ?? 'Complaint not found.', onRetry: _load),
                    ),
                  )
                : _content(c, df, dfTime),
      ),
    );
  }

  Widget _content(MailComplaint c, DateFormat df, DateFormat dfTime) {
    final tone = mailComplaintStatusTone(c.status);
    final tagTone = switch (c.status) {
      MailComplaintStatus.resolved => ProTagTone.ok,
      MailComplaintStatus.rejected => ProTagTone.bad,
      MailComplaintStatus.inProgress => ProTagTone.neutral,
      _ => ProTagTone.warn,
    };
    final hasNote = c.resolutionNote != null && c.resolutionNote!.isNotEmpty;
    final line = hasNote
        ? '${c.status == MailComplaintStatus.rejected ? 'Rejected' : 'Resolution'}: ${c.resolutionNote!}${c.resolvedBy == null ? '' : ' — ${c.resolvedBy}'}'
        : 'Raised${c.date == null ? '' : ' on ${df.format(c.date!)}'}${c.raisedByName == null ? '' : ' by ${c.raisedByName}'}';
    final lineColor = switch (c.status) {
      MailComplaintStatus.resolved => AppColors.live,
      MailComplaintStatus.rejected => const Color(0xFFE5484D),
      MailComplaintStatus.inProgress => const Color(0xFF9FCBD5),
      _ => const Color(0xFFF2B347),
    };
    final history = _history ?? const <MailComplaintLog>[];

    return ProPage(
      onRefresh: _load,
      hero: ProHero(
        children: [
          ProHeroIdentity(
            name: c.subject,
            role: '${c.branchLabel} · ${c.department ?? 'No department'}',
            icon: mailComplaintIcon,
            tags: [
              ProHeroTag(tone.label, tone: tagTone),
              if (c.date != null) ProHeroTag(df.format(c.date!), icon: Icons.event_rounded),
            ],
          ),
          ProLiveLine(text: line, color: lineColor),
        ],
      ),
      children: [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Complaint'),
              const SizedBox(height: 4),
              ProKeyValue(rows: [
                MapEntry('Date', c.date == null ? '—' : df.format(c.date!)),
                if (c.raisedByName != null) MapEntry('Raised by', c.raisedByName!),
                if (c.raisedByCode != null) MapEntry('Employee code', c.raisedByCode!),
                MapEntry('Branch', c.branchLabel),
                if (c.areaName != null) MapEntry('Area', c.areaName!),
                if (c.divisionName != null) MapEntry('Division', c.divisionName!),
                if (c.regionName != null) MapEntry('Region', c.regionName!),
                if (c.stateName != null) MapEntry('State', c.stateName!),
                if (c.phone != null && c.phone!.isNotEmpty) MapEntry('Phone', c.phone!),
                if (hasNote)
                  MapEntry(c.status == MailComplaintStatus.rejected ? 'Rejected' : 'Resolution',
                      '${c.resolutionNote!}${c.resolvedBy == null ? '' : ' — ${c.resolvedBy}'}'),
              ]),
              if (c.content != null && c.content!.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Details',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      Text(c.content!, style: const TextStyle(fontSize: 14.5, height: 1.45, color: AppColors.ink)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(title: 'Update status'),
              const SizedBox(height: 12),
              if (!_canResolve)
                const ProNote('Only an admin can update the status. You will be notified when it changes.',
                    tone: ProNoteTone.info)
              else if (c.allowedNext.isEmpty)
                const ProNote('This complaint is closed.')
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final s in c.allowedNext) _statusButton(s, () => _changeStatus(s)),
                  ],
                ),
            ],
          ),
        ),
        ProSectionHeader(title: 'History', subtitle: history.isEmpty ? null : '${history.length} changes'),
        if (history.isEmpty)
          const ProEmpty(icon: Icons.history_rounded, title: 'No status changes recorded.')
        else
          ProListGroup(
            children: [
              for (final h in history)
                ProListRow(
                  chevron: false,
                  leading: ProIconWell(
                    icon: h.fromStatus == null ? Icons.flag_outlined : Icons.swap_horiz_rounded,
                    color: h.toStatus == null
                        ? AppColors.primary
                        : mailComplaintStatusTone(h.toStatus!).color,
                  ),
                  title: h.fromStatus == null
                      ? h.action
                      : '${mailComplaintStatusLabel(h.fromStatus!)} → ${h.toStatus == null ? '—' : mailComplaintStatusLabel(h.toStatus!)}',
                  subtitle: h.note != null && h.note!.isNotEmpty ? h.note : null,
                  meta: '${h.byUser ?? 'system'} · ${h.createdAt == null ? '—' : dfTime.format(h.createdAt!)}',
                ),
            ],
          ),
      ],
    );
  }

  Widget _statusButton(String status, VoidCallback onTap) {
    final tone = mailComplaintStatusTone(status);
    final destructive = status == MailComplaintStatus.rejected;
    if (destructive) {
      return FilledButton.icon(
        onPressed: _busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.dangerTint,
          foregroundColor: AppColors.danger,
        ),
        icon: const Icon(Icons.close_rounded, size: 17),
        label: Text(tone.label),
      );
    }
    if (status == MailComplaintStatus.resolved) {
      return FilledButton.icon(
        onPressed: _busy ? null : onTap,
        icon: const Icon(Icons.check_rounded, size: 17),
        label: Text(tone.label),
      );
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
      label: Text(tone.label),
    );
  }
}
