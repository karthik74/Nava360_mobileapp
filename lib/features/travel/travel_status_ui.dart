import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'travel_models.dart';

/// (color, label) tone for a `TravelClaimStatus`. Mirrors the web claim-status
/// chips so the two front-ends read the same.
StatusTone claimStatusTone(String status) {
  switch (status) {
    case 'DRAFT':
      return const StatusTone(AppColors.muted, 'Draft');
    case 'SUBMITTED':
      return const StatusTone(AppColors.warning, 'Submitted');
    case 'LEVEL_1_APPROVED':
      return const StatusTone(AppColors.info, 'L1 Approved');
    case 'LEVEL_2_APPROVED':
      return const StatusTone(AppColors.info, 'L2 Approved');
    case 'LEVEL_3_APPROVED':
      return const StatusTone(AppColors.info, 'L3 Approved');
    case 'APPROVED':
      return const StatusTone(AppColors.success, 'Approved');
    case 'REJECTED':
      return const StatusTone(AppColors.danger, 'Rejected');
    case 'SENT_BACK':
      return const StatusTone(AppColors.pink, 'Sent back');
    case 'SETTLED':
      return StatusTone(AppColors.primary, 'Settled');
    default:
      return StatusTone(AppColors.muted, TravelEnums.label(status));
  }
}

/// (color, label) tone for a `TravelPlanStatus`.
StatusTone planStatusTone(String status) {
  switch (status) {
    case 'ACTIVE':
      return const StatusTone(AppColors.success, 'Active');
    case 'COMPLETED':
      return const StatusTone(AppColors.info, 'Completed');
    case 'CANCELLED':
      return const StatusTone(AppColors.muted, 'Cancelled');
    default:
      return StatusTone(AppColors.muted, TravelEnums.label(status));
  }
}

/// A claim header is editable by its owner only while DRAFT or SENT_BACK.
bool claimIsEditable(String status) => status == 'DRAFT' || status == 'SENT_BACK';

/// Whether the claimant may delete their own claim in this status.
///
/// SUBMITTED is deletable so a claim sent by mistake can be withdrawn from the
/// approver's inbox; once a level has been approved the claim carries somebody
/// else's decision and only the approval path can end it. Mirrors the backend's
/// DELETABLE_STATUSES guard, which is what actually enforces this.
bool claimIsDeletable(String status) => status == 'DRAFT' || status == 'SUBMITTED';

/// Icon for a `TravelExpenseCategory`.
IconData expenseCategoryIcon(String category) {
  switch (category) {
    case 'TRAVEL_FARE':
      return Icons.flight_takeoff_rounded;
    case 'ACCOMMODATION':
      return Icons.hotel_rounded;
    case 'MEALS':
      return Icons.restaurant_rounded;
    case 'LOCAL_CONVEYANCE':
      return Icons.local_taxi_rounded;
    case 'FUEL':
      return Icons.local_gas_station_rounded;
    case 'COMMUNICATION':
      return Icons.call_rounded;
    default:
      return Icons.receipt_long_rounded;
  }
}

/// Icon for a `TravelMode`.
IconData travelModeIcon(String? mode) {
  switch (mode) {
    case 'BIKE':
      return Icons.two_wheeler_rounded;
    case 'BUS':
      return Icons.directions_bus_rounded;
    case 'TRAIN':
      return Icons.train_rounded;
    case 'TAXI':
      return Icons.local_taxi_rounded;
    case 'OWN_CAR':
      return Icons.directions_car_rounded;
    case 'OFFICE_CAR':
      return Icons.directions_car_filled_rounded;
    default:
      return Icons.alt_route_rounded;
  }
}

/// Indian-rupee money formatting used across the travel screens.
String money(double? v) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0];
  final neg = whole.startsWith('-');
  final digits = neg ? whole.substring(1) : whole;
  // Indian grouping: last 3 digits, then pairs.
  final buf = StringBuffer();
  final n = digits.length;
  for (int i = 0; i < n; i++) {
    buf.write(digits[i]);
    final remaining = n - i - 1;
    if (remaining > 0) {
      if (remaining == 3 || (remaining > 3 && (remaining - 3) % 2 == 0)) {
        buf.write(',');
      }
    }
  }
  return '${neg ? '-' : ''}₹$buf.${parts[1]}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Pro presentation helpers for the travel screens
// ─────────────────────────────────────────────────────────────────────────────

/// Hero tag tone for a `TravelClaimStatus`.
ProTagTone claimTagTone(String status) {
  switch (status) {
    case 'APPROVED':
    case 'SETTLED':
      return ProTagTone.ok;
    case 'REJECTED':
      return ProTagTone.bad;
    case 'DRAFT':
      return ProTagTone.neutral;
    default:
      return ProTagTone.warn;
  }
}

/// Pulse-dot colour for the claim's live approval line on the deep hero.
Color claimLiveColor(String status) {
  switch (status) {
    case 'APPROVED':
    case 'SETTLED':
      return AppColors.live;
    case 'REJECTED':
      return const Color(0xFFE5484D);
    case 'DRAFT':
      return Colors.white54;
    default:
      return const Color(0xFFF2B347);
  }
}

/// The approver currently holding the claim (current PENDING step), if any.
TravelClaimApprovalStep? claimPendingStep(TravelClaim claim) {
  for (final s in claim.approvalSteps) {
    if (s.current && s.status == 'PENDING') return s;
  }
  for (final s in claim.approvalSteps) {
    if (s.status == 'PENDING') return s;
  }
  return null;
}

/// One-line approval state shown in the hero's [ProLiveLine].
String claimLiveText(TravelClaim claim) {
  final df = DateFormat('d MMM yyyy');
  String on(DateTime? d) => d == null ? '' : ' on ${df.format(d)}';
  switch (claim.status) {
    case 'DRAFT':
      return 'Draft · add expenses and submit for approval';
    case 'SENT_BACK':
      return 'Sent back for changes · update it and submit again';
    case 'REJECTED':
      return 'Rejected${on(claim.rejectedAt)}';
    case 'APPROVED':
      return 'Approved${on(claim.approvedAt)} · awaiting settlement';
    case 'SETTLED':
      return 'Settled${on(claim.settledAt ?? claim.settlement?.settledAt)}';
    default:
      final step = claimPendingStep(claim);
      final who = step?.approverName ?? 'the approver';
      final lvl = step?.levelOrder == null ? '' : ' · level ${step!.levelOrder}';
      final since = claim.submittedAt == null
          ? ''
          : ' · submitted ${DateFormat('d MMM').format(claim.submittedAt!)}';
      return 'Waiting for $who$lvl$since';
  }
}

/// Icon for an approval-step status node.
IconData approvalStepIcon(String status) {
  switch (status) {
    case 'APPROVED':
      return Icons.check_rounded;
    case 'REJECTED':
      return Icons.close_rounded;
    case 'SENT_BACK':
      return Icons.reply_rounded;
    case 'PENDING':
      return Icons.hourglass_top_rounded;
    case 'SKIPPED':
      return Icons.remove_rounded;
    default:
      return Icons.circle_outlined;
  }
}

/// Vertical approval timeline (rail + status nodes) for a claim's steps.
class TravelApprovalTimeline extends StatelessWidget {
  const TravelApprovalTimeline({
    super.key,
    required this.steps,
    required this.toneOf,
  });

  final List<TravelClaimApprovalStep> steps;

  /// (colour, label) for a step status — each screen keeps its own wording.
  final StatusTone Function(String status) toneOf;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineTile(
            step: steps[i],
            tone: toneOf(steps[i].status),
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.step, required this.tone, required this.isLast});
  final TravelClaimApprovalStep step;
  final StatusTone tone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final active = step.current && step.status == 'PENDING';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tone.color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: active ? Border.all(color: tone.color, width: 1.6) : null,
                ),
                alignment: Alignment.center,
                child: Icon(approvalStepIcon(step.status), size: 14, color: tone.color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: AppColors.hairline,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Level ${step.levelOrder ?? '?'} · ${step.approverName ?? 'Approver'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: active ? AppColors.primary : AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ProPill(tone.label, color: tone.color),
                    ],
                  ),
                  if (step.actionAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        DateFormat('d MMM yyyy, h:mm a').format(step.actionAt!),
                        style: AppText.caption,
                      ),
                    ),
                  if (step.remarks != null && step.remarks!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '“${step.remarks!}”',
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.inkSoft,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
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

/// Bold-titled notice card (sent back / rejected / policy violation) in the
/// Pro note style: tinted fill, no border.
class TravelNotice extends StatelessWidget {
  const TravelNotice({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    this.body,
  });
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
                if (body != null && body!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(body!,
                      style: const TextStyle(
                          fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White bottom-sheet frame (radius 24 top, drag handle, 19px title) used by
/// the travel add/edit/upload sheets. Lifts above the keyboard.
class TravelSheet extends StatelessWidget {
  const TravelSheet({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + mq.padding.bottom),
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
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.35,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Destructive button style (tinted red) per the Pro button rules.
ButtonStyle get travelDangerFilled => FilledButton.styleFrom(
      backgroundColor: AppColors.dangerTint,
      foregroundColor: AppColors.danger,
    );
