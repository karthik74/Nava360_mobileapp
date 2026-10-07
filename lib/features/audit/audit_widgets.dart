// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — reusable presentation widgets ("Pro" look).
//
//  Card-first, no wide tables. Scores / percentages are on a 0–100 scale.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../core/pro_ui.dart';
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
      return (color: AppColors.primary, label: 'In progress');
    case 'SUBMITTED':
      return (color: AppColors.accent, label: 'Submitted');
    case 'ASSIGNED':
      return (color: AppColors.info, label: 'Assigned');
    case 'SUPERVISOR_APPROVAL_PENDING':
      return (color: AppColors.warning, label: 'Supervisor approval');
    case 'BM_ACTION_PENDING':
    case 'SENT_TO_BM': // legacy alias
      return (color: AppColors.warning, label: 'Sent to BM');
    case 'BM_ACTION_SUBMITTED':
    case 'VERIFICATION_PENDING':
    case 'BM_SUBMITTED': // legacy alias
    case 'BM_RESPONDED':
      return (color: AppColors.pink, label: 'BM submitted');
    case 'UNDER_REVIEW':
      return (color: AppColors.accent, label: 'Under review');
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
      return (color: AppColors.warning, label: 'In progress');
    case 'CAPA_SUBMITTED':
    case 'PENDING_VERIFICATION':
      return (color: AppColors.accent, label: 'CAPA submitted');
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

/// Pill / tile background for a status colour.
Color auditTint(Color c) {
  if (c == AppColors.success) return AppColors.successTint;
  if (c == AppColors.warning) return AppColors.warningTint;
  if (c == AppColors.danger) return AppColors.dangerTint;
  if (c == AppColors.info || c == AppColors.accent) return AppColors.infoTint;
  if (c == AppColors.muted) return AppColors.neutralTint;
  return c.withValues(alpha: 0.12);
}

/// Text colour that reads on [auditTint] (amber and grey get an ink shade).
Color auditInk(Color c) {
  if (c == AppColors.warning) return const Color(0xFF9A5B00);
  if (c == AppColors.muted) return const Color(0xFF43585D);
  return c;
}

/// Tinted status pill for any status colour.
ProPill auditPill(String label, Color color, {bool dot = false}) =>
    ProPill(label, color: auditInk(color), background: auditTint(color), dot: dot);

/// Hero tag tone (deep surfaces) for a status colour.
ProTagTone auditTagTone(Color c) {
  if (c == AppColors.success) return ProTagTone.ok;
  if (c == AppColors.warning) return ProTagTone.warn;
  if (c == AppColors.danger) return ProTagTone.bad;
  return ProTagTone.neutral;
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
    if (icon == null) return auditPill(t.label, t.color);
    return _IconPill(label: t.label, color: t.color, icon: icon!);
  }
}

/// A pill rendering a finding status.
class FindingStatusChip extends StatelessWidget {
  const FindingStatusChip({super.key, required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final t = findingStatusTone(status);
    return auditPill(t.label, t.color);
  }
}

/// A pill rendering a finding severity.
class SeverityChip extends StatelessWidget {
  const SeverityChip({super.key, required this.severity});
  final String? severity;

  @override
  Widget build(BuildContext context) {
    final t = severityTone(severity);
    return _IconPill(label: t.label, color: t.color, icon: Icons.flag_rounded);
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ink = auditInk(color);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: auditTint(color),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Score bar (0–100) ─────────────────────────────────────────────────────────

/// A labelled progress bar with a tinted % pill for a 0–100 score.
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
                style: AppText.section,
              ),
            ),
            const SizedBox(width: 8),
            auditPill(auditPct(score), tone),
          ],
        ),
        if (sub != null || riskLevel != null) ...[
          const SizedBox(height: 2),
          Text(
            [
              if (sub != null) sub!,
              if (riskLevel != null) 'Risk: $riskLevel',
            ].join(' · '),
            style: AppText.caption,
          ),
        ],
        const SizedBox(height: 12),
        ProBar(value: clamped, color: tone, height: 6),
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
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: v,
                strokeWidth: size * 0.085,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.hairlineSoft,
                valueColor: AlwaysStoppedAnimation(tone),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    auditPct(score),
                    style: TextStyle(
                      fontSize: size * 0.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: auditInk(tone),
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    label!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ─────────────────────────────────────────────────────────────

/// A titled white card (Pro section header + body).
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                ProIconWell(icon: icon!, color: AppColors.primary, size: 30),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.section,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheets ────────────────────────────────────────────────────────────

/// White bottom-sheet frame (radius 24 top, drag handle, 19px title). Lifts
/// above the keyboard; the [child] may be scrollable (it is given the space
/// left under the title).
class AuditSheet extends StatelessWidget {
  const AuditSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6D3D6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.35,
                                color: AppColors.ink,
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(subtitle!, style: AppText.caption),
                              ),
                          ],
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              Flexible(child: Padding(padding: padding, child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pickers (filters) ────────────────────────────────────────────────────────

/// Wraps a picker choice so "All" (null) can be told apart from "dismissed".
class AuditPickResult<T> {
  const AuditPickResult(this.value);
  final T? value;
}

/// Bottom-sheet single-choice list. Returns null when dismissed.
Future<AuditPickResult<T>?> showAuditPicker<T>(
  BuildContext context, {
  required String title,
  required List<({T? value, String label})> options,
  required T? selected,
}) {
  return showModalBottomSheet<AuditPickResult<T>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => AuditSheet(
      title: title,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.62,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              thickness: 1,
              indent: 14,
              color: AppColors.hairlineSoft,
            ),
            itemBuilder: (_, i) {
              final o = options[i];
              final on = o.value == selected;
              return ProListRow(
                title: o.label,
                chevron: false,
                trailing: on
                    ? Icon(Icons.check_rounded, size: 20, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, AuditPickResult<T>(o.value)),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Tappable filter field: small label over the current value + chevron.
class AuditPickField extends StatelessWidget {
  const AuditPickField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  /// Highlights the border when a non-default value is picked.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: active ? AppColors.primary : const Color(0xFFD9E2E4),
          width: active ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more_rounded,
                  size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pager row ("‹  Page 2 of 5  ›") for server-paged lists.
class AuditPager extends StatelessWidget {
  const AuditPager({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });
  final int page; // zero-based
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  icon,
                  size: 22,
                  color: onTap == null ? AppColors.hairline : AppColors.ink,
                ),
              ),
            ),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        btn(Icons.chevron_left_rounded, 'Previous page', onPrev),
        const SizedBox(width: 14),
        Text(
          'Page ${page + 1} of $totalPages',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 14),
        btn(Icons.chevron_right_rounded, 'Next page', onNext),
      ],
    );
  }
}
