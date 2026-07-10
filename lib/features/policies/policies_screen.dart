import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'policies_models.dart';
import 'policies_repository.dart';

final myPoliciesProvider = FutureProvider.autoDispose<List<MyPolicy>>(
  (ref) => ref.watch(policiesRepositoryProvider).myPolicies(),
);

class PoliciesScreen extends ConsumerWidget {
  const PoliciesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPoliciesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Company Policies')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myPoliciesProvider),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: AppLoadingBlock(height: 200),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(myPoliciesProvider),
            ),
          ),
          data: (policies) {
            if (policies.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  AppEmptyState(
                    icon: Icons.description_outlined,
                    message: 'No policies are currently assigned to you.',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: policies.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PolicyCard(policy: policies[i]),
            );
          },
        ),
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.policy});
  final MyPolicy policy;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final meta = [
      policy.category ?? 'General',
      if (policy.versionNumber != null) 'v${policy.versionNumber}',
      if (policy.effectiveDate != null) 'Effective ${df.format(policy.effectiveDate!)}',
    ].join(' · ');

    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: () => context.push('/policies/${policy.id}'),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    policy.title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(
              label: policy.read ? 'Read' : 'Action needed',
              color: policy.read ? AppColors.success : AppColors.warning,
              icon: policy.read ? Icons.check_rounded : Icons.priority_high_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
