// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — reusable presentation widgets.
//
//  Card-first, no wide tables. Scores / percentages are on a 0–100 scale.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../core/theme.dart';

// ── Formatting / tone helpers────────────────────────────────────────────────

/// 0–100 score → "73.0%". Null → "—".
String auditPct(double? score) =>
    score == null ? '—' : '${score.toStringAsFixed(1)}%';

/// Status color for a 0–100 score: >=90 success, >=60 warning, else danger.
Color auditScoreTone(double? score) {
  if (score == null) return AppColors.muted;
  if (score >= 90) return AppColors.success;
  if (score >= 60) return AppColors.warning;
  return AppColors.danger;
}

/// (color, label) for an audit plan / execution status string.
({Color color, String label}) auditStatusTone(String? raw) {
  switch (raw) {
    case 'DRAFT':
      return (color: AppColors.muted, label: 'Draft');
    case 'PLANNED':
      return (color: AppColors.info, label: 'Planned');
    case 'IN_PROGRESS':
      return (color: AppColors.primary, label: 'In Progress');
    case 'SUBMITTED':
      return (color: AppColors.accent, label: 'Submitted');
    case 'SENT_TO_BM':
      return (color: AppColors.warning, label: 'Sent to BM');
    case 'BM_SUBMITTED':
    case 'BM_RESPONDED':
      return (color: AppColors.pink, label: 'BM Submitted');
    case 'UNDER_REVIEW':
      return (color: AppColors.accent, label: 'Under Review');
    case 'REOPENED':
      return (color: AppColors.warning, label: 'Reopened');
    case 'CLOSED':
      return (color: AppColors.success, label: 'Closed');
    case 'CANCELLED':
      return (color: AppColors.danger, label: 'Cancelled');
    default:
      return (color: AppColors.muted, label: raw ?? '—');
  }
}

/// (color, label) for a finding status string.
({Color color, String label}) findingStatusTone(String? raw) {
  switch (raw) {
    case 'OPEN':
      return (color: AppColors.danger, label: 'Open');
    case 'IN_PROGRESS':
      return (color: AppColors.warning, label: 'In Progress');
    case 'CAPA_SUBMITTED':
    case 'PENDING_VERIFICATION':
      return (color: AppColors.accent, label: 'CAPA Submitted');
    case 'ACCEPTED':
      return (color: AppColors.primary, label: 'Accepted');
    case 'REJECTED':
      return (color: AppColors.danger, label: 'Rejected');
    case 'REOPENED':
      return (color: AppColors.warning, label: 'Reopened');
    case 'ESCALATED':
      return (color: AppColors.pink, label: 'Escalated');
    case 'CLOSED':
      return (color: AppColors.success, label: 'Closed');
    default:
      return (color: AppColors.muted, label: raw ?? '—');
  }
}

/// (color, label) for a finding severity string.
({Color color, String label}) severityTone(String? raw) {
  switch (raw) {
    case 'HIGH':
      return (color: AppColors.danger, label: 'High');
    case 'MODERATE':
      return (color: AppColors.warning, label: 'Moderate');
    case 'LOW':
      return (color: AppColors.success, label: 'Low');
    default:
      return (color: AppColors.muted, label: raw ?? '—');
  }
}

// ── Status chips ─────────────────────────────────────────────────────────────

/// A pill rendering an audit plan / execution status (tone via [auditStatusTone]).
class AuditStatusChip extends StatelessWidget {
  const AuditStatusChip({super.key, required this.status, this.icon});
  final String? status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = auditStatusTone(status);
    return StatusPill(label: t.label, color: t.color, icon: icon);
  }
}

/// A pill rendering a finding status.
class FindingStatusChip extends StatelessWidget {
  const FindingStatusChip({super.key, required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final t = findingStatusTone(status);
    return StatusPill(label: t.label, color: t.color);
  }
}

/// A pill rendering a finding severity.
class SeverityChip extends StatelessWidget {
  const SeverityChip({super.key, required this.severity});
  final String? severity;

  @override
  Widget build(BuildContext context) {
    final t = severityTone(severity);
    return StatusPill(
      label: t.label,
      color: t.color,
      icon: Icons.flag_rounded,
    );
  }
}

// ── Score bar (0–100) ─────────────────────────────────────────────────────────

/// A labelled linear progress bar with a tinted % badge for a 0–100 score.
class AuditScoreBar extends StatelessWidget {
  const AuditScoreBar({
    super.key,
    required this.label,
    required this.score,
    this.sub,
    this.riskLevel,
  });

  final String label;
  final double? score; // 0–100
  final String? sub;
  final String? riskLevel;

  @override
  Widget build(BuildContext context) {
    final tone = auditScoreTone(score);
    final clamped = ((score ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: tone.withValues(alpha: 0.30)),
              ),
              child: Text(
                auditPct(score),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
        if (sub != null || riskLevel != null) ...[
          const SizedBox(height: 3),
          Text(
            [
              if (sub != null) sub!,
              if (riskLevel != null) 'Risk: $riskLevel',
            ].join(' · '),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
        ],
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 7,
            backgroundColor: AppColors.hairline,
            valueColor: AlwaysStoppedAnimation(tone),
          ),
        ),
      ],
    );
  }
}

// ── Score ring (0–100) ─────────────────────────────────────────────────────────

/// A circular progress ring with the centred % value for a 0–100 score.
class AuditScoreRing extends StatelessWidget {
  const AuditScoreRing({
    super.key,
    required this.score,
    this.size = 92,
    this.label,
  });

  final double? score; // 0–100
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tone = auditScoreTone(score);
    final clamped = ((score ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: clamped,
              strokeWidth: 8,
              backgroundColor: AppColors.hairline,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                auditPct(score),
                style: TextStyle(
                  fontSize: size * 0.20,
                  fontWeight: FontWeight.w800,
                  color: tone,
                  height: 1.0,
                ),
              ),
              if (label != null) ...[
                const SizedBox(height: 2),
                Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section card ─────────────────────────────────────────────────────────────

/// A titled white card with an icon and divider (mirrors the team-detail look).
class AuditSectionCard extends StatelessWidget {
  const AuditSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// A simple key/value row used inside section cards.
class AuditKeyValueRow extends StatelessWidget {
  const AuditKeyValueRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
