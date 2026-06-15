import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'requisition_models.dart';
import 'requisition_repository.dart';

/// "My requisitions" — list of requisitions raised by the current user, with a
/// button to create a new one. Gated to users with REQUISITION_CREATE.
class RequisitionsScreen extends ConsumerWidget {
  const RequisitionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRequisitionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Job requisitions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>('/requisitions/new');
          if (created == true) ref.invalidate(myRequisitionsProvider);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New requisition'),
      ),
      body: GlassBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(myRequisitionsProvider),
            child: async.when(
              loading: () => ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              ),
              error: (e, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 8),
                  AppErrorPanel(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(myRequisitionsProvider),
                  ),
                ],
              ),
              data: (items) {
                if (items.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: const [
                      SizedBox(height: 60),
                      AppEmptyState(
                        icon: Icons.work_outline_rounded,
                        message:
                            'No requisitions yet.\nTap "New requisition" to '
                            'raise one.',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _RequisitionCard(item: items[i]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RequisitionCard extends StatelessWidget {
  const _RequisitionCard({required this.item});
  final RequisitionSummary item;

  @override
  Widget build(BuildContext context) {
    final tone = item.statusTone;
    final meta = <String>[
      if (item.department != null && item.department!.isNotEmpty)
        item.department!,
      '${item.numberOfPositions} '
          '${item.numberOfPositions == 1 ? 'position' : 'positions'}',
      if (item.branchLabel != null && item.branchLabel!.isNotEmpty)
        item.branchLabel!,
    ].join(' · ');

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              meta,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (item.priority != null) ...[
                StatusPill(
                  label: item.priority!.label,
                  color: item.priority!.color,
                  icon: Icons.flag_rounded,
                ),
                const SizedBox(width: 8),
              ],
              if (item.experienceLevel != null)
                StatusPill(
                  label: item.experienceLevel!.label,
                  color: AppColors.accent,
                  icon: Icons.trending_up_rounded,
                ),
              const Spacer(),
              if (item.targetDate != null)
                Text(
                  'Target ${item.targetDate}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
