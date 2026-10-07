import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/secure_screen.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_thread_screen.dart';
import 'new_chat_screen.dart';

/// Quick filters behind the hero stat tiles (presentation-only, applied to
/// the conversation list already in memory).
enum _ChatFilter { all, unread, direct, group }

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _ChatFilter _filter = _ChatFilter.all;

  @override
  void initState() {
    super.initState();
    // Conversation previews are confidential too — no screenshots here either.
    SecureScreen.acquire();
  }

  @override
  void dispose() {
    SecureScreen.release();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleFilter(_ChatFilter f) =>
      setState(() => _filter = _filter == f ? _ChatFilter.all : f);

  bool _inFilter(Conversation c) {
    switch (_filter) {
      case _ChatFilter.unread:
        return c.unreadCount > 0;
      case _ChatFilter.direct:
        return !c.isGroup;
      case _ChatFilter.group:
        return c.isGroup;
      case _ChatFilter.all:
        return true;
    }
  }

  String get _filterName {
    switch (_filter) {
      case _ChatFilter.unread:
        return 'Unread';
      case _ChatFilter.direct:
        return 'Direct messages';
      case _ChatFilter.group:
        return 'Groups';
      case _ChatFilter.all:
        return 'All conversations';
    }
  }

  void _openNewChat() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final convs = ref.watch(conversationsProvider);
    final mq = MediaQuery.of(context);
    final all = convs.valueOrNull;

    // Hero numbers, built from the list the screen already loads.
    String? subtitle;
    List<ProStat>? stats;
    if (all != null) {
      final unreadChats = all.where((c) => c.unreadCount > 0).length;
      final unreadMsgs = all.fold<int>(0, (a, c) => a + c.unreadCount);
      final directs = all.where((c) => !c.isGroup).toList();
      final onlineNow = directs.where((c) => c.otherOnline).length;
      subtitle = '${all.length} conversation${all.length == 1 ? '' : 's'}'
          ' · $unreadChats unread';
      stats = [
        ProStat(
          label: 'Unread',
          value: '$unreadChats',
          sub: '$unreadMsgs new message${unreadMsgs == 1 ? '' : 's'}',
          dot: AppColors.live,
          selected: _filter == _ChatFilter.unread,
          onTap: () => _toggleFilter(_ChatFilter.unread),
        ),
        ProStat(
          label: 'Direct',
          value: '${directs.length}',
          sub: '$onlineNow online now',
          dot: const Color(0xFF7FD3E3),
          selected: _filter == _ChatFilter.direct,
          onTap: () => _toggleFilter(_ChatFilter.direct),
        ),
        ProStat(
          label: 'Groups',
          value: '${all.length - directs.length}',
          sub: 'of ${all.length} chats',
          dot: const Color(0xFFF2B347),
          selected: _filter == _ChatFilter.group,
          onTap: () => _toggleFilter(_ChatFilter.group),
        ),
      ];
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Chats is a bottom-nav tab, so HomeShell supplies the deep header
      // (title/hamburger/avatar) and the floating tab bar — the hero below
      // continues that header.
      body: ProPage(
        topInset: mq.padding.top,
        clearNav: true,
        onRefresh: () async {
          ref.read(conversationsProvider.notifier).refresh();
        },
        hero: ProHero(
          title: 'Chats',
          subtitle: subtitle,
          actions: [
            ProHeroIconButton(
              icon: Icons.edit_square,
              tooltip: 'New chat',
              onTap: _openNewChat,
            ),
          ],
          overlap: _ChatSearchField(
            controller: _searchCtrl,
            hint: 'Search conversations',
            onChanged: (v) => setState(() => _query = v),
          ),
          children: [
            if (stats != null) ProHeroStats(stats: stats),
          ],
        ),
        children: convs.when(
          data: (list) {
            final q = _query.toLowerCase();
            final filtered = list
                .where(_inFilter)
                .where((c) => _query.isEmpty || c.title.toLowerCase().contains(q))
                .toList();
            if (filtered.isEmpty) {
              return [
                ProEmpty(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: _query.isNotEmpty
                      ? 'No conversations match "$_query"'
                      : (_filter == _ChatFilter.all
                          ? 'No conversations yet.'
                          : 'Nothing in ${_filterName.toLowerCase()} right now.'),
                  message: _query.isEmpty
                      ? 'Tap the new-chat button above to start one.'
                      : null,
                ),
              ];
            }
            return [
              ProSectionHeader(
                title: '$_filterName · ${filtered.length}',
                small: true,
              ),
              ProListGroup(
                dividerIndent: 70,
                children: [
                  for (final c in filtered)
                    _ConversationRow(
                      conversation: c,
                      onTap: () => _openThread(c),
                    ),
                ],
              ),
            ];
          },
          loading: () => const [AppLoadingBlock(height: 120)],
          error: (err, _) => [
            AppErrorPanel(
              message: err.toString(),
              onRetry: () =>
                  ref.read(conversationsProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
      // New chat lives in the hero (pencil button) — no duplicate FAB
      // floating over the list and the tab bar.
    );
  }

  void _openThread(Conversation conv) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(conversation: conv),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search field (ProSearchField look, keeps the title-case formatter)
// ─────────────────────────────────────────────────────────────────────────────

class _ChatSearchField extends StatelessWidget {
  const _ChatSearchField({
    required this.controller,
    required this.onChanged,
    required this.hint,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

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
            hintText: hint,
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

// ─────────────────────────────────────────────────────────────────────────────
// Conversation row
// ─────────────────────────────────────────────────────────────────────────────

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.onTap});
  final Conversation conversation;
  final VoidCallback onTap;

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return DateFormat.Hm().format(dt);
    if (diff.inDays < 7) return DateFormat.E().format(dt);
    return DateFormat('d MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    final time = _formatTime(conversation.lastMessageAt);
    final preview = conversation.lastMessagePreview ?? '';
    return ProListRow(
      leading: _ChatAvatar(
        name: conversation.title,
        isGroup: conversation.isGroup,
        online: conversation.isDirect && conversation.otherOnline,
        imageUrl: Env.fileUrl(conversation.otherAvatarUrl),
      ),
      title: conversation.title,
      subtitle: preview.isEmpty ? null : preview,
      chevron: false,
      onTap: onTap,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (time.isNotEmpty)
            Text(
              time,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                color: hasUnread ? AppColors.primary : AppColors.faint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 5),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                conversation.unreadCount > 99
                    ? '99+'
                    : '${conversation.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat avatar — ProAvatar squircle, photo on top when there is one, lime
// online dot, small group badge.
// ─────────────────────────────────────────────────────────────────────────────

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.name,
    this.isGroup = false,
    this.online = false,
    this.imageUrl,
  });
  final String name;
  final bool isGroup;
  final bool online;
  final String? imageUrl;

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final url = isGroup ? null : imageUrl;
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ProAvatar(name: name, size: _size),
          if (url != null && url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(_size * 0.31),
              child: Image.network(
                url,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                // Initials underneath stay visible while loading / on error.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
              ),
            ),
          if (online && !isGroup)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.live,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
          if (isGroup)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.group_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
