import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'task_models.dart';

/// Brand colour for each task status.
Color statusColor(String status) {
  switch (status.toUpperCase()) {
    case TaskStatuses.done:
      return AppColors.success;
    case TaskStatuses.inProgress:
      return AppColors.warning;
    case TaskStatuses.inReview:
      return AppColors.accent;
    case TaskStatuses.rejected:
      return AppColors.danger;
    case TaskStatuses.cancelled:
      return AppColors.muted;
    case TaskStatuses.todo:
    default:
      return AppColors.info;
  }
}

/// "IN_REVIEW" → "In review".
String humanizeEnum(String raw) {
  final cleaned = raw.trim().replaceAll('_', ' ').toLowerCase();
  if (cleaned.isEmpty) return raw;
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

String statusLabel(String status) => humanizeEnum(status);

Color priorityColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'URGENT':
      return AppColors.pink;
    case 'HIGH':
      return AppColors.danger;
    case 'MEDIUM':
      return AppColors.warning;
    case 'LOW':
      return AppColors.success;
    default:
      return AppColors.info;
  }
}

/// Formats a backend `LocalTime` string ("HH:mm[:ss]") as "h:mm a".
String? formatDueTime(String? t) {
  if (t == null || t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return t;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return t;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
}

// ─────────────────────────────── Pro tones ─────────────────────────────────

const _neutralInk = Color(0xFF43585D);
const _violetTint = Color(0xFFF0EBF7);

/// Pro pill colours `(ink, tint)` for a task status: to do neutral, in
/// progress brand, in review violet, done green, rejected red.
(Color, Color) taskStatusTones(String status) {
  switch (status.toUpperCase()) {
    case TaskStatuses.done:
      return (AppColors.success, AppColors.successTint);
    case TaskStatuses.inProgress:
      return (AppColors.primary, AppColors.primary.withValues(alpha: 0.1));
    case TaskStatuses.inReview:
      return (AppColors.pink, _violetTint);
    case TaskStatuses.rejected:
      return (AppColors.danger, AppColors.dangerTint);
    case TaskStatuses.cancelled:
    case TaskStatuses.todo:
    default:
      return (_neutralInk, AppColors.neutralTint);
  }
}

/// Dot colour for a status (timelines, avatar dots, stack bars).
Color taskStatusDot(String status) {
  switch (status.toUpperCase()) {
    case TaskStatuses.done:
      return AppColors.live;
    case TaskStatuses.inProgress:
      return AppColors.primary;
    case TaskStatuses.inReview:
      return const Color(0xFF8A6BC4);
    case TaskStatuses.rejected:
      return AppColors.danger;
    default:
      return const Color(0xFFB3C0C3);
  }
}

/// Icon for a status (list icon wells, hero identity).
IconData taskStatusIcon(String status) {
  switch (status.toUpperCase()) {
    case TaskStatuses.done:
      return Icons.check_circle_rounded;
    case TaskStatuses.inProgress:
      return Icons.timelapse_rounded;
    case TaskStatuses.inReview:
      return Icons.rate_review_outlined;
    case TaskStatuses.rejected:
      return Icons.cancel_outlined;
    case TaskStatuses.cancelled:
      return Icons.block_rounded;
    default:
      return Icons.radio_button_unchecked_rounded;
  }
}

/// Status pill in the Pro style.
ProPill taskStatusProPill(String status) {
  final (ink, tint) = taskStatusTones(status);
  return ProPill(statusLabel(status), color: ink, background: tint);
}

/// Priority pill in the Pro style: low info, medium neutral, high amber,
/// urgent red.
ProPill taskPriorityProPill(String priority) {
  final label = humanizeEnum(priority);
  switch (priority.toUpperCase()) {
    case 'URGENT':
      return ProPill.bad(label);
    case 'HIGH':
      return ProPill.warn(label);
    case 'LOW':
      return ProPill.info(label);
    case 'MEDIUM':
    default:
      return ProPill.neutral(label);
  }
}

/// Small dot colour for a priority (chips, meta lines).
Color taskPriorityDot(String priority) {
  switch (priority.toUpperCase()) {
    case 'URGENT':
      return AppColors.danger;
    case 'HIGH':
      return const Color(0xFFE8A12C);
    case 'LOW':
      return AppColors.info;
    case 'MEDIUM':
    default:
      return AppColors.faint;
  }
}

/// Hero tag tone for a status on a deep surface.
ProTagTone taskStatusTagTone(String status) {
  switch (status.toUpperCase()) {
    case TaskStatuses.done:
      return ProTagTone.ok;
    case TaskStatuses.rejected:
      return ProTagTone.bad;
    case TaskStatuses.inProgress:
    case TaskStatuses.inReview:
      return ProTagTone.warn;
    default:
      return ProTagTone.neutral;
  }
}

/// Pill rendering a task status with its brand colour.
class TaskStatusPill extends StatelessWidget {
  const TaskStatusPill({super.key, required this.status, this.dense = true});
  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) => taskStatusProPill(status);
}

// ─────────────────────────────── Shared widgets ────────────────────────────

/// The Pro 50px search field, with the title-case formatter the task screens
/// have always applied to what is typed.
class TaskSearchField extends StatelessWidget {
  const TaskSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hint,
    this.onClear,
    this.raised = false,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final VoidCallback? onClear;
  final bool raised;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(
        color: raised ? AppColors.hairline : const Color(0xFFDBE3E5),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: raised ? AppShadows.lifted : null,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, __) => TextField(
          controller: controller,
          onChanged: onChanged,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: v.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      controller.clear();
                      if (onClear != null) {
                        onClear!();
                      } else {
                        onChanged('');
                      }
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// A task row for a [ProListGroup]: same rhythm as [ProListRow], plus a footer
/// line of pills / due date and an optional progress bar.
class TaskListRow extends StatelessWidget {
  const TaskListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.footer = const [],
    this.progress,
    this.progressColor,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> footer;

  /// 0–100; draws a thin bar under the footer when set.
  final int? progress;
  final Color? progressColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.33,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    if (footer.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: footer,
                      ),
                    ],
                    if (progress != null) ...[
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: ProBar(
                              value: progress!.clamp(0, 100) / 100,
                              color: progressColor,
                              height: 4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${progress!.clamp(0, 100)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: progressColor ?? AppColors.primary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: Color(0xFFB3C0C3)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Due-date label with an icon; red when overdue.
class TaskDueLabel extends StatelessWidget {
  const TaskDueLabel({super.key, required this.text, this.overdue = false});
  final String text;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final color = overdue ? AppColors.danger : AppColors.inkSoft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          overdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Drag handle + title (+ subtitle) for the task bottom sheets.
class TaskSheetHeader extends StatelessWidget {
  const TaskSheetHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFC6D3D6),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.35,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle!, style: AppText.caption),
            ),
          ),
      ],
    );
  }
}

/// Shape shared by the task bottom sheets.
const kTaskSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);
