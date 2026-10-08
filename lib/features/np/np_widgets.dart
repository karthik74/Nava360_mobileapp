// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — shared presentational widgets + dialogs + document upload.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'np_models.dart';
import 'np_repository.dart';

// ── formatting ──

String npFmtDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d.toLocal());
String npFmtDateTime(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());

void npToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.danger : AppColors.success,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Opens a backend file (image / PDF / HTML report) in the external viewer.
Future<void> npOpenFile(BuildContext context, NpFileRef? file) async {
  final url = Env.fileUrl(file?.url);
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) npToast(context, 'Could not open the file.', error: true);
}

Future<void> npOpenMaps(double lat, double lng) async {
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ── dialogs ──

Future<bool> npConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? npDangerButtonStyle() : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r == true;
}

/// Multi-line text prompt. Returns null when cancelled; empty string is only
/// possible when [required] is false.
Future<String?> npPrompt(
  BuildContext context, {
  required String title,
  String? label,
  String? hint,
  bool required = true,
  String confirmLabel = 'Save',
  bool danger = false,
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  String? err;
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(label, style: AppText.label),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint ?? (required ? 'Required' : 'Optional'), errorText: err),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: danger ? npDangerButtonStyle() : null,
            onPressed: () {
              final v = ctrl.text.trim();
              if (required && v.isEmpty) {
                setState(() => err = 'This is required.');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return r;
}

// ── small presentational pieces ──

/// Destructive filled button (tinted red), per the Pro button rules.
ButtonStyle npDangerButtonStyle() => FilledButton.styleFrom(
      backgroundColor: AppColors.dangerTint,
      foregroundColor: AppColors.danger,
    );

const Color _npOrange = Color(0xFFC2410C);
const Color _npOrangeTint = Color(0xFFFDEADF);
const Color _npViolet = Color(0xFF6D28D9);
const Color _npVioletTint = Color(0xFFF0EAFD);

/// Workflow status as a tinted Pro pill (tones follow [npStatusColor]).
ProPill npStatusProPill(String status, {String? label}) {
  final l = label ?? npStatusLabel(status);
  if (status == 'ACTIVE_NP') return ProPill.ok(l);
  if (status.endsWith('_REJECTED')) return ProPill.bad(l);
  if (status == 'SENT_BACK_FOR_CORRECTION') return ProPill(l, color: _npOrange, background: _npOrangeTint);
  if (status == 'DRAFT') return ProPill.neutral(l);
  if (status.endsWith('_PENDING')) return ProPill.warn(l);
  if (status.endsWith('_SUBMITTED')) return ProPill(l, color: _npViolet, background: _npVioletTint);
  if (status.endsWith('_APPROVED') ||
      status.endsWith('_COMPLETED') ||
      status.endsWith('_CREATED') ||
      status.endsWith('_ACTIVATED') ||
      status == 'INTERVIEW_PASSED') {
    return ProPill.ok(l);
  }
  return ProPill.info(l);
}

/// Workflow status tone for tags on the deep hero.
ProTagTone npStatusTagTone(String status) {
  if (status.endsWith('_REJECTED')) return ProTagTone.bad;
  if (status == 'SENT_BACK_FOR_CORRECTION' || status.endsWith('_PENDING')) return ProTagTone.warn;
  if (status == 'ACTIVE_NP' ||
      status.endsWith('_APPROVED') ||
      status.endsWith('_COMPLETED') ||
      status.endsWith('_CREATED') ||
      status.endsWith('_ACTIVATED') ||
      status == 'INTERVIEW_PASSED') {
    return ProTagTone.ok;
  }
  return ProTagTone.neutral;
}

/// Pill for a status colour picked elsewhere (success / danger / warning …).
ProPill npTonePill(String label, Color color) {
  if (color == AppColors.success) return ProPill.ok(label);
  if (color == AppColors.danger) return ProPill.bad(label);
  if (color == AppColors.warning) return ProPill.warn(label);
  if (color == AppColors.info) return ProPill.info(label);
  if (color == AppColors.muted) return ProPill.neutral(label);
  return ProPill(label, color: color);
}

class NpStatusPill extends StatelessWidget {
  const NpStatusPill({super.key, required this.status, this.label});
  final String status;
  final String? label;
  @override
  Widget build(BuildContext context) => npStatusProPill(status, label: label);
}

class NpFieldLabel extends StatelessWidget {
  const NpFieldLabel(this.text, {super.key, this.required = false});
  final String text;
  final bool required;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Text.rich(
          TextSpan(
            text: text,
            children: [if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger))],
          ),
          style: AppText.label,
        ),
      );
}

/// Key / value line (label left, value right) — the Pro key-value look.
class NpInfoRow extends StatelessWidget {
  const NpInfoRow(this.label, this.value, {super.key});
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) {
    final v = (value == null || value!.trim().isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.ink,
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

/// "By Name · 3 Sep 2026, 10:15 AM"
class NpPersonStamp extends StatelessWidget {
  const NpPersonStamp({super.key, this.person, this.at, this.prefix = 'By'});
  final NpPerson? person;
  final DateTime? at;
  final String prefix;
  @override
  Widget build(BuildContext context) {
    if (person == null && at == null) return const SizedBox.shrink();
    final parts = <String>[];
    if (person != null) parts.add('$prefix ${person!.name}');
    if (at != null) parts.add(npFmtDateTime(at));
    return Text(
      parts.join(' · '),
      style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}

class NpChip extends StatelessWidget {
  const NpChip(this.label, {super.key, this.on = false, this.color});
  final String label;
  final bool on;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    if (color != null) {
      fg = color == AppColors.warning ? const Color(0xFF9A5B00) : color!;
      bg = color == AppColors.warning ? AppColors.warningTint : Color.alphaBlend(color!.withValues(alpha: 0.12), Colors.white);
    } else if (on) {
      fg = AppColors.success;
      bg = AppColors.successTint;
    } else {
      fg = const Color(0xFF43585D);
      bg = AppColors.neutralTint;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(on ? Icons.check_rounded : Icons.radio_button_unchecked_rounded, size: 12, color: fg),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ),
      ]),
    );
  }
}

class NpCheckLine extends StatelessWidget {
  const NpCheckLine({super.key, required this.ok, required this.label, this.failColor});
  final bool ok;
  final String label;
  final Color? failColor;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 18, color: ok ? AppColors.success : (failColor ?? AppColors.faint)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13.5, height: 1.35, color: ok ? AppColors.ink : AppColors.inkSoft, fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

/// A softly filled box for an action form inside a step panel.
class NpActionBox extends StatelessWidget {
  const NpActionBox({super.key, required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairlineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: AppText.title.copyWith(fontSize: 15)),
              const SizedBox(height: 4),
            ],
            child,
          ],
        ),
      );
}

/// Tinted inline banner with an icon well, title, body and an optional action.
class NpBanner extends StatelessWidget {
  const NpBanner({super.key, required this.icon, required this.color, required this.title, this.body, this.action});
  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.08), Colors.white),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: Color.alphaBlend(color.withValues(alpha: 0.22), Colors.white)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ProIconWell(icon: icon, color: color, background: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600, color: color)),
                  if (body != null && body!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(body!, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.45)),
                  ],
                ]),
              ),
            ]),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      );
}

/// Who a form is for: avatar, name, code · mobile, status and (optionally)
/// the address on file.
class NpWhoCard extends StatelessWidget {
  const NpWhoCard({super.key, required this.d, this.address});
  final NpCandidateDetail d;
  final String? address;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProAvatar(name: d.fullName.isEmpty ? '?' : d.fullName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
              Text('${d.candidateCode} · ${d.mobileNumber}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 6),
              NpStatusPill(status: d.status, label: d.statusLabel),
            ]),
          ),
        ]),
        if (address != null && address!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.place_outlined, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(
                        text: 'Address on file\n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
                    TextSpan(text: address),
                  ]),
                  style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── stepper + step panel ──

Color npStepStateColor(String state) {
  switch (state) {
    case 'DONE':
      return AppColors.success;
    case 'CURRENT':
      return AppColors.primary;
    case 'REJECTED':
      return AppColors.danger;
    case 'SENT_BACK':
      return const Color(0xFFEA580C);
    case 'SKIPPED':
      return AppColors.muted;
    default:
      return AppColors.hairline;
  }
}

/// Horizontal 13-dot stepper. Tapping a dot scrolls/opens that panel.
class NpStepper extends StatelessWidget {
  const NpStepper({super.key, required this.steps, required this.selected, required this.onSelect});
  final List<NpStepView> steps;
  final String selected;
  final void Function(String step) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < kNpSteps.length; i++) ...[
            _dot(i),
            if (i < kNpSteps.length - 1)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Container(
                  width: 14,
                  height: 2,
                  decoration: BoxDecoration(
                    color: _stateOf(kNpSteps[i].step) == 'DONE' ? AppColors.success : AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _stateOf(String step) {
    for (final s in steps) {
      if (s.step == step) return s.state;
    }
    return 'PENDING';
  }

  Widget _dot(int i) {
    final info = kNpSteps[i];
    final state = _stateOf(info.step);
    final color = npStepStateColor(state);
    final isSel = info.step == selected;
    final filled = state == 'DONE' || state == 'CURRENT' || state == 'REJECTED' || state == 'SENT_BACK';
    return InkWell(
      onTap: () => onSelect(info.step),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : AppColors.surface,
              border: Border.all(color: isSel ? AppColors.ink : (filled ? color : const Color(0xFFD5DFE1)), width: isSel ? 2 : 1.5),
            ),
            alignment: Alignment.center,
            child: state == 'DONE'
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : Text('${i + 1}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: filled ? Colors.white : AppColors.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
          ),
          const SizedBox(height: 5),
          Text(info.short,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                color: isSel ? AppColors.ink : AppColors.muted,
              )),
        ]),
      ),
    );
  }
}

/// One collapsible workflow step. Flat (no card of its own) — stack the
/// panels inside a [ProListGroup] so they read as one grouped checklist.
class NpStepPanel extends StatelessWidget {
  const NpStepPanel({
    super.key,
    required this.index,
    required this.title,
    required this.view,
    required this.open,
    required this.onToggle,
    required this.children,
  });
  final int index;
  final String title;
  final NpStepView? view;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final state = view?.state ?? 'PENDING';
    final color = npStepStateColor(state);
    final pending = state == 'PENDING';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pending ? AppColors.surfaceAlt : Color.alphaBlend(color.withValues(alpha: 0.12), Colors.white),
                    border: Border.all(color: pending ? const Color(0xFFD5DFE1) : color, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: state == 'DONE'
                      ? Icon(Icons.check_rounded, size: 16, color: color)
                      : Text('$index',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: pending ? AppColors.muted : color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, height: 1.33, fontWeight: FontWeight.w500, letterSpacing: -0.15, color: AppColors.ink),
                    ),
                    if (view != null && (view!.completedBy != null || view!.completedAt != null))
                      NpPersonStamp(person: view!.completedBy, at: view!.completedAt)
                    else if (!pending)
                      Text(npTitle(state), style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
                  ]),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, color: Color(0xFFB3C0C3)),
                ),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (view?.remarks != null && view!.remarks!.isNotEmpty) ...[
                  ProNote(view!.remarks!, icon: Icons.notes_rounded),
                  const SizedBox(height: 12),
                ],
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ── documents ──

class NpDocumentTile extends StatelessWidget {
  const NpDocumentTile({super.key, required this.doc, this.onDelete, this.onVerify, this.busy = false});
  final NpDocument doc;
  final VoidCallback? onDelete;
  final VoidCallback? onVerify;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final imgUrl = doc.file.isImage ? Env.fileUrl(doc.file.url) : null;
    final compact = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 32),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => npOpenFile(context, doc.file),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: imgUrl != null
                    ? Image.network(imgUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fileIcon())
                    : _fileIcon(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(doc.docTypeLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.ink)),
                ),
                if (doc.verified)
                  ProPill.ok('Verified')
                else if (doc.superseded)
                  ProPill.neutral('Replaced'),
                const SizedBox(width: 4),
              ]),
              if (doc.documentNumber != null && doc.documentNumber!.isNotEmpty)
                Text('No. ${doc.documentNumber}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, fontFeatures: [FontFeature.tabularFigures()])),
              if (doc.caption != null && doc.caption!.isNotEmpty)
                Text(doc.caption!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              NpPersonStamp(person: doc.uploadedBy, at: doc.uploadedAt),
              if (doc.verified && doc.verifiedBy != null)
                NpPersonStamp(person: doc.verifiedBy, at: doc.verifiedAt, prefix: 'Verified by'),
              const SizedBox(height: 2),
              Row(children: [
                TextButton.icon(
                  style: compact,
                  onPressed: () => npOpenFile(context, doc.file),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('Open'),
                ),
                if (doc.latitude != null && doc.longitude != null)
                  TextButton.icon(
                    style: compact,
                    onPressed: () => npOpenMaps(doc.latitude!, doc.longitude!),
                    icon: const Icon(Icons.place_outlined, size: 15),
                    label: const Text('Map'),
                  ),
                const Spacer(),
                if (onVerify != null && !doc.verified)
                  TextButton(
                    style: compact,
                    onPressed: busy ? null : onVerify,
                    child: const Text('Verify'),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Remove',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.danger),
                  ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _fileIcon() => Container(
        color: AppColors.neutralTint,
        alignment: Alignment.center,
        child: Icon(doc.file.isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
            color: AppColors.primary, size: 22),
      );
}

class NpDocumentList extends StatelessWidget {
  const NpDocumentList({
    super.key,
    required this.documents,
    this.emptyText = 'No documents.',
    this.onDelete,
    this.onVerify,
    this.busy = false,
  });
  final List<NpDocument> documents;
  final String emptyText;
  final void Function(NpDocument doc)? onDelete;
  final void Function(NpDocument doc)? onVerify;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Text(emptyText, style: AppText.caption.copyWith(fontSize: 13));
    }
    return Column(children: [
      for (var i = 0; i < documents.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == documents.length - 1 ? 0 : 8),
          child: NpDocumentTile(
            doc: documents[i],
            busy: busy,
            onDelete: onDelete == null ? null : () => onDelete!(documents[i]),
            onVerify: onVerify == null ? null : () => onVerify!(documents[i]),
          ),
        ),
    ]);
  }
}

/// White bottom-sheet frame: 24px top radius, drag handle, optional title.
class NpSheetFrame extends StatelessWidget {
  const NpSheetFrame({super.key, required this.child, this.title, this.subtitle});
  final Widget child;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    // A Material (not a plain Container) so list-tile ink and selection
    // highlights paint on the white sheet rather than behind it.
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: const Color(0xFFC6D3D6), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title!,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.35, color: AppColors.ink)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppText.caption.copyWith(fontSize: 13)),
                ],
              ]),
            ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Tries to read a current GPS fix, falling back to the last known position.
/// Returns nulls silently when location is unavailable or denied.
Future<({double? lat, double? lng, double? accuracy})> npTryLocation({bool request = true}) async {
  try {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied && request) {
      perm = await Geolocator.requestPermission();
    }
    final granted = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    if (!granted || !serviceOn) return (lat: null, lng: null, accuracy: null);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return (lat: pos.latitude, lng: pos.longitude, accuracy: pos.accuracy);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return (lat: last?.latitude, lng: last?.longitude, accuracy: last?.accuracy);
    }
  } catch (_) {
    return (lat: null, lng: null, accuracy: null);
  }
}

class NpPickedRef {
  final String path;
  final String name;
  const NpPickedRef(this.path, this.name);
}

/// Camera / gallery / PDF chooser. Returns null when dismissed.
Future<NpPickedRef?> npPickFile(BuildContext context, {bool allowPdf = true, bool imagesOnly = false}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => NpSheetFrame(
      title: 'Add a file',
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: ProIconWell(icon: Icons.photo_camera_outlined, color: AppColors.primary),
              title: const Text('Take a photo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: ProIconWell(icon: Icons.photo_library_outlined, color: AppColors.primary),
              title: const Text('Choose from gallery', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (allowPdf && !imagesOnly)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: ProIconWell(icon: Icons.picture_as_pdf_outlined, color: AppColors.primary),
                title: const Text('Pick a PDF / document', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () => Navigator.pop(context, 'file'),
              ),
          ]),
        ),
      ),
    ),
  );
  if (choice == null) return null;
  if (choice == 'file') {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: false,
    );
    final f = r?.files.single;
    if (f?.path == null) return null;
    return NpPickedRef(f!.path!, f.name);
  }
  final picked = await ImagePicker().pickImage(
    source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 70,
    maxWidth: 1800,
  );
  if (picked == null) return null;
  final name = picked.name.contains('.') ? picked.name : '${picked.name}.jpg';
  return NpPickedRef(picked.path, name);
}

/// Bottom-sheet uploader for one NP stage: doc type + number + caption +
/// file. With [captureGps] the phone position is attached to the upload —
/// that is how BGV visit photos are geotagged. Returns true when a document
/// was uploaded.
Future<bool> npUploadDocumentSheet(
  BuildContext context,
  WidgetRef ref, {
  required int candidateId,
  required List<NpDocumentTypeConfig> docTypes,
  String? initialDocType,
  bool captureGps = false,
  String? parentType,
  int? parentId,
}) async {
  if (docTypes.isEmpty) {
    npToast(context, 'No document types are configured for this stage.', error: true);
    return false;
  }
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UploadSheet(
      candidateId: candidateId,
      docTypes: docTypes,
      initialDocType: initialDocType,
      captureGps: captureGps,
      parentType: parentType,
      parentId: parentId,
      ref: ref,
    ),
  );
  return result == true;
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({
    required this.candidateId,
    required this.docTypes,
    this.initialDocType,
    required this.captureGps,
    this.parentType,
    this.parentId,
    required this.ref,
  });
  final int candidateId;
  final List<NpDocumentTypeConfig> docTypes;
  final String? initialDocType;
  final bool captureGps;
  final String? parentType;
  final int? parentId;
  final WidgetRef ref;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  late String _docType;
  final _number = TextEditingController();
  final _caption = TextEditingController();
  NpPickedRef? _file;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _docType = widget.docTypes.any((t) => t.code == widget.initialDocType)
        ? widget.initialDocType!
        : widget.docTypes.first.code;
  }

  @override
  void dispose() {
    _number.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (_file == null) {
      setState(() => _error = 'Pick a file first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      double? lat, lng;
      if (widget.captureGps) {
        final loc = await npTryLocation();
        lat = loc.lat;
        lng = loc.lng;
      }
      await widget.ref.read(npRepositoryProvider).uploadDocument(
            widget.candidateId,
            filePath: _file!.path,
            fileName: _file!.name,
            docType: _docType,
            documentNumber: _number.text,
            caption: _caption.text,
            latitude: lat,
            longitude: lng,
            capturedAt: DateTime.now(),
            parentType: widget.parentType,
            parentId: widget.parentId,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: NpSheetFrame(
        title: 'Upload document',
        subtitle: widget.captureGps ? 'Your current location is attached to the photo.' : null,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NpFieldLabel('Document type', required: true),
              DropdownButtonFormField<String>(
                value: _docType,
                isExpanded: true,
                items: [
                  for (final t in widget.docTypes)
                    DropdownMenuItem(value: t.code, child: Text(t.mandatory ? '${t.label} *' : t.label)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _docType = v ?? _docType),
              ),
              const NpFieldLabel('Document number'),
              TextField(controller: _number, decoration: const InputDecoration(hintText: 'Optional')),
              const NpFieldLabel('Caption'),
              TextField(
                controller: _caption,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Optional'),
              ),
              const NpFieldLabel('File', required: true),
              _NpFileTile(
                fileName: _file?.name,
                emptyText: 'Choose file (photo or PDF)',
                onTap: _busy
                    ? null
                    : () async {
                        final f = await npPickFile(context);
                        if (f != null) setState(() => _file = f);
                      },
              ),
              if (_file != null && !_file!.name.toLowerCase().endsWith('.pdf')) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(File(_file!.path), height: 140, fit: BoxFit.cover),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ProNote(_error!, tone: ProNoteTone.bad),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_busy ? 'Uploading…' : 'Upload'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple "pick a file" field for the agreement / PDC scans.
class NpFilePickField extends StatelessWidget {
  const NpFilePickField({super.key, required this.label, required this.fileName, required this.onPick, this.required = true});
  final String label;
  final String? fileName;
  final VoidCallback onPick;
  final bool required;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        NpFieldLabel(label, required: required),
        _NpFileTile(fileName: fileName, emptyText: 'Choose photo or PDF', onTap: onPick),
      ]);
}

/// Tappable file slot: icon well, chosen file name (or a prompt) and a
/// "Choose" / "Change" affordance.
class _NpFileTile extends StatelessWidget {
  const _NpFileTile({required this.fileName, required this.emptyText, required this.onTap});
  final String? fileName;
  final String emptyText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = fileName != null;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: has ? AppColors.surface : AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: has ? AppColors.hairline : const Color(0xFFDBE3E5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            child: Row(children: [
              ProIconWell(
                icon: has ? Icons.check_rounded : Icons.attach_file_rounded,
                color: has ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  fileName ?? emptyText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: has ? FontWeight.w500 : FontWeight.w400,
                    color: has ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(has ? 'Change' : 'Choose',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Exposes the picker's result type for callers outside this file.
typedef NpPickedFile = ({String path, String name});

Future<NpPickedFile?> npPickAnyFile(BuildContext context) async {
  final f = await npPickFile(context);
  return f == null ? null : (path: f.path, name: f.name);
}
