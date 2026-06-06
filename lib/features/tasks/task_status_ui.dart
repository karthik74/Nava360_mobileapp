import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

/// Pill rendering a task status with its brand colour.
class TaskStatusPill extends StatelessWidget {
  const TaskStatusPill({super.key, required this.status, this.dense = true});
  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        statusLabel(status).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: dense ? 9.5 : 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
