import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'announcement_detail_screen.dart';
import 'announcements_models.dart';
import 'announcements_repository.dart';

final myAnnouncementsProvider =
    FutureProvider.autoDispose<List<MyAnnouncement>>((ref) {
  return ref.watch(announcementsRepositoryProvider).getMyAnnouncements();
});

String _stripHtml(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  String _query = '';
  String _category = '';
  String _priority = '';

  static const _categories = [
    'GENERAL', 'HR_NOTICE', 'PAYROLL', 'TRAINING', 'COMPLIANCE',
    'POLICY_UPDATE', 'EMERGENCY', 'HOLIDAY', 'BRANCH_NOTICE',
  ];
  static const _priorities = ['LOW', 'NORMAL', 'HIGH', 'URGENT'];

  List<MyAnnouncement> _filter(List<MyAnnouncement> rows) {
    final q = _query.trim().toLowerCase();
    return rows.where((r) {
      if (_category.isNotEmpty && r.category != _category) return false;
      if (_priority.isNotEmpty && r.priority != _priority) return false;
      if (q.isNotEmpty &&
          !('${r.title} ${r.description ?? ''}'.toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myAnnouncementsProvider);
    final mq = MediaQuery.of(context);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                          child: Text('Announcements',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                  letterSpacing: -0.2)),
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
          onRefresh: () async => ref.invalidate(myAnnouncementsProvider),
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 20),
            children: [
              // Search
              TextField(
                onChanged: (v) => setState(() => _query = v),
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [TitleCaseTextFormatter()],
                decoration: InputDecoration(
                  hintText: 'Search announcements…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide: const BorderSide(color: AppColors.hairline),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Category chips
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('All', _category.isEmpty, () => setState(() => _category = '')),
                    for (final c in _categories)
                      _chip(c.replaceAll('_', ' '), _category == c,
                          () => setState(() => _category = _category == c ? '' : c)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Priority chips
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('Any priority', _priority.isEmpty, () => setState(() => _priority = '')),
                    for (final p in _priorities)
                      _chip(p, _priority == p,
                          () => setState(() => _priority = _priority == p ? '' : p),
                          color: priorityColor(p)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              async.when(
                data: (rows) {
                  final list = _filter(rows);
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.notifications_none_rounded,
                      message: 'No announcements to show.',
                    );
                  }
                  return Column(
                    children: [
                      for (final a in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AnnouncementCard(a: a),
                        ),
                    ],
                  );
                },
                loading: () => const AppLoadingBlock(height: 160),
                error: (e, _) => AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myAnnouncementsProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.withOpacity(0.14) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: selected ? c.withOpacity(0.4) : AppColors.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? c : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.a});
  final MyAnnouncement a;

  @override
  Widget build(BuildContext context) {
    final pc = priorityColor(a.priority);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      shadow: AppShadows.soft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: () => context.push('/announcements/${a.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!a.read)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                if (a.pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.push_pin_rounded, size: 14, color: AppColors.pink),
                  ),
                Expanded(
                  child: Text(
                    a.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(label: a.priority, color: pc),
              ],
            ),
            if (a.description != null && a.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _stripHtml(a.description!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                StatusPill(label: a.category.replaceAll('_', ' '), color: AppColors.muted),
                const Spacer(),
                if (a.requiresAcknowledgement)
                  StatusPill(
                    label: a.acknowledged ? 'Acknowledged' : 'Ack required',
                    color: a.acknowledged ? AppColors.success : AppColors.warning,
                    icon: a.acknowledged ? Icons.check_rounded : Icons.priority_high_rounded,
                  ),
              ],
            ),
            if (a.publishedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                DateFormat('d MMM yyyy, h:mm a').format(a.publishedAt!),
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
