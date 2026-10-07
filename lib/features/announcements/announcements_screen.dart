import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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

/// "HR_NOTICE" → "HR notice", "URGENT" → "Urgent".
String _label(String code) {
  var t = code.replaceAll('_', ' ').toLowerCase();
  t = t.replaceFirst(RegExp(r'^hr\b'), 'HR');
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// Icon + tint per category (icon wells in the list).
(IconData, Color) _categoryLook(String category) {
  switch (category) {
    case 'HR_NOTICE':
      return (Icons.groups_rounded, const Color(0xFF00748C));
    case 'PAYROLL':
      return (Icons.account_balance_wallet_rounded, AppColors.success);
    case 'TRAINING':
      return (Icons.school_rounded, const Color(0xFF6B46A8));
    case 'COMPLIANCE':
      return (Icons.shield_rounded, const Color(0xFF4253A8));
    case 'POLICY_UPDATE':
      return (Icons.description_rounded, const Color(0xFF4253A8));
    case 'EMERGENCY':
      return (Icons.warning_amber_rounded, AppColors.danger);
    case 'HOLIDAY':
      return (Icons.event_rounded, const Color(0xFF9A5B00));
    case 'BRANCH_NOTICE':
      return (Icons.storefront_rounded, AppColors.info);
    default:
      return (Icons.campaign_rounded, const Color(0xFF43585D));
  }
}

/// Priority pill in the Pro tones.
Widget _priorityPill(String p) {
  switch (p) {
    case 'URGENT':
      return ProPill.bad(_label(p));
    case 'HIGH':
      return ProPill.warn(_label(p));
    case 'LOW':
      return ProPill.neutral(_label(p));
    default:
      return ProPill(
        _label(p),
        color: priorityColor(p),
        background:
            Color.alphaBlend(priorityColor(p).withOpacity(0.11), Colors.white),
      );
  }
}

/// Quick "show" filter behind the hero stat tiles (presentation-only).
enum _Show { all, unread, ack }

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _category = '';
  String _priority = '';
  _Show _show = _Show.all;

  static const _categories = [
    'GENERAL', 'HR_NOTICE', 'PAYROLL', 'TRAINING', 'COMPLIANCE',
    'POLICY_UPDATE', 'EMERGENCY', 'HOLIDAY', 'BRANCH_NOTICE',
  ];
  static const _priorities = ['LOW', 'NORMAL', 'HIGH', 'URGENT'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MyAnnouncement> _filter(List<MyAnnouncement> rows) {
    final q = _query.trim().toLowerCase();
    return rows.where((r) {
      if (_show == _Show.unread && r.read) return false;
      if (_show == _Show.ack && !(r.requiresAcknowledgement && !r.acknowledged)) {
        return false;
      }
      if (_category.isNotEmpty && r.category != _category) return false;
      if (_priority.isNotEmpty && r.priority != _priority) return false;
      if (q.isNotEmpty &&
          !('${r.title} ${r.description ?? ''}'.toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
  }

  void _toggleShow(_Show s) =>
      setState(() => _show = _show == s ? _Show.all : s);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myAnnouncementsProvider);
    final all = async.valueOrNull;
    final unread = all?.where((a) => !a.read).length ?? 0;
    final ackDue = all
            ?.where((a) => a.requiresAcknowledgement && !a.acknowledged)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myAnnouncementsProvider),
        hero: ProHero(
          title: 'Announcements',
          subtitle: all == null ? 'Company info' : 'Company info · $unread unread',
          overlap: _SearchField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
          ),
          children: [
            if (all != null)
              ProHeroStats(
                stats: [
                  ProStat(
                    label: 'Unread',
                    value: '$unread',
                    sub: 'new for you',
                    dot: const Color(0xFF4CC3DB),
                    selected: _show == _Show.unread,
                    onTap: () => _toggleShow(_Show.unread),
                  ),
                  ProStat(
                    label: 'Ack required',
                    value: '$ackDue',
                    sub: 'to acknowledge',
                    dot: const Color(0xFFF2B347),
                    selected: _show == _Show.ack,
                    onTap: () => _toggleShow(_Show.ack),
                  ),
                  ProStat(
                    label: 'All',
                    value: '${all.length}',
                    sub: 'announcements',
                    dot: const Color(0xFF9FB3B8),
                    onTap: () => setState(() => _show = _Show.all),
                  ),
                ],
              ),
          ],
        ),
        children: [
          // Category chips (tap a selected one again to clear it)
          ProChipBar(
            labels: ['All', for (final c in _categories) _label(c)],
            selected: _category.isEmpty ? 0 : _categories.indexOf(_category) + 1,
            onSelected: (i) => setState(() {
              if (i == 0) {
                _category = '';
              } else {
                final c = _categories[i - 1];
                _category = _category == c ? '' : c;
              }
            }),
            bleed: 0,
          ),
          // Priority chips
          ProChipBar(
            labels: ['Any priority', for (final p in _priorities) _label(p)],
            selected: _priority.isEmpty ? 0 : _priorities.indexOf(_priority) + 1,
            onSelected: (i) => setState(() {
              if (i == 0) {
                _priority = '';
              } else {
                final p = _priorities[i - 1];
                _priority = _priority == p ? '' : p;
              }
            }),
            bleed: 0,
          ),
          ...async.when(
            data: (rows) {
              final list = _filter(rows);
              if (list.isEmpty) {
                return [
                  const ProEmpty(
                    icon: Icons.notifications_none_rounded,
                    title: 'No announcements to show.',
                    message:
                        'Try another category or priority, or clear the search.',
                  ),
                ];
              }
              final pinned = list.where((a) => a.pinned).toList();
              final rest = list.where((a) => !a.pinned).toList();
              return [
                if (pinned.isNotEmpty) ...[
                  ProSectionHeader(
                    title: 'Pinned · ${pinned.length}',
                    small: true,
                  ),
                  ProListGroup(
                    children: [
                      for (final a in pinned) _AnnouncementRow(a: a),
                    ],
                  ),
                ],
                if (rest.isNotEmpty) ...[
                  ProSectionHeader(
                    title: 'Latest · ${rest.length}',
                    small: true,
                  ),
                  ProListGroup(
                    children: [
                      for (final a in rest) _AnnouncementRow(a: a),
                    ],
                  ),
                ],
              ];
            },
            loading: () => const [AppLoadingBlock(height: 160)],
            error: (e, _) => [
              AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(myAnnouncementsProvider),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Raised search field over the hero (ProSearchField look, keeps the
/// title-case formatter).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: AppColors.hairline),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: AppShadows.lifted,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, __) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const <TextInputFormatter>[TitleCaseTextFormatter()],
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Search announcements…',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: v.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementRow extends StatelessWidget {
  const _AnnouncementRow({required this.a});
  final MyAnnouncement a;

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = _categoryLook(a.category);
    final desc = a.description == null ? '' : _stripHtml(a.description!);
    final meta = [
      _label(a.category),
      if (a.publishedAt != null)
        DateFormat('d MMM yyyy, h:mm a').format(a.publishedAt!),
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/announcements/${a.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon well with the unread dot.
              SizedBox(
                width: 34,
                height: 34,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProIconWell(icon: icon, color: tint),
                    if (!a.read)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a.pinned)
                          const Padding(
                            padding: EdgeInsets.only(top: 2, right: 5),
                            child: Icon(Icons.push_pin_rounded,
                                size: 14, color: AppColors.pink),
                          ),
                        Expanded(
                          child: Text(
                            a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.33,
                              letterSpacing: -0.15,
                              fontWeight:
                                  a.read ? FontWeight.w500 : FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _priorityPill(a.priority),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        maxLines: 2,
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
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        if (a.requiresAcknowledgement) ...[
                          const SizedBox(width: 8),
                          a.acknowledged
                              ? ProPill.ok('Acknowledged')
                              : ProPill.warn('Ack required'),
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
