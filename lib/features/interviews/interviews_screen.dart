import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'interview_models.dart';
import 'interview_repository.dart';

const _amber = Color(0xFFF2B347);
const _red = Color(0xFFE5484D);

/// Decided bucket used by the hero filters (presentation only).
bool _isSelected(Interview i) => !i.isPending && i.statusTone.color == AppColors.success;
bool _isRejected(Interview i) => !i.isPending && i.statusTone.color == AppColors.danger;

String _when(Interview i) =>
    i.interviewAt == null ? '' : DateFormat('EEE, d MMM yyyy · h:mm a').format(i.interviewAt!.toLocal());

String _roleLine(Interview item) => <String>[
      if (item.designation != null && item.designation!.isNotEmpty) item.designation!,
      if (item.department != null && item.department!.isNotEmpty) item.department!,
    ].join(' · ');

ProPill _pill(StatusTone tone) => ProPill(tone.label, color: tone.color);

/// "My interviews" — candidates the signed-in user is assigned to interview.
/// Reachable only by users with the INTERVIEW_VIEW permission (gated at the
/// entry point in the profile screen).
class InterviewsScreen extends ConsumerStatefulWidget {
  const InterviewsScreen({super.key});

  @override
  ConsumerState<InterviewsScreen> createState() => _InterviewsScreenState();
}

class _InterviewsScreenState extends ConsumerState<InterviewsScreen> {
  /// -1 = all, 0 = awaiting, 1 = selected, 2 = rejected.
  int _f = -1;

  void _toggle(int i) => setState(() => _f = _f == i ? -1 : i);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myInterviewsProvider);
    final items = async.valueOrNull;
    final all = items ?? const <Interview>[];
    final pending = all.where((i) => i.isPending).toList();
    final decided = all.where((i) => !i.isPending).toList();
    final selected = all.where(_isSelected).length;
    final rejected = all.where(_isRejected).length;

    final shownPending = _f == -1 || _f == 0 ? pending : const <Interview>[];
    final shownDecided = switch (_f) {
      -1 => decided,
      1 => decided.where(_isSelected).toList(),
      2 => decided.where(_isRejected).toList(),
      _ => const <Interview>[],
    };

    final children = <Widget>[
      ...async.when<List<Widget>>(
        loading: () => const [AppLoadingBlock(height: 150), AppLoadingBlock(height: 150)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(myInterviewsProvider),
          ),
        ],
        data: (items) {
          if (items.isEmpty) {
            return const [
              ProEmpty(
                icon: Icons.event_note_outlined,
                title: 'No interviews yet',
                message: 'No interviews assigned to you yet.',
              ),
            ];
          }
          return [
            if (shownPending.isNotEmpty) ...[
              ProSectionHeader(
                title: 'Awaiting your decision · ${shownPending.length}',
                small: true,
              ),
              const ProSwipeHint(text: 'Swipe right to select, left to reject'),
              for (final i in shownPending) _InterviewCard(key: ValueKey('p${i.id}'), item: i),
            ],
            if (shownDecided.isNotEmpty) ...[
              ProSectionHeader(title: 'Decided · ${shownDecided.length}', small: true),
              ProListGroup(
                children: [
                  for (final i in shownDecided)
                    ProListRow(
                      leading: ProAvatar(name: i.fullName, size: 40),
                      title: i.fullName,
                      subtitle: <String>[
                        if (_roleLine(i).isNotEmpty) _roleLine(i),
                        if (i.requisitionTitle != null && i.requisitionTitle!.isNotEmpty)
                          i.requisitionTitle!,
                      ].join(' · '),
                      meta: <String>[
                        if (i.interviewAt != null) _when(i),
                        if (i.phone != null && i.phone!.isNotEmpty) i.phone!,
                      ].join(' · '),
                      pill: _pill(i.statusTone),
                    ),
                ],
              ),
            ],
            if (shownPending.isEmpty && shownDecided.isEmpty)
              ProEmpty(
                icon: Icons.event_note_outlined,
                title: 'Nothing here',
                message: 'No candidates in this view.',
                action: OutlinedButton(
                  onPressed: () => setState(() => _f = -1),
                  child: const Text('Show all'),
                ),
              ),
          ];
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Interviews')),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myInterviewsProvider),
        hero: ProHero(
          title: 'My interviews',
          subtitle: 'Candidates you are assigned to interview',
          children: [
            if (items != null)
              ProLiveLine(
                text: pending.isEmpty
                    ? 'All caught up · no decisions pending'
                    : '${pending.length} ${pending.length == 1 ? 'candidate' : 'candidates'} awaiting your decision',
                color: pending.isEmpty ? AppColors.live : _amber,
              ),
            ProHeroStats(stats: [
              ProStat(
                label: 'Awaiting',
                value: items == null ? '—' : '${pending.length}',
                dot: _amber,
                selected: _f == 0,
                onTap: items == null ? null : () => _toggle(0),
              ),
              ProStat(
                label: 'Selected',
                value: items == null ? '—' : '$selected',
                dot: AppColors.live,
                selected: _f == 1,
                onTap: items == null ? null : () => _toggle(1),
              ),
              ProStat(
                label: 'Rejected',
                value: items == null ? '—' : '$rejected',
                dot: _red,
                selected: _f == 2,
                onTap: items == null ? null : () => _toggle(2),
              ),
            ]),
          ],
        ),
        children: children,
      ),
    );
  }
}

class _InterviewCard extends ConsumerStatefulWidget {
  const _InterviewCard({super.key, required this.item});
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
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
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
                    Row(
                      children: [
                        ProIconWell(
                          icon: isSelect ? Icons.check_rounded : Icons.close_rounded,
                          color: isSelect ? AppColors.success : AppColors.danger,
                          size: 44,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isSelect ? 'Select candidate?' : 'Reject candidate?',
                                style: const TextStyle(
                                  fontSize: 19,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.35,
                                  color: AppColors.ink,
                                ),
                              ),
                              Text(
                                isSelect
                                    ? 'Mark ${widget.item.fullName} as selected.'
                                    : 'Mark ${widget.item.fullName} as rejected.',
                                style: const TextStyle(
                                    fontSize: 13.5, height: 1.4, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ProField(
                      label: 'Feedback (optional)',
                      child: TextField(
                        controller: controller,
                        minLines: 3,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [TitleCaseTextFormatter()],
                        decoration: const InputDecoration(
                          hintText: 'What stood out in the interview?',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ProBottomBar(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: isSelect
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor: AppColors.dangerTint,
                            foregroundColor: AppColors.danger,
                          ),
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: Text(isSelect ? 'Select' : 'Reject'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final meta = _roleLine(item);

    final card = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProAvatar(name: item.fullName, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _pill(item.statusTone),
            ],
          ),
          if ((item.requisitionTitle?.isNotEmpty ?? false) ||
              item.interviewAt != null ||
              (item.phone?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                children: [
                  if (item.requisitionTitle != null && item.requisitionTitle!.isNotEmpty)
                    _MetaRow(icon: Icons.work_outline_rounded, text: item.requisitionTitle!),
                  if (item.interviewAt != null)
                    _MetaRow(icon: Icons.event_outlined, text: _when(item)),
                  if (item.phone != null && item.phone!.isNotEmpty)
                    _MetaRow(icon: Icons.call_outlined, text: item.phone!),
                ],
              ),
            ),
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
                    child: FilledButton.icon(
                      onPressed: () => _decide('REJECTED'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.dangerTint,
                        foregroundColor: AppColors.danger,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _decide('SELECTED'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Select'),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );

    if (!item.isPending || _busy) return card;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: ProSwipeDecision(
        approveLabel: 'Select',
        onApprove: () => _decide('SELECTED'),
        onReject: () => _decide('REJECTED'),
        child: card,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
