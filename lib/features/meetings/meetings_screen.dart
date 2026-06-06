import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'meetings_models.dart';
import 'meetings_repository.dart';

final myMeetingsProvider =
    FutureProvider.autoDispose<List<MeetingRecord>>((ref) {
  return ref.watch(meetingsRepositoryProvider).getMyMeetings();
});

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(myMeetingsProvider);
    final mq = MediaQuery.of(context);

    int upcomingCount = 0;
    final now = DateTime.now();
    meetings.whenData((list) {
      for (final m in list) {
        try {
          final start = DateTime.parse(m.startTime).toLocal();
          if (start.isAfter(now)) upcomingCount++;
        } catch (_) {}
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
                            'My Meetings',
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
          onRefresh: () async => ref.invalidate(myMeetingsProvider),
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
                      label: 'Total meetings',
                      value: meetings.when(
                        data: (list) => list.length.toString(),
                        loading: () => '—',
                        error: (_, __) => '0',
                      ),
                      icon: Icons.meeting_room_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Upcoming',
                      value: meetings.when(
                        data: (_) => upcomingCount.toString(),
                        loading: () => '—',
                        error: (_, __) => '0',
                      ),
                      icon: Icons.upcoming_rounded,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const AppSectionHeader(
                title: 'Scheduled Meetings',
                subtitle: 'Upcoming and recent discussions',
                onDark: false,
              ),
              const SizedBox(height: 12),
              meetings.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.event_busy_rounded,
                      message: 'No meetings scheduled.',
                    );
                  }
                  final sorted = [...list]
                    ..sort((a, b) => b.startTime.compareTo(a.startTime));
                  return Column(
                    children: [
                      for (final m in sorted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MeetingCard(meeting: m),
                        ),
                    ],
                  );
                },
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myMeetingsProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.meeting});
  final MeetingRecord meeting;

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('jm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('EEE, d MMM').format(dt);
    } catch (_) {
      return iso;
    }
  }

  bool _isUpcoming() {
    try {
      final dt = DateTime.parse(meeting.startTime).toLocal();
      return dt.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<void> _launchUrlHelper(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUpcoming = _isUpcoming();
    final link = meeting.meetLink ?? meeting.googleEventLink;

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
                  meeting.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: isUpcoming ? 'Upcoming' : 'Completed',
                color: isUpcoming ? AppColors.warning : AppColors.success,
              ),
            ],
          ),
          if (meeting.description != null && meeting.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              meeting.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, size: 15, color: AppColors.inkSoft),
              const SizedBox(width: 6),
              Text(
                _formatDate(meeting.startTime),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.access_time_rounded, size: 15, color: AppColors.inkSoft),
              const SizedBox(width: 6),
              Text(
                '${_formatTime(meeting.startTime)} - ${_formatTime(meeting.endTime)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
          if (meeting.location != null && meeting.location!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 15, color: AppColors.inkSoft),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    meeting.location!,
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
          if (link != null && link.isNotEmpty && isUpcoming) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(AppRadii.md),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _launchUrlHelper(link),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.video_call_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Join Meeting',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
