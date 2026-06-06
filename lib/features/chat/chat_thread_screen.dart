import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'group_info_screen.dart';

class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load more when scrolled near the top (reversed list → position at max).
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 100) {
      final notifier =
          ref.read(chatMessagesProvider(widget.conversation.id).notifier);
      if (notifier.hasMore) {
        notifier.loadMore();
      }
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(widget.conversation.id, content: text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showDeleteSheet(ChatMessage msg, bool isMine) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadii.xl)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              _SheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Delete for me',
                color: AppColors.danger,
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(chatRepositoryProvider).deleteMessage(
                        widget.conversation.id,
                        msg.id,
                      );
                  // Remove locally.
                  ref
                      .read(chatMessagesProvider(widget.conversation.id).notifier)
                      .loadMore(); // Quick refresh.
                },
              ),
              if (isMine && !msg.deletedForEveryone)
                _SheetAction(
                  icon: Icons.delete_forever_rounded,
                  label: 'Delete for everyone',
                  color: AppColors.danger,
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(chatRepositoryProvider).deleteMessage(
                          widget.conversation.id,
                          msg.id,
                          forEveryone: true,
                        );
                  },
                ),
              _SheetAction(
                icon: Icons.close_rounded,
                label: 'Cancel',
                color: AppColors.muted,
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    final msgs = ref.watch(chatMessagesProvider(conv.id));
    final user = ref.watch(authUserProvider);
    final myEmpId = user?.employeeId;
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFE5DDD5),
      // ── App bar styled like WhatsApp ──────────────────────────────────
      appBar: PreferredSize(
        preferredSize:
            Size.fromHeight(mq.padding.top + AppChrome.appBarHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF008069), // WhatsApp Signature Green
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    onPressed: () => Navigator.pop(context),
                    color: Colors.white,
                  ),
                  const SizedBox(width: 2),
                  GestureDetector(
                    onTap: conv.isGroup
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroupInfoScreen(
                                    conversation: conv),
                              ),
                            )
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UserAvatar(
                          name: conv.title,
                          size: 36,
                          radius: conv.isGroup ? 12 : 18,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              conv.title,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              conv.isDirect
                                  ? (conv.otherOnline
                                      ? 'online'
                                      : 'offline')
                                  : '${conv.members.length} members',
                              style: TextStyle(
                                fontSize: 11,
                                color: conv.isDirect && conv.otherOnline
                                    ? const Color(0xFF25D366) // Bright green for online
                                    : Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (conv.isGroup)
                    IconButton(
                      icon: const Icon(Icons.info_outline_rounded,
                          size: 22),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupInfoScreen(conversation: conv),
                        ),
                      ),
                      color: Colors.white,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      // ── Body with Repeating WhatsApp doodles ─────────────────────────
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: _WhatsAppWallpaperPainter(),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: msgs.when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_rounded,
                                  color: Color(0xFF008069),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No messages yet',
                                style: TextStyle(
                                  color: Color(0xFF54656F),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Say hello! 👋',
                                style: TextStyle(
                                  color: Color(0xFF667781),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: _scrollCtrl,
                      reverse: true,
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        mq.padding.bottom + 8,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final idx = messages.length - 1 - i;
                        final msg = messages[idx];
                        final isMine = msg.senderId == myEmpId;

                        Widget? separator;
                        if (idx == 0 ||
                            !_isSameDay(
                              messages[idx].createdAt,
                              messages[idx - 1].createdAt,
                            )) {
                          separator = _DateSeparator(date: msg.createdAt);
                        }

                        bool isRead = false;
                        if (conv.isDirect &&
                            isMine &&
                            conv.otherLastReadAt != null) {
                          isRead =
                              !msg.createdAt.isAfter(conv.otherLastReadAt!);
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (separator != null) separator,
                            if (msg.isSystem)
                              _SystemBubble(msg: msg)
                            else
                              _MessageBubble(
                                msg: msg,
                                isMine: isMine,
                                isRead: isRead,
                                showSender: conv.isGroup && !isMine,
                                onLongPress: () =>
                                    _showDeleteSheet(msg, isMine),
                              ),
                          ],
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: AppLoadingBlock(height: 80),
                  ),
                  error: (err, _) => Center(
                    child: AppErrorPanel(message: err.toString()),
                  ),
                ),
              ),
              // ── Input bar styled like WhatsApp ────────────────────────────
              _InputBar(
                controller: _msgCtrl,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp Wallpaper Painter
// ─────────────────────────────────────────────────────────────────────────────

class _WhatsAppWallpaperPainter extends CustomPainter {
  const _WhatsAppWallpaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000).withOpacity(0.018)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    final stepX = 90.0;
    final stepY = 90.0;

    for (double x = 30; x < size.width; x += stepX) {
      for (double y = 30; y < size.height; y += stepY) {
        final cx = x + (y % 2 == 0 ? 25 : 0);
        final cy = y;

        final idx = ((cx / stepX).floor() + (cy / stepY).floor()) % 4;
        if (idx == 0) {
          // Phone outline
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(cx - 7, cy - 11, 14, 22),
              const Radius.circular(3),
            ),
            paint,
          );
          canvas.drawCircle(Offset(cx, cy + 8), 1.2, paint);
        } else if (idx == 1) {
          // Speech Bubble
          final path = Path()
            ..moveTo(cx - 8, cy - 6)
            ..lineTo(cx + 8, cy - 6)
            ..quadraticBezierTo(cx + 10, cy - 6, cx + 10, cy)
            ..quadraticBezierTo(cx + 10, cy + 6, cx, cy + 6)
            ..lineTo(cx - 5, cy + 10)
            ..lineTo(cx - 5, cy + 6)
            ..lineTo(cx - 8, cy + 6)
            ..quadraticBezierTo(cx - 10, cy + 6, cx - 10, cy)
            ..quadraticBezierTo(cx - 10, cy - 6, cx - 8, cy - 6);
          canvas.drawPath(path, paint);
        } else if (idx == 2) {
          // Simple Heart
          final path = Path()
            ..moveTo(cx, cy + 5)
            ..cubicTo(cx - 6, cy - 1, cx - 6, cy - 7, cx, cy - 7)
            ..cubicTo(cx + 6, cy - 7, cx + 6, cy - 1, cx, cy + 5);
          canvas.drawPath(path, paint);
        } else {
          // Simple Star
          final path = Path()
            ..moveTo(cx, cy - 7)
            ..lineTo(cx + 2, cy - 2)
            ..lineTo(cx + 7, cy - 2)
            ..lineTo(cx + 3, cy + 1)
            ..lineTo(cx + 5, cy + 6)
            ..lineTo(cx, cy + 3)
            ..lineTo(cx - 5, cy + 6)
            ..lineTo(cx - 3, cy + 1)
            ..lineTo(cx - 7, cy - 2)
            ..lineTo(cx - 2, cy - 2)
            ..close();
          canvas.drawPath(path, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble matching WhatsApp exactly
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.isMine,
    required this.isRead,
    required this.showSender,
    required this.onLongPress,
  });
  final ChatMessage msg;
  final bool isMine;
  final bool isRead;
  final bool showSender;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final deleted = msg.deletedForEveryone;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    
    // WhatsApp sharp tail styling: sharp corner at top-right for sent, top-left for received
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMine ? 12 : 0),
      topRight: Radius.circular(isMine ? 0 : 12),
      bottomLeft: const Radius.circular(12),
      bottomRight: const Radius.circular(12),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (showSender)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Text(
                msg.senderName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _senderColor(msg.senderName),
                ),
              ),
            ),
          GestureDetector(
            onLongPress: deleted ? null : onLongPress,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                // WhatsApp Light green sent, white received
                color: isMine 
                    ? (deleted ? const Color(0xFFE1F5FE) : const Color(0xFFD9FDD3))
                    : (deleted ? const Color(0xFFF0F2F5) : Colors.white),
                borderRadius: radius,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x15000000),
                    blurRadius: 1.5,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (deleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.block_rounded,
                            size: 13, color: Color(0xFF8696A0)),
                        const SizedBox(width: 4),
                        Text(
                          'This message was deleted',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: const Color(0xFF8696A0).withOpacity(0.9),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    if (msg.attachmentName != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: (isMine ? Colors.black : const Color(0xFF008069))
                              .withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              msg.type == ChatMessageType.IMAGE
                                  ? Icons.image_rounded
                                  : Icons.attach_file_rounded,
                              size: 16,
                              color: const Color(0xFF54656F),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                msg.attachmentName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111B21),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (msg.content != null && msg.content!.isNotEmpty)
                      Text(
                        msg.content!,
                        style: const TextStyle(
                          fontSize: 13.8,
                          color: Color(0xFF111B21), // WhatsApp dark text color
                          height: 1.3,
                        ),
                      ),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('h:mm a').format(msg.createdAt),
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFF667781), // WhatsApp status grey
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isMine && !deleted) ...[
                        const SizedBox(width: 3),
                        Icon(
                          isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 14,
                          color: isRead
                              ? const Color(0xFF53BDEB) // WhatsApp Blue double check ticks
                              : const Color(0xFF8696A0), // Grey ticks
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _senderColor(String name) {
    final colors = [
      const Color(0xFFE91E63),
      const Color(0xFF9C27B0),
      const Color(0xFF673AB7),
      const Color(0xFF3F51B5),
      const Color(0xFF2196F3),
      const Color(0xFF009688),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// System message (centered WhatsApp style)
// ─────────────────────────────────────────────────────────────────────────────

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.msg});
  final ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE1F3FD), // WhatsApp system light blue info card
            borderRadius: BorderRadius.circular(7.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 1,
                offset: Offset(0, 0.5),
              ),
            ],
          ),
          child: Text(
            msg.content ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF54656F),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date separator (WhatsApp rounded pill)
// ─────────────────────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target == today) return 'TODAY';
    if (target == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('d MMMM yyyy').format(date).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white, // WhatsApp clean white date bubble
            borderRadius: BorderRadius.circular(7.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 1,
                offset: Offset(0, 0.5),
              ),
            ],
          ),
          child: Text(
            _label(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF54656F),
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp Input Bar: Pill text container + separate green circle send button
// ─────────────────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        mq.padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // White Rounded Text Input Box with Emoji and Clip icon on left
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.sentiment_satisfied_alt_rounded,
                        color: Color(0xFF8696A0), size: 22),
                    onPressed: () {},
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: TextField(
                        controller: controller,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: const Color(0xFF008069),
                        cursorWidth: 1.5,
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: Color(0xFF111B21),
                        ),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          border: InputBorder.none,
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            color: Color(0xFF8696A0),
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded,
                        color: Color(0xFF8696A0), size: 22),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          // Green Circular Send Button on Right
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF00A884), // WhatsApp Send Button Green
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x20000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: sending ? null : onSend,
                borderRadius: BorderRadius.circular(22),
                child: Center(
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet action
// ─────────────────────────────────────────────────────────────────────────────

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    );
  }
}
