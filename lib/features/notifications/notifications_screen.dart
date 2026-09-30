import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../tasks/task_detail_screen.dart';
import 'notifications_repository.dart';

/// The signed-in user's in-app alerts (task, PTP and FTOD), newest first.
final inAppNotificationsProvider =
    FutureProvider.autoDispose<List<InAppNotification>>(
  (ref) => ref.watch(notificationsRepositoryProvider).inApp(),
);

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);
    final async = ref.watch(inAppNotificationsProvider);
    final hasUnread = async.asData?.value.any((n) => !n.read) ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          mq.padding.top + AppChrome.appBarHeight,
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: GlassBlur.chrome,
              sigmaY: GlassBlur.chrome,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(0),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Material(
                                color: Colors.white.withValues(alpha: 0.55),
                                child: InkWell(
                                  onTap: () =>
                                      Navigator.of(context).maybePop(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.55),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 20,
                                      color: AppColors.inkSoft,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (hasUnread)
                        TextButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(notificationsRepositoryProvider)
                                  .markAllRead();
                            } catch (_) {}
                            // Back pressed while the PUT was in flight: a
                            // disposed widget's ref throws.
                            if (!context.mounted) return;
                            ref.invalidate(inAppNotificationsProvider);
                          },
                          child: const Text('Mark all read'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: GlassBackdrop(
        child: RefreshIndicator(
          color: AppColors.primary,
          edgeOffset: mq.padding.top + AppChrome.appBarHeight,
          onRefresh: () => ref.refresh(inAppNotificationsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              mq.padding.top + AppChrome.appBarHeight + 12,
              16,
              mq.padding.bottom + 24,
            ),
            children: async.when(
              loading: () => const [AppLoadingBlock()],
              error: (e, _) => [
                AppErrorPanel(
                  message: '$e',
                  onRetry: () => ref.invalidate(inAppNotificationsProvider),
                ),
              ],
              data: (items) => items.isEmpty
                  ? const [
                      AppEmptyState(
                        icon: Icons.notifications_none_rounded,
                        message:
                            'No notifications yet.\nWe will let you know when something happens.',
                      ),
                    ]
                  : [
                      for (final n in items) ...[
                        _NotificationTile(
                          n: n,
                          onTap: () => _open(context, ref, n),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});

  final InAppNotification n;
  final VoidCallback onTap;

  IconData get _icon {
    final r = n.route ?? '';
    if (r.startsWith('/ptp')) return Icons.handshake_rounded;
    if (r.startsWith('/ftod')) return Icons.calendar_month_rounded;
    return Icons.task_alt_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final when = n.createdAt;
    return GlassCard(
      padding: EdgeInsets.zero,
      shadow: AppShadows.soft,
      border: n.read
          ? null
          : Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(_icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: n.read ? FontWeight.w600 : FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      if (n.message.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          n.message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (when != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('d MMM, h:mm a').format(when),
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!n.read)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4, left: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
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
