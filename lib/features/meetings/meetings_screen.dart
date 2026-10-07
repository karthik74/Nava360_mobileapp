import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'meetings_models.dart';
import 'meetings_repository.dart';

final myMeetingsProvider =
    FutureProvider.autoDispose<List<MeetingRecord>>((ref) {
  return ref.watch(meetingsRepositoryProvider).getMyMeetings();
});

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

bool _isUpcoming(MeetingRecord m) {
  try {
    final dt = DateTime.parse(m.startTime).toLocal();
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

class MeetingsScreen extends ConsumerStatefulWidget {
  const MeetingsScreen({super.key});

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen> {
  /// 0 = upcoming, 1 = past; null = pick automatically (upcoming if any).
  int? _tab;

  @override
  Widget build(BuildContext context) {
    final meetings = ref.watch(myMeetingsProvider);

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

    final list = meetings.valueOrNull;
    final total = list?.length ?? 0;
    final pastCount = total - upcomingCount;
    final tab = _tab ?? (upcomingCount > 0 || total == 0 ? 0 : 1);

    // Soonest upcoming meeting for the "Next up" card.
    MeetingRecord? next;
    if (list != null) {
      final ups = list.where(_isUpcoming).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      if (ups.isNotEmpty) next = ups.first;
    }

    String kpi(String Function() data) => meetings.when(
          data: (_) => data(),
          loading: () => '—',
          error: (_, __) => '0',
        );

    return Scaffold(
      appBar: AppBar(),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myMeetingsProvider),
        hero: ProHero(
          title: 'My meetings',
          subtitle: list == null
              ? 'Upcoming and recent discussions'
              : '$total meeting${total == 1 ? '' : 's'} · $upcomingCount upcoming',
          overlap: ProKpiStrip(
            cells: [
              ProKpi(value: kpi(() => '$total'), label: 'Total meetings'),
              ProKpi(
                value: kpi(() => '$upcomingCount'),
                label: 'Upcoming',
                valueColor: upcomingCount > 0 ? AppColors.warning : null,
              ),
              ProKpi(value: kpi(() => '$pastCount'), label: 'Completed'),
            ],
          ),
          children: [
            if (next != null) _NextUpCard(meeting: next),
            if (list != null && list.isNotEmpty)
              ProHeroSegmented(
                labels: ['Upcoming · $upcomingCount', 'Past · $pastCount'],
                selected: tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
          ],
        ),
        children: meetings.when(
          data: (list) {
            if (list.isEmpty) {
              return const [
                ProEmpty(
                  icon: Icons.event_busy_rounded,
                  title: 'No meetings scheduled.',
                ),
              ];
            }
            final isUp = tab == 0;
            final shown = list.where((m) => _isUpcoming(m) == isUp).toList()
              ..sort((a, b) => isUp
                  ? a.startTime.compareTo(b.startTime)
                  : b.startTime.compareTo(a.startTime));
            if (shown.isEmpty) {
              return [
                ProEmpty(
                  icon: Icons.event_busy_rounded,
                  title: isUp
                      ? 'No upcoming meetings.'
                      : 'No past meetings yet.',
                  action: OutlinedButton(
                    onPressed: () => setState(() => _tab = isUp ? 1 : 0),
                    child: Text(isUp ? 'See past meetings' : 'See upcoming'),
                  ),
                ),
              ];
            }
            // Group by day, keeping the sorted order.
            final groups = <String, List<MeetingRecord>>{};
            for (final m in shown) {
              groups.putIfAbsent(_formatDate(m.startTime), () => []).add(m);
            }
            return [
              ProSectionHeader(
                title: 'Scheduled meetings',
                subtitle:
                    '${isUp ? 'Soonest first' : 'Most recent first'} · ${shown.length} meeting${shown.length == 1 ? '' : 's'}',
              ),
              for (final g in groups.entries)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProSectionHeader(
                      title: '${g.key} · ${g.value.length} '
                          'meeting${g.value.length == 1 ? '' : 's'}',
                      small: true,
                    ),
                    const SizedBox(height: 10),
                    ProListGroup(
                      dividerIndent: 0,
                      children: [
                        for (final m in g.value) _MeetingRow(meeting: m),
                      ],
                    ),
                  ],
                ),
            ];
          },
          loading: () => const [AppLoadingBlock(height: 160)],
          error: (e, _) => [
            AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(myMeetingsProvider),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Next up" card on the deep hero.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.meeting});
  final MeetingRecord meeting;

  @override
  Widget build(BuildContext context) {
    final link = meeting.meetLink ?? meeting.googleEventLink;
    final loc = meeting.location;
    const meta = TextStyle(
      fontSize: 12.5,
      color: Color(0xE0FFFFFF),
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              ProPulseDot(color: AppColors.live, size: 7),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Next up',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
              ProHeroTag('Upcoming', tone: ProTagTone.warn),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meeting.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              height: 1.3,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month_rounded,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text(_formatDate(meeting.startTime), style: meta),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time_rounded,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text(
                    '${_formatTime(meeting.startTime)} - ${_formatTime(meeting.endTime)}',
                    style: meta,
                  ),
                ],
              ),
              if (loc != null && loc.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 14, color: Colors.white70),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        loc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (link != null && link.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.deep,
                ),
                onPressed: () => _launchUrlHelper(link),
                icon: const Icon(Icons.video_call_rounded, size: 20),
                label: const Text('Join meeting'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({required this.meeting});
  final MeetingRecord meeting;

  @override
  Widget build(BuildContext context) {
    final isUpcoming = _isUpcoming(meeting);
    final link = meeting.meetLink ?? meeting.googleEventLink;
    final hasLink = link != null && link.isNotEmpty;
    final loc = meeting.location;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Time column
            SizedBox(
              width: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(meeting.startTime),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(meeting.endTime),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            // Rail
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isUpcoming ? AppColors.primary : const Color(0xFFCFDADD),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          meeting.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.33,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.15,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      isUpcoming
                          ? ProPill.warn('Upcoming')
                          : ProPill.ok('Completed'),
                    ],
                  ),
                  if (meeting.description != null &&
                      meeting.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meeting.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  if ((loc != null && loc.isNotEmpty) ||
                      (hasLink && isUpcoming)) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (loc != null && loc.isNotEmpty) ...[
                          Icon(
                            hasLink
                                ? Icons.videocam_rounded
                                : Icons.location_on_rounded,
                            size: 15,
                            color: AppColors.inkSoft,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              loc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        if (hasLink && isUpcoming) ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () => _launchUrlHelper(link),
                            icon: const Icon(Icons.video_call_rounded, size: 17),
                            label: const Text('Join'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
