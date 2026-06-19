import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.assetName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
              StatusPill(label: a.assetTag, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 8),
          Text('Assigned ${_fmt(a.assignedDate)}'
              '${a.expectedReturnDate != null ? ' · return by ${_fmt(a.expectedReturnDate)}' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          const SizedBox(height: 12),
          if (pending)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _ack(context, ref, true),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _ack(context, ref, false),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              children: [
                if (a.acknowledgementStatus == 'ACCEPTED')
                  const StatusPill(label: 'Acknowledged', color: AppColors.success, icon: Icons.check_rounded),
                OutlinedButton.icon(
                  onPressed: () => _return(context, ref),
                  icon: const Icon(Icons.assignment_return_rounded, size: 16),
                  label: const Text('Return'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _incident(context, ref),
                  icon: const Icon(Icons.report_problem_rounded, size: 16),
                  label: const Text('Report'),
                ),
              ],
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
      content: TextField(controller: ctrl, autofocus: true, maxLines: 3, minLines: 1),
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
