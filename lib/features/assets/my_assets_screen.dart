import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'assets_models.dart';
import 'assets_repository.dart';

final myAssetsProvider = FutureProvider.autoDispose<List<AssetAssignment>>((ref) {
  return ref.watch(assetsRepositoryProvider).getMyAssets();
});

Color assetStatusColor(String s) {
  switch (s) {
    case 'AVAILABLE':
      return AppColors.success;
    case 'ASSIGNED':
      return AppColors.primary;
    case 'IN_REPAIR':
      return AppColors.warning;
    case 'LOST':
    case 'DAMAGED':
      return AppColors.danger;
    default:
      return AppColors.muted;
  }
}

String assetStatusLabel(String s) {
  switch (s) {
    case 'AVAILABLE':
      return 'Available';
    case 'ASSIGNED':
      return 'Assigned';
    case 'IN_REPAIR':
      return 'In repair';
    case 'LOST':
      return 'Lost';
    case 'DAMAGED':
      return 'Damaged';
    default:
      return s.isEmpty ? '—' : s[0] + s.substring(1).toLowerCase();
  }
}

/// Picks a representative icon from the asset name so each card has a
/// recognisable visual anchor.
IconData assetIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('laptop') || n.contains('macbook') || n.contains('notebook')) {
    return Icons.laptop_mac_rounded;
  }
  if (n.contains('iphone') || n.contains('phone') || n.contains('mobile')) {
    return Icons.smartphone_rounded;
  }
  if (n.contains('ipad') || n.contains('tablet')) return Icons.tablet_mac_rounded;
  if (n.contains('monitor') || n.contains('display') || n.contains('screen')) {
    return Icons.desktop_windows_rounded;
  }
  if (n.contains('printer') || n.contains('scanner')) return Icons.print_rounded;
  if (n.contains('keyboard')) return Icons.keyboard_rounded;
  if (n.contains('mouse')) return Icons.mouse_rounded;
  if (n.contains('headset') || n.contains('headphone') || n.contains('earphone')) {
    return Icons.headset_mic_rounded;
  }
  if (n.contains('camera')) return Icons.photo_camera_rounded;
  if (n.contains('car') || n.contains('vehicle') || n.contains('bike')) {
    return Icons.directions_car_rounded;
  }
  if (n.contains('sim') || n.contains('card')) return Icons.sim_card_rounded;
  if (n.contains('router') || n.contains('wifi') || n.contains('modem')) {
    return Icons.router_rounded;
  }
  return Icons.devices_other_rounded;
}

class MyAssetsScreen extends ConsumerWidget {
  const MyAssetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myAssetsProvider);
    final mq = MediaQuery.of(context);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan'),
          onPressed: () => context.push('/assets/scan'),
        ),
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(mq.padding.top + AppChrome.appBarHeight),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: GlassBlur.chrome, sigmaY: GlassBlur.chrome),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.hairline)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          color: AppColors.inkSoft,
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text('My Assets',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800,
                                  color: AppColors.ink, letterSpacing: -0.2)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: Colors.white.withOpacity(0.92),
          onRefresh: () async => ref.invalidate(myAssetsProvider),
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 90),
            children: [
              async.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.devices_other_rounded,
                      message: 'No assets are assigned to you.',
                    );
                  }
                  return Column(
                    children: [
                      for (final a in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AssetCard(assignment: a),
                        ),
                    ],
                  );
                },
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myAssetsProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetCard extends ConsumerWidget {
  const _AssetCard({required this.assignment});
  final AssetAssignment assignment;

  String _fmt(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

  Future<void> _ack(BuildContext context, WidgetRef ref, bool accept) async {
    String? remarks;
    if (!accept) {
      remarks = await _prompt(context, 'Reason for rejecting');
      if (remarks == null) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(assetsRepositoryProvider).acknowledge(assignment.id, accept, remarks: remarks);
      ref.invalidate(myAssetsProvider);
      messenger.showSnackBar(SnackBar(content: Text(accept ? 'Asset acknowledged ✓' : 'Assignment rejected')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _return(BuildContext context, WidgetRef ref) async {
    final note = await _prompt(context, 'Condition note (optional)', required: false);
    if (note == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(assetsRepositoryProvider).returnRequest(
            assignment.assetId,
            returnedDate: DateTime.now().toIso8601String().substring(0, 10),
            conditionOnReturn: note.isEmpty ? null : note,
          );
      ref.invalidate(myAssetsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Return requested — awaiting verification')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _incident(BuildContext context, WidgetRef ref) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in const ['DAMAGE', 'LOST', 'STOLEN'])
              ListTile(title: Text(t), onTap: () => Navigator.pop(context, t)),
          ],
        ),
      ),
    );
    if (type == null) return;
    final desc = await _prompt(context, 'Describe the incident', required: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(assetsRepositoryProvider).reportIncident(
            assignment.assetId,
            incidentType: type,
            incidentDate: DateTime.now().toIso8601String().substring(0, 10),
            description: desc,
          );
      ref.invalidate(myAssetsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Incident reported — awaiting approval')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = assignment;
    final pending = a.acknowledgementRequired && a.acknowledgementStatus == 'PENDING';
    final tone = assetStatusColor(a.status);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: icon · name + tag · status pill ──────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tone.withOpacity(0.18), tone.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tone.withOpacity(0.22)),
                ),
                alignment: Alignment.center,
                child: Icon(assetIcon(a.assetName), color: tone, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.assetName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.qr_code_2_rounded,
                            size: 13, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            a.assetTag.isEmpty ? '—' : a.assetTag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: assetStatusLabel(a.status), color: tone),
            ],
          ),
          const SizedBox(height: 14),
          // ── Meta: assigned / return-by tiles ─────────────────────────
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.event_available_rounded,
                  label: 'ASSIGNED',
                  value: _fmt(a.assignedDate),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoTile(
                  icon: Icons.event_busy_rounded,
                  label: 'RETURN BY',
                  value: _fmt(a.expectedReturnDate),
                ),
              ),
            ],
          ),
          // ── Serial number / IMEI tiles (only when present) ───────────
          if ((a.serialNumber?.trim().isNotEmpty ?? false) ||
              (a.imeiNumber?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (a.serialNumber?.trim().isNotEmpty ?? false)
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.tag_rounded,
                      label: 'SERIAL NO.',
                      value: a.serialNumber!.trim(),
                    ),
                  ),
                if ((a.serialNumber?.trim().isNotEmpty ?? false) &&
                    (a.imeiNumber?.trim().isNotEmpty ?? false))
                  const SizedBox(width: 8),
                if (a.imeiNumber?.trim().isNotEmpty ?? false)
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.smartphone_rounded,
                      label: 'IMEI',
                      value: a.imeiNumber!.trim(),
                    ),
                  ),
              ],
            ),
          ],
          // ── Acknowledgement state / actions ──────────────────────────
          if (pending) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.warning.withOpacity(0.28)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_rounded, size: 16, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please review and acknowledge this assignment.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ack(context, ref, true),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _ack(context, ref, false),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (a.acknowledgementStatus == 'ACCEPTED') ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.verified_rounded,
                      size: 15, color: AppColors.success),
                  SizedBox(width: 6),
                  Text(
                    'Acknowledged',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _return(context, ref),
                    icon: const Icon(Icons.assignment_return_rounded, size: 16),
                    label: const Text('Return'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _incident(context, ref),
                    icon: const Icon(Icons.report_problem_rounded, size: 16),
                    label: const Text('Report'),
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

/// Compact labelled fact tile used inside the asset card meta row.
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.muted),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, {bool required = true}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        textCapitalization: TextCapitalization.words,
        inputFormatters: const [TitleCaseTextFormatter()],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (required && ctrl.text.trim().isEmpty) return;
            Navigator.pop(ctx, ctrl.text.trim());
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
