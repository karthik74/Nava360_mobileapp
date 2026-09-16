import 'package:flutter/material.dart';

import 'theme.dart';

/// One live step of a request's configurable approval chain — mirrors the
/// backend `ApprovalWorkflowDtos.StepResponse` returned by
/// `GET /api/leaves/{id}/approval-steps` and
/// `GET /api/regularizations/{id}/approval-steps`.
///
/// An EMPTY step list means no custom chain is configured for that record —
/// the default direct-manager flow applies and the chain UI should hide.
class ApprovalStep {
  final int levelOrder;
  final String levelName;
  final int? approverEmployeeId;
  final String? approverEmployeeName;

  /// NOT_STARTED | PENDING | APPROVED | REJECTED | SKIPPED
  final String status;
  final String? actionComment;
  final DateTime? actedAt;

  const ApprovalStep({
    required this.levelOrder,
    required this.levelName,
    this.approverEmployeeId,
    this.approverEmployeeName,
    required this.status,
    this.actionComment,
    this.actedAt,
  });

  factory ApprovalStep.fromJson(Map<String, dynamic> j) {
    return ApprovalStep(
      levelOrder: (j['levelOrder'] as num?)?.toInt() ?? 0,
      levelName: j['levelName'] as String? ?? '',
      approverEmployeeId: (j['approverEmployeeId'] as num?)?.toInt(),
      approverEmployeeName: j['approverEmployeeName'] as String?,
      status: j['status'] as String? ?? 'NOT_STARTED',
      actionComment: j['actionComment'] as String?,
      actedAt: j['actedAt'] is String
          ? DateTime.tryParse(j['actedAt'] as String)
          : null,
    );
  }

  static List<ApprovalStep> listFromJson(dynamic d) => ((d as List?) ?? const [])
      .map((e) => ApprovalStep.fromJson(e as Map<String, dynamic>))
      .toList();

  Color get color {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      case 'PENDING':
        return AppColors.warning;
      case 'SKIPPED':
        return AppColors.info;
      default: // NOT_STARTED
        return AppColors.muted;
    }
  }

  IconData get icon {
    switch (status) {
      case 'APPROVED':
        return Icons.check_circle_rounded;
      case 'REJECTED':
        return Icons.cancel_rounded;
      case 'PENDING':
        return Icons.hourglass_top_rounded;
      case 'SKIPPED':
        return Icons.skip_next_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }
}

/// Compact inline rendering of an approval chain — one chip per step
/// ("Level · Approver" tinted by status), matching the web's
/// ApprovalChainInline. Renders NOTHING for an empty list (no custom chain).
class ApprovalChainInline extends StatelessWidget {
  const ApprovalChainInline({super.key, required this.steps});

  final List<ApprovalStep> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final sorted = [...steps]..sort((a, b) => a.levelOrder.compareTo(b.levelOrder));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          if (i > 0)
            const Icon(Icons.arrow_forward_rounded,
                size: 12, color: AppColors.muted),
          _StepChip(step: sorted[i]),
        ],
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.step});

  final ApprovalStep step;

  @override
  Widget build(BuildContext context) {
    final name = step.approverEmployeeName?.trim() ?? '';
    final label = name.isEmpty ? step.levelName : '${step.levelName} · $name';
    return Tooltip(
      message: step.actionComment?.trim().isNotEmpty == true
          ? step.actionComment!.trim()
          : step.status,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: step.color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: step.color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(step.icon, size: 12, color: step.color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: step.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
