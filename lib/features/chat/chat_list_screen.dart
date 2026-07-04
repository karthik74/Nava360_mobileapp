import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/secure_screen.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_thread_screen.dart';
import 'new_chat_screen.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

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

  @override
  Widget build(BuildContext context) {
    final convs = ref.watch(conversationsProvider);
    final mq = MediaQuery.of(context);

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(mq.padding.top + AppChrome.appBarHeight),
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
                    padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          onPressed: () => context.pop(),
                          color: AppColors.inkSoft,
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'Chats',
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
        body: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _ChatSearchBar(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // Conversation list
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: Colors.white.withOpacity(0.85),
                onRefresh: () async {
                  ref.read(conversationsProvider.notifier).refresh();
                },
                child: convs.when(
                  data: (list) {
                    final filtered = _query.isEmpty
                        ? list
                        : list
                            .where((c) => c.title
                                .toLowerCase()
                                .contains(_query.toLowerCase()))
                            .toList();
                    if (filtered.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          const SizedBox(height: 40),
                          AppEmptyState(
                            icon: Icons.chat_bubble_outline_rounded,
                            message: _query.isEmpty
                                ? 'No conversations yet.\nTap + to start chatting!'
                                : 'No conversations match "$_query"',
                          ),
                        ],
                      );
                    }
                    return ListView.builder(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(
                        12, 4, 12, 20,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _ConversationTile(
                        conversation: filtered[i],
                        onTap: () => _openThread(filtered[i]),
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: AppLoadingBlock(height: 120),
                    ),
                  ),
                  error: (err, _) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SizedBox(height: 40),
                      AppErrorPanel(
                        message: err.toString(),
                        onRetry: () =>
                            ref.read(conversationsProvider.notifier).refresh(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: Container(
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            shape: BoxShape.circle,
            boxShadow: AppShadows.lifted,
          ),
          child: FloatingActionButton(
            heroTag: 'new_chat_fab',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewChatScreen()),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
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
// Search bar
// ─────────────────────────────────────────────────────────────────────────────

class _ChatSearchBar extends StatelessWidget {
  const _ChatSearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.50),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: Colors.white.withOpacity(0.6)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.search_rounded, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  cursorColor: AppColors.primary,
                  cursorWidth: 1.5,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 13),
                    border: InputBorder.none,
                    hintText: 'Search conversations…',
                    hintStyle: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16,
                        color: AppColors.muted),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversation tile
// ─────────────────────────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shadow: AppShadows.soft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Row(
            children: [
              // Avatar with online dot
              _ChatAvatar(
                name: conversation.title,
                isGroup: conversation.isGroup,
                online: conversation.isDirect && conversation.otherOnline,
                imageUrl: Env.fileUrl(conversation.otherAvatarUrl),
              ),
              const SizedBox(width: 12),
              // Title + preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(conversation.lastMessageAt),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w500,
                            color:
                                hasUnread ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessagePreview ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: hasUnread
                                  ? AppColors.inkSoft
                                  : AppColors.muted,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: AppColors.heroGradient,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(
                              conversation.unreadCount > 99
                                  ? '99+'
                                  : '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Chat avatar (with online dot)
// ─────────────────────────────────────────────────────────────────────────────

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.name,
    this.isGroup = false,
    this.online = false,
    this.size = 44,
    this.imageUrl,
  });
  final String name;
  final bool isGroup;
  final bool online;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        UserAvatar(
          name: name,
          size: size,
          radius: isGroup ? 14 : 22,
          imageUrl: isGroup ? null : imageUrl,
        ),
        if (online)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        if (isGroup)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.group_rounded,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}
