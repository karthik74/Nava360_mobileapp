import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'training_test_screen.dart';
import 'trainings_models.dart';
import 'trainings_repository.dart';

final myTrainingsProvider =
    FutureProvider.autoDispose<List<TrainingEnrollment>>((ref) {
  return ref.watch(trainingsRepositoryProvider).getMyTrainings();
});

const _progressColor = Color(0xFF4CC3DB);
const _enrolledColor = Color(0xFFF2B347);

/// 0 = enrolled, 1 = in progress, 2 = completed (same rules as the card).
int _bucket(TrainingEnrollment t) {
  final s = t.status.toUpperCase();
  if (s == 'COMPLETED') return 2;
  if (s == 'IN_PROGRESS' || s == 'ACTIVE') return 1;
  return 0;
}

String _pct(int n, int total) =>
    total == 0 ? '0% of courses' : '${(n / total * 100).round()}% of courses';

class TrainingsScreen extends ConsumerWidget {
  const TrainingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainings = ref.watch(myTrainingsProvider);
    final list = trainings.valueOrNull;

    int completedCount = 0;
    int progressCount = 0;
    int enrolledCount = 0;
    for (final t in list ?? const <TrainingEnrollment>[]) {
      switch (_bucket(t)) {
        case 2:
          completedCount++;
          break;
        case 1:
          progressCount++;
          break;
        default:
          enrolledCount++;
      }
    }
    final total = list?.length ?? 0;

    final body = <Widget>[
      const ProSectionHeader(
        title: 'Training modules',
        subtitle: 'Assigned certifications and professional learning',
      ),
      ...trainings.when<List<Widget>>(
        data: (list) {
          if (list.isEmpty) {
            return const [
              ProEmpty(
                icon: Icons.school_outlined,
                title: 'No trainings yet',
                message: 'No training modules assigned yet.',
              ),
            ];
          }
          final sorted = [...list]
            ..sort((a, b) => (b.trainingStartDate ?? '').compareTo(a.trainingStartDate ?? ''));
          return [for (final t in sorted) _TrainingCard(enrollment: t)];
        },
        loading: () => const [AppLoadingBlock(height: 160), AppLoadingBlock(height: 160)],
        error: (e, _) => [
          AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(myTrainingsProvider),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Trainings')),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myTrainingsProvider),
        hero: ProHero(
          title: 'My trainings',
          subtitle: list == null
              ? 'Assigned certifications and professional learning'
              : '$total assigned ${total == 1 ? 'course' : 'courses'} · $completedCount completed',
          children: [
            ProHeroStats(stats: [
              ProStat(
                label: 'Completed',
                value: list == null ? '—' : '$completedCount',
                sub: list == null ? null : _pct(completedCount, total),
                dot: AppColors.live,
              ),
              ProStat(
                label: 'In progress',
                value: list == null ? '—' : '$progressCount',
                sub: list == null ? null : _pct(progressCount, total),
                dot: _progressColor,
              ),
              ProStat(
                label: 'Enrolled',
                value: list == null ? '—' : '$enrolledCount',
                sub: list == null ? null : _pct(enrolledCount, total),
                dot: _enrolledColor,
              ),
            ]),
            if (total > 0)
              ProStackBar(parts: [
                MapEntry(completedCount.toDouble(), AppColors.live),
                MapEntry(progressCount.toDouble(), _progressColor),
                MapEntry(enrolledCount.toDouble(), _enrolledColor),
              ]),
          ],
        ),
        children: body,
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

  static String _human(String raw) {
    final s = raw.replaceAll('_', ' ').toLowerCase();
    return s.isEmpty ? raw : s[0].toUpperCase() + s.substring(1);
  }

  void _openMaterials(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => FutureBuilder<List<TrainingMaterial>>(
        future: ref.read(trainingsRepositoryProvider).getMaterials(enrollment.trainingId),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _Sheet(
              title: 'Materials',
              subtitle: enrollment.trainingTitle,
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final mats = snap.data ?? const [];
          return _Sheet(
            title: 'Materials',
            subtitle: enrollment.trainingTitle,
            child: mats.isEmpty
                ? const _SheetEmpty('No materials shared yet.')
                : ProListGroup(
                    children: [
                      for (final m in mats)
                        ProListRow(
                          leading: ProIconWell(
                            icon: m.kind == 'LINK'
                                ? Icons.link_rounded
                                : Icons.description_rounded,
                            color: AppColors.primary,
                          ),
                          title: m.title,
                          subtitle: m.description != null && m.description!.isNotEmpty
                              ? m.description!
                              : m.fileName,
                          chevron: false,
                          trailing: const Icon(Icons.open_in_new_rounded,
                              size: 18, color: AppColors.faint),
                          onTap: () {
                            final base = Env.apiBaseUrl.endsWith('/')
                                ? Env.apiBaseUrl.substring(0, Env.apiBaseUrl.length - 1)
                                : Env.apiBaseUrl;
                            final url = m.kind == 'LINK' ? m.url : '$base${m.url}';
                            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          },
                        ),
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
      builder: (sheetCtx) => FutureBuilder<TrainingTestStatus>(
        future: ref.read(trainingsRepositoryProvider).getTestStatus(enrollment.trainingId),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _Sheet(
              title: 'Tests & feedback',
              subtitle: enrollment.trainingTitle,
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final s = snap.data;
          if (s == null) {
            return _Sheet(
              title: 'Tests & feedback',
              subtitle: enrollment.trainingTitle,
              child: const _SheetEmpty('Unavailable.'),
            );
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

          final rows = <Widget>[
            if (s.preQuestionCount > 0)
              _testRow('Pre test',
                  questions: s.preQuestionCount,
                  done: s.preAttempts > 0 && !s.allowRetake,
                  doneLabel: s.preBestPercentage != null ? '${s.preBestPercentage}%' : '✓',
                  onTap: () => open('PRE_TEST', 'Pre Test')),
            if (s.postQuestionCount > 0)
              _testRow('Post test',
                  questions: s.postQuestionCount,
                  done: s.postAttempts > 0 && !s.allowRetake,
                  doneLabel: s.postBestPercentage != null ? '${s.postBestPercentage}%' : '✓',
                  onTap: () => open('POST_TEST', 'Post Test')),
            if (s.feedbackQuestionCount > 0)
              _testRow('Feedback',
                  questions: s.feedbackQuestionCount,
                  done: s.feedbackSubmitted,
                  doneLabel: '✓',
                  onTap: () => open('FEEDBACK', 'Feedback')),
          ];

          return _Sheet(
            title: 'Tests & feedback',
            subtitle: enrollment.trainingTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.improvement != null) ...[
                  ProNote(
                    'Pre ${s.preBestPercentage}% → Post ${s.postBestPercentage}% (${s.improvement! >= 0 ? '+' : ''}${s.improvement}%)',
                    tone: ProNoteTone.ok,
                    icon: Icons.trending_up_rounded,
                  ),
                  const SizedBox(height: 12),
                ],
                if (rows.isEmpty)
                  const _SheetEmpty('No tests or feedback for this training.')
                else
                  ProListGroup(children: rows),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _testRow(String label,
      {required int questions,
      required bool done,
      required String doneLabel,
      required VoidCallback onTap}) {
    return ProListRow(
      leading: ProIconWell(
        icon: done ? Icons.check_circle_rounded : Icons.quiz_rounded,
        color: done ? AppColors.success : AppColors.primary,
      ),
      title: label,
      subtitle: '$questions ${questions == 1 ? 'question' : 'questions'}',
      value: done ? doneLabel : null,
      valueColor: AppColors.success,
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

    final pill = isDone
        ? ProPill.ok('Completed')
        : isInProgress
            ? ProPill.info('In progress')
            : ProPill.warn('Enrolled');

    final mode = enrollment.trainingMode;
    final isOnline = mode == 'ONLINE';
    final hasMeet = isOnline && (enrollment.trainingMeetLink?.isNotEmpty ?? false);
    final hasVenue = !isOnline && (enrollment.trainingVenue?.isNotEmpty ?? false);

    final smallButton = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    );

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(icon: Icons.school_rounded, color: AppColors.primary, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enrollment.trainingTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 13, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${_formatDate(enrollment.trainingStartDate)} - ${_formatDate(enrollment.trainingEndDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              pill,
            ],
          ),
          if (mode != null || hasVenue) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mode != null)
                  _ModeChip(
                    icon: isOnline ? Icons.computer_rounded : Icons.groups_rounded,
                    label: _human(mode),
                  ),
                if (mode != null && hasVenue) const SizedBox(width: 10),
                if (hasVenue)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.location_on_outlined,
                                size: 14, color: AppColors.muted),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              enrollment.trainingVenue!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.38,
                                color: Color(0xFF43585D),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (hasMeet) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(enrollment.trainingMeetLink!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.videocam_rounded, size: 18),
              label: const Text('Join Google Meet'),
            ),
          ],
          if (isDone && enrollment.score > 0) ...[
            const SizedBox(height: 12),
            ProNote(
              'Score attained: ${enrollment.score}%',
              tone: ProNoteTone.ok,
              icon: Icons.emoji_events_rounded,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMaterials(context, ref),
                  style: smallButton,
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Materials', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openTests(context, ref),
                  style: smallButton,
                  icon: const Icon(Icons.quiz_rounded, size: 16),
                  label: const Text('Tests', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (!isDone) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _markAttendance(context, ref),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: const Text('Attend', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ],
          ),
          if (enrollment.feedback != null && enrollment.feedback!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Feedback from trainer',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: Color(0xFFD4DEE0), width: 2)),
                    ),
                    child: Text(
                      '“${enrollment.feedback!}”',
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Color(0xFF43585D),
                      ),
                    ),
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

/// Small neutral chip for the training mode (online / classroom).
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF43585D)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF43585D),
            ),
          ),
        ],
      ),
    );
  }
}

/// White bottom-sheet frame: handle, title + subtitle, close button.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 19,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.35,
                            color: AppColors.ink,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: const Color(0xFFEEF3F4),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.close_rounded, size: 18, color: AppColors.ink),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: AppColors.muted),
      ),
    );
  }
}
