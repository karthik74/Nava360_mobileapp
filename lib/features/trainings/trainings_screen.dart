import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'training_test_screen.dart';
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

class _TrainingCard extends ConsumerWidget {
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

  void _openMaterials(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FutureBuilder<List<TrainingMaterial>>(
        future: ref.read(trainingsRepositoryProvider).getMaterials(enrollment.trainingId),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final mats = snap.data ?? const [];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Materials',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 12),
                if (mats.isEmpty)
                  const Text('No materials shared yet.',
                      style: TextStyle(color: AppColors.muted))
                else
                  ...mats.map((m) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          m.kind == 'LINK' ? Icons.link_rounded : Icons.description_rounded,
                          color: AppColors.primary,
                        ),
                        title: Text(m.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: AppColors.ink)),
                        subtitle: m.description != null && m.description!.isNotEmpty
                            ? Text(m.description!)
                            : (m.fileName != null ? Text(m.fileName!) : null),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () {
                          final base = Env.apiBaseUrl.endsWith('/')
                              ? Env.apiBaseUrl.substring(0, Env.apiBaseUrl.length - 1)
                              : Env.apiBaseUrl;
                          final url = m.kind == 'LINK' ? m.url : '$base${m.url}';
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                      )),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openTests(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => FutureBuilder<TrainingTestStatus>(
        future: ref.read(trainingsRepositoryProvider).getTestStatus(enrollment.trainingId),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final s = snap.data;
          if (s == null) {
            return const Padding(padding: EdgeInsets.all(24), child: Text('Unavailable.'));
          }

          void open(String section, String label) {
            Navigator.pop(sheetCtx);
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TrainingTestScreen(
                trainingId: enrollment.trainingId,
                section: section,
                titleLabel: label,
              ),
            ));
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tests & Feedback',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                if (s.improvement != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Pre ${s.preBestPercentage}% → Post ${s.postBestPercentage}% (${s.improvement! >= 0 ? '+' : ''}${s.improvement}%)',
                    style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 12),
                if (s.preQuestionCount > 0)
                  _testTile('Pre Test',
                      done: s.preAttempts > 0 && !s.allowRetake,
                      doneLabel: s.preBestPercentage != null ? '${s.preBestPercentage}%' : '✓',
                      onTap: () => open('PRE_TEST', 'Pre Test')),
                if (s.postQuestionCount > 0)
                  _testTile('Post Test',
                      done: s.postAttempts > 0 && !s.allowRetake,
                      doneLabel: s.postBestPercentage != null ? '${s.postBestPercentage}%' : '✓',
                      onTap: () => open('POST_TEST', 'Post Test')),
                if (s.feedbackQuestionCount > 0)
                  _testTile('Feedback',
                      done: s.feedbackSubmitted,
                      doneLabel: '✓',
                      onTap: () => open('FEEDBACK', 'Feedback')),
                if (s.preQuestionCount == 0 &&
                    s.postQuestionCount == 0 &&
                    s.feedbackQuestionCount == 0)
                  const Text('No tests or feedback for this training.',
                      style: TextStyle(color: AppColors.muted)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _testTile(String label,
      {required bool done, required String doneLabel, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(done ? Icons.check_circle_rounded : Icons.quiz_rounded,
          color: done ? AppColors.success : AppColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: done
          ? Text(doneLabel,
              style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))
          : const Icon(Icons.chevron_right_rounded),
      onTap: done ? null : onTap,
    );
  }

  Future<void> _markAttendance(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 70,
      maxWidth: 1080,
    );
    if (shot == null) return;

    double? lat;
    double? lng;
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      if (serviceOn && granted) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // GPS optional — proceed without it.
    }

    try {
      await ref.read(trainingsRepositoryProvider).markAttendance(
            trainingId: enrollment.trainingId,
            selfiePath: shot.path,
            latitude: lat,
            longitude: lng,
            deviceInfo: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Attendance marked ✓')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not mark attendance: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (enrollment.trainingMode == 'ONLINE' &&
              (enrollment.trainingMeetLink?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(enrollment.trainingMeetLink!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.videocam_rounded, size: 18),
                label: const Text('Join Google Meet'),
              ),
            ),
          ] else if (enrollment.trainingMode != 'ONLINE' &&
              (enrollment.trainingVenue?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 14, color: AppColors.inkSoft),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    enrollment.trainingVenue!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _openMaterials(context, ref),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Materials'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                onPressed: () => _openTests(context, ref),
                icon: const Icon(Icons.quiz_rounded, size: 18),
                label: const Text('Tests'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 16),
              if (!isDone)
                TextButton.icon(
                  onPressed: () => _markAttendance(context, ref),
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Attend'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppColors.success,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
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
