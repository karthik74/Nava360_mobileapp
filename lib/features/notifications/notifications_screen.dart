import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../tasks/task_detail_screen.dart';
import 'notifications_repository.dart';

/// The signed-in user's in-app alerts (task, PTP and FTOD), newest first.
final inAppNotificationsProvider =
    FutureProvider.autoDispose<List<InAppNotification>>(
  (ref) => ref.watch(notificationsRepositoryProvider).inApp(),
);

/// What an alert is about — derived from its route, same rule as the icon.
enum _Kind { task, ptp, ftod }

_Kind _kindOf(InAppNotification n) {
  final r = n.route ?? '';
  if (r.startsWith('/ptp')) return _Kind.ptp;
  if (r.startsWith('/ftod')) return _Kind.ftod;
  return _Kind.task;
}

/// Presentation-only filter over the list already loaded.
enum _Filter { all, unread, task, ptp, ftod }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _Filter _filter = _Filter.all;

  /// Tapping an alert marks it read and opens what it is about: its own route
  /// (a PTP alert → the PTP customer list, an FTOD digest → the FTOD
  /// distribution), else its task, else the task list.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    InAppNotification n,
  ) async {
    if (!n.read) {
      // Fire-and-forget: a failed mark-read must never block the navigation.
      ref.read(notificationsRepositoryProvider).markRead(n.id).catchError((Object _) {});
    }
    final route = n.route;
    final taskId = n.taskId;
    if (route != null) {
      await context.push(route);
    } else if (taskId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: taskId)),
      );
    } else {
      await context.push('/tasks');
    }
    // The screen may be gone by now (e.g. the opened route replaced it); a
    // disposed widget's ref throws.
    if (!context.mounted) return;
    ref.invalidate(inAppNotificationsProvider);
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
    } catch (_) {}
    // Back pressed while the PUT was in flight: a disposed widget's ref
    // throws.
    if (!mounted) return;
    ref.invalidate(inAppNotificationsProvider);
  }

  bool _inFilter(InAppNotification n) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.unread:
        return !n.read;
      case _Filter.task:
        return _kindOf(n) == _Kind.task;
      case _Filter.ptp:
        return _kindOf(n) == _Kind.ptp;
      case _Filter.ftod:
        return _kindOf(n) == _Kind.ftod;
    }
  }

  void _toggle(_Filter f) =>
      setState(() => _filter = _filter == f ? _Filter.all : f);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inAppNotificationsProvider);
    final items = async.asData?.value;
    final hasUnread = items?.any((n) => !n.read) ?? false;

    final total = items?.length ?? 0;
    final unread = items?.where((n) => !n.read).length ?? 0;
    int count(_Kind k) => items?.where((n) => _kindOf(n) == k).length ?? 0;
    int unreadOf(_Kind k) =>
        items?.where((n) => _kindOf(n) == k && !n.read).length ?? 0;

    return Scaffold(
      appBar: AppBar(),
      body: ProPage(
        onRefresh: () => ref.refresh(inAppNotificationsProvider.future),
        hero: ProHero(
          title: 'Notifications',
          subtitle: items == null
              ? 'Task, PTP and FTOD alerts'
              : (unread > 0
                  ? '$unread unread · $total alert${total == 1 ? '' : 's'}'
                  : 'All caught up · $total alert${total == 1 ? '' : 's'}'),
          actions: [
            if (hasUnread)
              _HeroPillButton(
                icon: Icons.done_all_rounded,
                label: 'Mark all read',
                onTap: _markAllRead,
              ),
          ],
          children: [
            if (items != null && items.isNotEmpty)
              ProHeroStats(
                stats: [
                  ProStat(
                    label: 'Unread',
                    value: '$unread',
                    sub: 'of $total',
                    dot: const Color(0xFF5FD0E6),
                    selected: _filter == _Filter.unread,
                    onTap: () => _toggle(_Filter.unread),
                  ),
                  ProStat(
                    label: 'Tasks',
                    value: '${count(_Kind.task)}',
                    sub: '${unreadOf(_Kind.task)} new',
                    dot: AppColors.live,
                    selected: _filter == _Filter.task,
                    onTap: () => _toggle(_Filter.task),
                  ),
                  ProStat(
                    label: 'PTP',
                    value: '${count(_Kind.ptp)}',
                    sub: '${unreadOf(_Kind.ptp)} new',
                    dot: const Color(0xFF9AA8F0),
                    selected: _filter == _Filter.ptp,
                    onTap: () => _toggle(_Filter.ptp),
                  ),
                  ProStat(
                    label: 'FTOD',
                    value: '${count(_Kind.ftod)}',
                    sub: '${unreadOf(_Kind.ftod)} new',
                    dot: const Color(0xFFC4A6EC),
                    selected: _filter == _Filter.ftod,
                    onTap: () => _toggle(_Filter.ftod),
                  ),
                ],
              ),
          ],
        ),
        children: async.when(
          loading: () => const [AppLoadingBlock()],
          error: (e, _) => [
            AppErrorPanel(
              message: '$e',
              onRetry: () => ref.invalidate(inAppNotificationsProvider),
            ),
          ],
          data: (items) {
            if (items.isEmpty) {
              return const [
                ProEmpty(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications yet.',
                  message: 'We will let you know when something happens.',
                ),
              ];
            }
            final shown = items.where(_inFilter).toList();
            final chips = ProChipBar(
              labels: const ['All', 'Unread', 'Tasks', 'PTP', 'FTOD'],
              counts: [
                total,
                unread,
                count(_Kind.task),
                count(_Kind.ptp),
                count(_Kind.ftod),
              ],
              selected: _filter.index,
              onSelected: (i) => setState(() => _filter = _Filter.values[i]),
              bleed: 0,
            );
            if (shown.isEmpty) {
              return [
                chips,
                ProEmpty(
                  icon: Icons.check_circle_outline_rounded,
                  title: _filter == _Filter.unread
                      ? 'All caught up'
                      : 'No ${_filterNoun(_filter)} alerts',
                  message: _filter == _Filter.unread
                      ? 'You have read every notification.'
                      : 'Nothing in this filter right now.',
                ),
              ];
            }
            // Group by day, keeping the newest-first order from the server.
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final yesterday = today.subtract(const Duration(days: 1));
            final groups = <String, List<InAppNotification>>{
              'Today': [],
              'Yesterday': [],
              'Earlier': [],
            };
            for (final n in shown) {
              final c = n.createdAt;
              final d = c == null ? null : DateTime(c.year, c.month, c.day);
              if (d == today) {
                groups['Today']!.add(n);
              } else if (d == yesterday) {
                groups['Yesterday']!.add(n);
              } else {
                groups['Earlier']!.add(n);
              }
            }
            return [
              chips,
              for (final g in groups.entries)
                if (g.value.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProSectionHeader(
                        title: '${g.key} · ${g.value.length}',
                        small: true,
                      ),
                      const SizedBox(height: 10),
                      ProListGroup(
                        children: [
                          for (final n in g.value)
                            _NotificationRow(
                              n: n,
                              onTap: () => _open(context, ref, n),
                            ),
                        ],
                      ),
                    ],
                  ),
            ];
          },
        ),
      ),
    );
  }

  static String _filterNoun(_Filter f) {
    switch (f) {
      case _Filter.task:
        return 'task';
      case _Filter.ptp:
        return 'PTP';
      case _Filter.ftod:
        return 'FTOD';
      case _Filter.unread:
        return 'unread';
      case _Filter.all:
        return '';
    }
  }
}

/// Translucent label button for the deep hero ("Mark all read").
class _HeroPillButton extends StatelessWidget {
  const _HeroPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n, required this.onTap});

  final InAppNotification n;
  final VoidCallback onTap;

  IconData get _icon {
    switch (_kindOf(n)) {
      case _Kind.ptp:
        return Icons.handshake_rounded;
      case _Kind.ftod:
        return Icons.calendar_month_rounded;
      case _Kind.task:
        return Icons.task_alt_rounded;
    }
  }

  Color get _tint {
    switch (_kindOf(n)) {
      case _Kind.ptp:
        return const Color(0xFF4253A8);
      case _Kind.ftod:
        return const Color(0xFF6B46A8);
      case _Kind.task:
        return AppColors.primary;
    }
  }

  String get _kindLabel {
    switch (_kindOf(n)) {
      case _Kind.ptp:
        return 'PTP';
      case _Kind.ftod:
        return 'FTOD';
      case _Kind.task:
        return 'Task';
    }
  }

  @override
  Widget build(BuildContext context) {
    final when = n.createdAt;
    final tint = _tint;
    return Material(
      color: n.read
          ? Colors.transparent
          : Color.alphaBlend(AppColors.primary.withOpacity(0.035), Colors.white),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProIconWell(icon: _icon, color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.33,
                              letterSpacing: -0.15,
                              fontWeight:
                                  n.read ? FontWeight.w500 : FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (when != null || !n.read) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!n.read) ...[
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (when != null)
                                  Text(
                                    DateFormat('h:mm a').format(when),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: n.read
                                          ? FontWeight.w500
                                          : FontWeight.w600,
                                      color: n.read
                                          ? AppColors.faint
                                          : AppColors.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (n.message.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        n.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkSoft,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        ProPill(
                          _kindLabel,
                          color: tint,
                          background: Color.alphaBlend(
                              tint.withOpacity(0.11), Colors.white),
                        ),
                        if (when != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('d MMM').format(when),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
