import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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

/// Hero stat filters (index into [_filterNames]; -1 = all).
const _filterNames = ['To acknowledge', 'In repair', 'Acknowledged'];
const _emptyTitles = ['Nothing to acknowledge', 'Nothing in repair', 'Nothing acknowledged yet'];

bool _isPendingAck(AssetAssignment a) =>
    a.acknowledgementRequired && a.acknowledgementStatus == 'PENDING';
bool _isInRepair(AssetAssignment a) => a.status == 'IN_REPAIR';
bool _isAcknowledged(AssetAssignment a) => a.acknowledgementStatus == 'ACCEPTED';

class MyAssetsScreen extends ConsumerStatefulWidget {
  const MyAssetsScreen({super.key});

  @override
  ConsumerState<MyAssetsScreen> createState() => _MyAssetsScreenState();
}

class _MyAssetsScreenState extends ConsumerState<MyAssetsScreen> {
  int _f = -1;

  bool _matches(AssetAssignment a) {
    switch (_f) {
      case 0:
        return _isPendingAck(a);
      case 1:
        return _isInRepair(a);
      case 2:
        return _isAcknowledged(a);
      default:
        return true;
    }
  }

  void _toggle(int i) => setState(() => _f = _f == i ? -1 : i);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myAssetsProvider);
    final list = async.valueOrNull;

    final all = list ?? const <AssetAssignment>[];
    final pending = all.where(_isPendingAck).toList();
    final repair = all.where(_isInRepair).toList();
    final acked = all.where(_isAcknowledged).toList();

    String repairSub() {
      if (repair.isEmpty) return 'None';
      final a = repair.first;
      if (a.assetType?.trim().isNotEmpty ?? false) return a.assetType!.trim();
      if (a.category?.trim().isNotEmpty ?? false) return a.category!.trim();
      return a.assetName;
    }

    final children = <Widget>[
      ...async.when<List<Widget>>(
        data: (list) {
          if (list.isEmpty) {
            return const [
              ProEmpty(
                icon: Icons.devices_other_rounded,
                title: 'No assets yet',
                message: 'No assets are assigned to you.',
              ),
            ];
          }
          final shown = list.where(_matches).toList();
          return [
            ProSectionHeader(
              title: '${_f == -1 ? 'All assets' : _filterNames[_f]} · ${shown.length}',
              small: true,
              actionLabel: _f == -1 ? null : 'Show all',
              onAction: () => setState(() => _f = -1),
            ),
            if (shown.isEmpty)
              ProEmpty(
                icon: Icons.devices_other_rounded,
                title: _emptyTitles[_f],
                message: 'Try another filter or show all assets.',
              )
            else
              for (final a in shown) _AssetCard(assignment: a),
          ];
        },
        loading: () => const [AppLoadingBlock(height: 160), AppLoadingBlock(height: 160)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(myAssetsProvider),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Assets')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan'),
        onPressed: () => context.push('/assets/scan'),
      ),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myAssetsProvider),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        hero: ProHero(
          title: 'My assets',
          subtitle: list == null
              ? 'Devices and equipment issued to you'
              : '${all.length} ${all.length == 1 ? 'asset' : 'assets'} assigned to you',
          children: [
            ProHeroStats(stats: [
              ProStat(
                label: 'Pending',
                value: list == null ? '—' : '${pending.length}',
                sub: list == null ? null : (pending.isEmpty ? 'All done' : 'To acknowledge'),
                dot: const Color(0xFFF2B347),
                selected: _f == 0,
                onTap: list == null ? null : () => _toggle(0),
              ),
              ProStat(
                label: 'In repair',
                value: list == null ? '—' : '${repair.length}',
                sub: list == null ? null : repairSub(),
                dot: const Color(0xFF3CC2D8),
                selected: _f == 1,
                onTap: list == null ? null : () => _toggle(1),
              ),
              ProStat(
                label: 'Acknowledged',
                value: list == null ? '—' : '${acked.length}',
                sub: list == null ? null : 'of ${all.length} with you',
                dot: AppColors.live,
                selected: _f == 2,
                onTap: list == null ? null : () => _toggle(2),
              ),
            ]),
          ],
        ),
        children: children,
      ),
    );
  }
}

class _AssetCard extends ConsumerWidget {
  const _AssetCard({required this.assignment});
  final AssetAssignment assignment;

  String _fmt(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);
  bool _present(String? s) => s != null && s.trim().isNotEmpty;

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
      builder: (_) => _IncidentTypeSheet(
        assetName: assignment.assetName,
        assetTag: assignment.assetTag,
        onPick: (t) => Navigator.pop(context, t),
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
    final hasSerial = a.serialNumber?.trim().isNotEmpty ?? false;
    final hasImei = a.imeiNumber?.trim().isNotEmpty ?? false;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: icon · name + tag · status pill ──────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(icon: assetIcon(a.assetName), color: tone, size: 42),
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
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                        height: 1.3,
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
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ProPill(assetStatusLabel(a.status), color: tone),
            ],
          ),
          const SizedBox(height: 14),
          // ── What it is: type / brand / model (only when the backend sends them) ──
          if (_present(a.assetType) || _present(a.category) ||
              _present(a.brand) || _present(a.model)) ...[
            Row(
              children: [
                Expanded(
                  child: _InfoTile(
                    label: 'Type',
                    value: _present(a.assetType)
                        ? a.assetType!.trim()
                        : (_present(a.category) ? a.category!.trim() : '—'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoTile(
                    label: 'Brand',
                    value: _present(a.brand) ? a.brand!.trim() : '—',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoTile(
                    label: 'Model',
                    value: _present(a.model) ? a.model!.trim() : '—',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // ── Meta: assigned / return-by tiles ─────────────────────────
          Row(
            children: [
              Expanded(
                child: _InfoTile(label: 'Assigned', value: _fmt(a.assignedDate)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoTile(label: 'Return by', value: _fmt(a.expectedReturnDate)),
              ),
            ],
          ),
          // ── Serial number / IMEI tiles (only when present) ───────────
          if (hasSerial || hasImei) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (hasSerial)
                  Expanded(
                    child: _InfoTile(
                      label: 'Serial no.',
                      value: a.serialNumber!.trim(),
                      mono: true,
                    ),
                  ),
                if (hasSerial && hasImei) const SizedBox(width: 8),
                if (hasImei)
                  Expanded(
                    child: _InfoTile(
                      label: 'IMEI',
                      value: a.imeiNumber!.trim(),
                      mono: true,
                    ),
                  ),
              ],
            ),
          ],
          // ── Acknowledgement state / actions ──────────────────────────
          if (pending) ...[
            const SizedBox(height: 12),
            const ProNote(
              'Please review and acknowledge this assignment.',
              tone: ProNoteTone.warn,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ack(context, ref, false),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.dangerTint,
                      foregroundColor: AppColors.danger,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ack(context, ref, true),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
              ),
              child: Row(
                children: [
                  if (a.acknowledgementStatus == 'ACCEPTED')
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 15, color: AppColors.success),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Acknowledged',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _return(context, ref),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.assignment_return_rounded, size: 16),
                    label: const Text('Return'),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: () => _incident(context, ref),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.report_problem_rounded, size: 16),
                    label: const Text('Report'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact labelled fact cell used inside the asset card.
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
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
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              fontFamily: mono ? 'monospace' : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// White sheet listing the incident types (returns the raw type code).
class _IncidentTypeSheet extends StatelessWidget {
  const _IncidentTypeSheet({
    required this.assetName,
    required this.assetTag,
    required this.onPick,
  });
  final String assetName;
  final String assetTag;
  final ValueChanged<String> onPick;

  static const _labels = {'DAMAGE': 'Damage', 'LOST': 'Lost', 'STOLEN': 'Stolen'};
  static const _icons = {
    'DAMAGE': Icons.broken_image_outlined,
    'LOST': Icons.search_off_rounded,
    'STOLEN': Icons.gpp_bad_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Report an incident',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.35,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                assetTag.isEmpty ? assetName : '$assetName · $assetTag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
              const ProSectionHeader(title: 'Incident type', small: true),
              const SizedBox(height: 8),
              ProListGroup(
                children: [
                  for (final t in const ['DAMAGE', 'LOST', 'STOLEN'])
                    ProListRow(
                      leading: ProIconWell(icon: _icons[t]!, color: AppColors.danger),
                      title: _labels[t]!,
                      onTap: () => onPick(t),
                    ),
                ],
              ),
            ],
          ),
        ),
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
