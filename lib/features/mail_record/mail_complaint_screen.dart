import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mail_models.dart';
import 'mail_repository.dart';
import 'mail_status_ui.dart';

/// One complaint's detail + status workflow + history. There is no
/// `GET /complaints/{id}` endpoint (the web lists complaints and works
/// against the page), so this screen lists and finds [complaintId] within
/// it, same source of truth as [MailListScreen]'s complaints tab.
///
/// Workflow: the web offers every other status as a manual transition from
/// a "Change status…" dropdown rather than enforcing a strict linear state
/// machine — PENDING/IN_PROGRESS/RESOLVED/ESCALATED/REJECTED are all
/// reachable from any current status (gated by `ADMIN_MAIL_COMPLAINT_MANAGE`).
/// Moving to RESOLVED or REJECTED prompts for an optional note, mirroring
/// the web's `promptDialog` on those two transitions; the full status
/// history (who changed what, when, with what note) is fetched on demand
/// via `GET /complaints/{id}/history` and shown below the actions.
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
      child: GlassBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(c?.subject ?? 'Complaint'),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(_changed),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : c == null
                  ? Center(child: AppErrorPanel(message: _error ?? 'Complaint not found.', onRetry: _load))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        GlassCard(
                          padding: const EdgeInsets.all(16),
                          shadow: AppShadows.soft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(c.subject,
                                        style: const TextStyle(
                                            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                                  ),
                                  StatusPill(
                                    label: mailComplaintStatusTone(c.status).label,
                                    color: mailComplaintStatusTone(c.status).color,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('${c.branchLabel} · ${c.deptName ?? 'No department'}',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                              const Divider(height: 22),
                              _kv('Date', c.date == null ? '—' : df.format(c.date!)),
                              if (c.content != null && c.content!.isNotEmpty) _kv('Details', c.content!),
                              if (c.raisedByName != null) _kv('Raised by', c.raisedByName!),
                              if (c.phone != null && c.phone!.isNotEmpty) _kv('Phone', c.phone!),
                              if (c.resolutionNote != null && c.resolutionNote!.isNotEmpty)
                                _kv('Resolution note', c.resolutionNote!),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const AppSectionHeader(title: 'Change status'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final s in MailComplaintStatus.values)
                              if (s != c.status)
                                _statusButton(s, () => _changeStatus(s)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const AppSectionHeader(title: 'History'),
                        const SizedBox(height: 10),
                        if (_history == null || _history!.isEmpty)
                          const AppEmptyState(icon: Icons.history_rounded, message: 'No status changes recorded.')
                        else
                          GlassCard(
                            padding: EdgeInsets.zero,
                            shadow: AppShadows.soft,
                            child: Column(
                              children: [
                                for (int i = 0; i < _history!.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _history![i].fromStatus == null
                                              ? _history![i].action
                                              : '${_history![i].fromStatus} → ${_history![i].toStatus}',
                                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                        ),
                                        if (_history![i].note != null && _history![i].note!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(_history![i].note!,
                                              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_history![i].byUser ?? 'system'} · ${_history![i].createdAt == null ? '—' : dfTime.format(_history![i].createdAt!)}',
                                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink))),
          ],
        ),
      );

  Widget _statusButton(String status, VoidCallback onTap) {
    final tone = mailComplaintStatusTone(status);
    return FilledButton.icon(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: tone.color,
        side: BorderSide(color: tone.color.withOpacity(0.4)),
      ),
      icon: Icon(Icons.arrow_forward_rounded, size: 16, color: tone.color),
      label: Text(tone.label),
    );
  }
}
