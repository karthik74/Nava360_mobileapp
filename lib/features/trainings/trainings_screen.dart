import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'trainings_models.dart';
import 'trainings_repository.dart';

final myTrainingsProvider =
    FutureProvider.autoDispose<List<TrainingEnrollment>>((ref) {
  return ref.watch(trainingsRepositoryProvider).getMyTrainings();
});

class TrainingsScreen extends ConsumerWidget {
  const TrainingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainings = ref.watch(myTrainingsProvider);
    final mq = MediaQuery.of(context);

    int completedCount = 0;
    trainings.whenData((list) {
      for (final t in list) {
        if (t.status == 'COMPLETED') completedCount++;
      }
    });

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize:
              Size.fromHeight(mq.padding.top + AppChrome.appBarHeight),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: GlassBlur.chrome,
                sigmaY: GlassBlur.chrome,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.62),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.5)),
                  ),
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
                          child: Text(
                            'My Trainings',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
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
          onRefresh: () async => ref.invalidate(myTrainingsProvider),
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              mq.padding.bottom + 20,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Assigned courses',
                      value: trainings.when(
                        data: (list) => list.length.toString(),
                        loading: () => '—',
                        error: (_, __) => '0',
                      ),
                      icon: Icons.school_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Completed',
                      value: trainings.when(
                        data: (_) => completedCount.toString(),
                        loading: () => '—',
                        error: (_, __) => '0',
                      ),
                      icon: Icons.verified_user_rounded,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const AppSectionHeader(
                title: 'Training Modules',
                subtitle: 'Assigned certifications and professional learning',
                onDark: false,
              ),
              const SizedBox(height: 12),
              trainings.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.school_outlined,
                      message: 'No training modules assigned yet.',
                    );
                  }
                  final sorted = [...list]
                    ..sort((a, b) => (b.trainingStartDate ?? '').compareTo(a.trainingStartDate ?? ''));
                  return Column(
                    children: [
                      for (final t in sorted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TrainingCard(enrollment: t),
                        ),
                    ],
                  );
                },
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myTrainingsProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.enrollment});
  final TrainingEnrollment enrollment;

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = enrollment.status.toUpperCase();
    final isDone = status == 'COMPLETED';
    final isInProgress = status == 'IN_PROGRESS' || status == 'ACTIVE';

    final statusLabel = isDone
        ? 'COMPLETED'
        : isInProgress
            ? 'IN PROGRESS'
            : 'ENROLLED';

    final statusColor = isDone
        ? AppColors.success
        : isInProgress
            ? AppColors.primary
            : AppColors.warning;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  enrollment.trainingTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.inkSoft),
              const SizedBox(width: 6),
              Text(
                '${_formatDate(enrollment.trainingStartDate)} - ${_formatDate(enrollment.trainingEndDate)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const Spacer(),
              if (enrollment.trainingMode != null) ...[
                const Icon(Icons.computer_rounded, size: 14, color: AppColors.inkSoft),
                const SizedBox(width: 6),
                Text(
                  enrollment.trainingMode!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
          if (isDone && enrollment.score > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: AppColors.success.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Score attained: ${enrollment.score}%',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (enrollment.feedback != null && enrollment.feedback!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),
            const Text(
              'Feedback from Trainer:',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              enrollment.feedback!,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.muted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
