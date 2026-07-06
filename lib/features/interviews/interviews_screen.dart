import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'interview_models.dart';
import 'interview_repository.dart';

/// "My interviews" — candidates the signed-in user is assigned to interview.
/// Reachable only by users with the INTERVIEW_VIEW permission (gated at the
/// entry point in the profile screen).
class InterviewsScreen extends ConsumerWidget {
  const InterviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myInterviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My interviews')),
      body: GlassBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(myInterviewsProvider),
            child: async.when(
              loading: () => ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              ),
              error: (e, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 8),
                  AppErrorPanel(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(myInterviewsProvider),
                  ),
                ],
              ),
              data: (items) {
                if (items.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: const [
                      SizedBox(height: 60),
                      AppEmptyState(
                        icon: Icons.event_note_outlined,
                        message: 'No interviews assigned to you yet.',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _InterviewCard(item: items[i]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InterviewCard extends ConsumerStatefulWidget {
  const _InterviewCard({required this.item});
  final Interview item;

  @override
  ConsumerState<_InterviewCard> createState() => _InterviewCardState();
}

class _InterviewCardState extends ConsumerState<_InterviewCard> {
  bool _busy = false;

  Future<void> _decide(String outcome) async {
    final item = widget.item;
    final note = await _askNote(context, outcome);
    if (note == null) return; // cancelled
    setState(() => _busy = true);
    try {
      await ref.read(interviewRepositoryProvider).submitDecision(
            candidateId: item.id,
            outcome: outcome,
            note: note,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            outcome == 'SELECTED'
                ? '${item.fullName} marked selected.'
                : '${item.fullName} marked rejected.',
          ),
        ));
      ref.invalidate(myInterviewsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// Returns the entered note (possibly empty) or null if cancelled.
  Future<String?> _askNote(BuildContext context, String outcome) {
    final controller = TextEditingController();
    final isSelect = outcome == 'SELECTED';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSelect ? 'Select candidate?' : 'Reject candidate?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isSelect
                  ? 'Mark ${widget.item.fullName} as selected.'
                  : 'Mark ${widget.item.fullName} as rejected.',
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: 'Feedback (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isSelect ? AppColors.success : AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(isSelect ? 'Select' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tone = item.statusTone;
    final meta = <String>[
      if (item.designation != null && item.designation!.isNotEmpty)
        item.designation!,
      if (item.department != null && item.department!.isNotEmpty)
        item.department!,
    ].join(' · ');

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: item.fullName, size: 40, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fullName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          if (item.requisitionTitle != null &&
              item.requisitionTitle!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _MetaRow(
              icon: Icons.work_outline_rounded,
              text: item.requisitionTitle!,
            ),
          ],
          if (item.interviewAt != null) ...[
            const SizedBox(height: 6),
            _MetaRow(
              icon: Icons.event_outlined,
              text: DateFormat('EEE, d MMM yyyy · h:mm a')
                  .format(item.interviewAt!.toLocal()),
            ),
          ],
          if (item.phone != null && item.phone!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _MetaRow(icon: Icons.call_outlined, text: item.phone!),
          ],
          if (item.isPending) ...[
            const SizedBox(height: 14),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide('REJECTED'),
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.danger),
                      label: const Text('Reject',
                          style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _decide('SELECTED'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Select'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
