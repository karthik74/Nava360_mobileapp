import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
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

  /// The message currently being replied to (null = not replying).
  ChatMessage? _replyingTo;

  /// The current "@..." token being typed (without the @); null = not tagging.
  String? _mentionQuery;

  /// Per-message keys so a reply-tap can scroll its original into view.
  final Map<int, GlobalKey> _msgKeys = {};
  /// Message to briefly flash-highlight after a reply-jump.
  int? _highlightMsgId;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _msgCtrl.addListener(_onTextChanged);
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
    final replyId = _replyingTo?.id;
    setState(() {
      _sending = true;
      _replyingTo = null;
    });
    _msgCtrl.clear();
    try {
      final sent = await ref
          .read(chatRepositoryProvider)
          .sendMessage(widget.conversation.id,
              content: text, replyToMessageId: replyId);
      // Show it right away (deduped against any later WebSocket echo).
      ref
          .read(chatMessagesProvider(widget.conversation.id).notifier)
          .addLocal(sent);
      _scrollToBottom();
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        // reverse: true → newest message sits at offset 0.
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scroll to (and briefly highlight) the original of a tapped reply. Works for
  /// messages currently built in the list; if the original is far up and not yet
  /// built, we nudge the user to scroll up so pagination can pull it in.
  void _jumpToMessage(int id) {
    final ctx = _msgKeys[id]?.currentContext;
    if (ctx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scroll up to load the original message')),
      );
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _highlightMsgId = id);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _highlightMsgId == id) {
        setState(() => _highlightMsgId = null);
      }
    });
  }

  // ── @mention tagging ─────────────────────────────────────────────────────────

  static final _mentionRegExp = RegExp(r'(^|\s)@([^\s@]*)$');

  /// Recomputes the active @token (the word being typed before the caret).
  void _onTextChanged() {
    final sel = _msgCtrl.selection;
    final text = _msgCtrl.text;
    String? query;
    if (sel.isValid && sel.start == sel.end && sel.start >= 0 && sel.start <= text.length) {
      final upToCaret = text.substring(0, sel.start);
      final m = _mentionRegExp.firstMatch(upToCaret);
      if (m != null) query = m.group(2);
    }
    if (query != _mentionQuery) {
      setState(() => _mentionQuery = query);
    }
  }

  /// Conversation members matching the current @token (self excluded).
  List<ChatContact> _mentionMatches() {
    if (_mentionQuery == null) return const [];
    final myId = ref.read(authUserProvider)?.employeeId;
    final q = _mentionQuery!.toLowerCase();
    return widget.conversation.members
        .where((c) => c.employeeId != myId)
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
        .take(20)
        .toList();
  }

  /// Replaces the active @token with "@<name> " and dismisses the picker.
  void _applyMention(ChatContact c) {
    final text = _msgCtrl.text;
    final caret = _msgCtrl.selection.start;
    if (caret < 0) {
      setState(() => _mentionQuery = null);
      return;
    }
    final upToCaret = text.substring(0, caret);
    final m = _mentionRegExp.firstMatch(upToCaret);
    if (m == null) {
      setState(() => _mentionQuery = null);
      return;
    }
    // Start index of the '@' (skip the leading whitespace group, if any).
    final atIndex = m.start + (m.group(1)?.length ?? 0);
    final insert = '@${c.name} ';
    final newText = text.replaceRange(atIndex, caret, insert);
    _msgCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIndex + insert.length),
    );
    setState(() => _mentionQuery = null);
  }

  // ── Emoji picker ───────────────────────────────────────────────────────────

  static const List<String> _emojis = [
    '😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🙂','🙃','😉','😌','😍','🥰',
    '😘','😗','😙','😚','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','😐','😑',
    '😶','😏','😒','🙄','😬','😯','😴','😪','😫','🥱','😮','😲','😳','🥺','😢','😭',
    '😤','😠','😡','🤬','😈','👿','💀','💩','🤡','👍','👎','👌','✌️','🤞','🙏','👏',
    '🙌','💪','🔥','✨','🎉','❤️','🧡','💛','💚','💙','💜','🖤','💯','✅','❌','⭐',
  ];

  void _showEmojiPicker() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: GridView.count(
            crossAxisCount: 8,
            shrinkWrap: true,
            children: _emojis
                .map((e) => InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertText(e);
                      },
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 24)),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  void _insertText(String text) {
    final sel = _msgCtrl.selection;
    final base = _msgCtrl.text;
    if (sel.isValid && sel.start >= 0) {
      final newText = base.replaceRange(sel.start, sel.end, text);
      _msgCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + text.length),
      );
    } else {
      _msgCtrl.text = base + text;
      _msgCtrl.selection =
          TextSelection.collapsed(offset: _msgCtrl.text.length);
    }
  }

  // ── Attachments ────────────────────────────────────────────────────────────

  void _pickAttachment() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _SheetAction(
              icon: Icons.photo_library_rounded,
              label: 'Photo / Gallery',
              color: AppColors.primary,
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
            _SheetAction(
              icon: Icons.photo_camera_rounded,
              label: 'Camera',
              color: AppColors.primary,
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
            _SheetAction(
              icon: Icons.insert_drive_file_rounded,
              label: 'Document',
              color: AppColors.primary,
              onTap: () { Navigator.pop(ctx); _pickDocument(); },
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Downscale to a 1920px max edge + re-encode (quality 82) so a multi-MB
      // phone photo uploads small — parity with the web compressImage().
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 82,
      );
      if (picked != null) {
        await _promptCaptionAndSend(picked.path, picked.name, isImage: true);
      }
    } catch (e) {
      _attachError(e);
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      if (path != null) {
        await _promptCaptionAndSend(path, result!.files.single.name,
            isImage: false);
      }
    } catch (e) {
      _attachError(e);
    }
  }

  /// Shows a preview with an optional caption, then sends. Returns early if the
  /// user backs out (caption screen popped with null).
  Future<void> _promptCaptionAndSend(String path, String name,
      {required bool isImage}) async {
    if (!mounted) return;
    final caption = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AttachmentCaptionScreen(
          filePath: path,
          fileName: name,
          isImage: isImage,
        ),
      ),
    );
    if (caption == null) return; // cancelled
    await _sendAttachment(path, name, caption: caption);
  }

  Future<void> _sendAttachment(String path, String name,
      {String? caption}) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final up = await repo.uploadAttachment(path, filename: name);
      final text = caption?.trim();
      final sent = await repo.sendMessage(
        widget.conversation.id,
        content: (text != null && text.isNotEmpty) ? text : null,
        attachmentFileId: up.fileId,
        attachmentName: up.name,
        attachmentContentType: up.contentType,
        attachmentSizeBytes: up.sizeBytes,
      );
      ref
          .read(chatMessagesProvider(widget.conversation.id).notifier)
          .addLocal(sent);
      _scrollToBottom();
    } catch (e) {
      _attachError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _attachError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attachment failed: $e')),
      );
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
              if (!msg.deletedForEveryone)
                _SheetAction(
                  icon: Icons.reply_rounded,
                  label: 'Reply',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyingTo = msg);
                  },
                ),
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
    final mentionMatches = _mentionMatches();

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

                        return Container(
                          key: _msgKeys.putIfAbsent(msg.id, () => GlobalKey()),
                          color: _highlightMsgId == msg.id
                              ? const Color(0xFF008069).withOpacity(0.12)
                              : Colors.transparent,
                          child: Column(
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
                                  onTapReply: msg.replyToId != null
                                      ? () => _jumpToMessage(msg.replyToId!)
                                      : null,
                                ),
                            ],
                          ),
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
              // ── @mention suggestions (shown above the input while tagging) ─
              if (mentionMatches.isNotEmpty)
                _MentionSuggestions(
                  matches: mentionMatches,
                  onSelect: _applyMention,
                ),
              // ── Reply preview (shown above the input while replying) ──────
              if (_replyingTo != null)
                _ReplyComposerBar(
                  message: _replyingTo!,
                  onCancel: () => setState(() => _replyingTo = null),
                ),
              // ── Input bar styled like WhatsApp ────────────────────────────
              _InputBar(
                controller: _msgCtrl,
                sending: _sending,
                onSend: _send,
                onEmoji: _showEmojiPicker,
                onAttach: _pickAttachment,
                onMention: () => _insertText('@'),
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
    this.onTapReply,
  });
  final ChatMessage msg;
  final bool isMine;
  final bool isRead;
  final bool showSender;
  final VoidCallback onLongPress;
  /// Tapping the quoted reply jumps to the original message (null = no original).
  final VoidCallback? onTapReply;

  /// Renders an inline image preview for image attachments, else a file chip.
  Widget _attachment(BuildContext context) {
    final url = _attachmentUrlOf(msg);
    final isImage = msg.type == ChatMessageType.IMAGE ||
        (msg.attachmentContentType?.startsWith('image/') ?? false);
    if (isImage && url != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () => _openImage(context, url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240, maxHeight: 260),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (c, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 160,
                        width: 200,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                errorBuilder: (c, e, s) => _fileChip(),
              ),
            ),
          ),
        ),
      );
    }
    return _fileChip();
  }

  Widget _fileChip() {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: (isMine ? Colors.black : const Color(0xFF008069)).withOpacity(0.06),
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
    );
  }

  void _openImage(BuildContext context, String url) {
    Navigator.of(context).push(PageRouteBuilder(
      fullscreenDialog: true,
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) =>
          _ImageViewerScreen(url: url, title: msg.attachmentName ?? 'Image'),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }

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
                    if (msg.replyToId != null)
                      _QuotedReply(msg: msg, isMine: isMine, onTap: onTapReply),
                    if (msg.attachmentName != null) ...[
                      _attachment(context),
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

/// Absolute URL for a message attachment (the /api/files GET is public, so
/// Image.network can load it directly, following the redirect to storage).
String? _attachmentUrlOf(ChatMessage m) {
  final path = m.attachmentUrl ??
      (m.attachmentFileId != null ? '/api/files/${m.attachmentFileId}' : null);
  if (path == null) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final base = Env.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  return base + (path.startsWith('/') ? path : '/$path');
}

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
    required this.onEmoji,
    required this.onAttach,
    required this.onMention,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onEmoji;
  final VoidCallback onAttach;
  final VoidCallback onMention;

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
                    onPressed: onEmoji,
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
                    icon: const Icon(Icons.alternate_email_rounded,
                        color: Color(0xFF8696A0), size: 21),
                    tooltip: 'Mention someone',
                    onPressed: onMention,
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded,
                        color: Color(0xFF8696A0), size: 22),
                    onPressed: onAttach,
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
// Quoted reply (inside a message bubble)
// ─────────────────────────────────────────────────────────────────────────────

class _QuotedReply extends StatelessWidget {
  const _QuotedReply({required this.msg, required this.isMine, this.onTap});
  final ChatMessage msg;
  final bool isMine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final deleted = msg.replyToDeleted;
    final preview =
        deleted ? 'This message was deleted' : (msg.replyToPreview ?? '');
    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF008069).withOpacity(0.07),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3.5, color: const Color(0xFF008069)),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.replyToSenderName ?? 'Reply',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF008069),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle:
                            deleted ? FontStyle.italic : FontStyle.normal,
                        color: const Color(0xFF54656F),
                      ),
                    ),
                  ],
                ),
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
// @mention suggestions (member picker above the composer)
// ─────────────────────────────────────────────────────────────────────────────

class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({required this.matches, required this.onSelect});
  final List<ChatContact> matches;
  final ValueChanged<ChatContact> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 60, endIndent: 12),
        itemBuilder: (_, i) {
          final c = matches[i];
          final hasDesignation =
              c.designation != null && c.designation!.isNotEmpty;
          return ListTile(
            dense: true,
            leading: UserAvatar(
              name: c.name,
              size: 36,
              radius: 18,
              imageUrl: Env.fileUrl(c.avatarUrl),
            ),
            title: Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111B21),
              ),
            ),
            subtitle: hasDesignation
                ? Text(
                    c.designation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF667781)),
                  )
                : null,
            onTap: () => onSelect(c),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reply preview bar above the composer
// ─────────────────────────────────────────────────────────────────────────────

class _ReplyComposerBar extends StatelessWidget {
  const _ReplyComposerBar({required this.message, required this.onCancel});
  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
          boxShadow: [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 2,
              offset: Offset(0, -1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: const Color(0xFF008069)),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Replying to ${message.senderName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF008069),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        message.previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF54656F),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 20, color: Color(0xFF8696A0)),
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attachment preview + caption (before sending)
// ─────────────────────────────────────────────────────────────────────────────

class _AttachmentCaptionScreen extends StatefulWidget {
  const _AttachmentCaptionScreen({
    required this.filePath,
    required this.fileName,
    required this.isImage,
  });
  final String filePath;
  final String fileName;
  final bool isImage;

  @override
  State<_AttachmentCaptionScreen> createState() =>
      _AttachmentCaptionScreenState();
}

class _AttachmentCaptionScreenState extends State<_AttachmentCaptionScreen> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF111B21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111B21),
        foregroundColor: Colors.white,
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.isImage
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Image.file(File(widget.filePath),
                          fit: BoxFit.contain),
                    )
                  : _FilePreviewCard(fileName: widget.fileName),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(8, 6, 8, mq.padding.bottom + 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _caption,
                        maxLines: null,
                        autofocus: false,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: const Color(0xFF008069),
                        style: const TextStyle(
                            fontSize: 14.5, color: Color(0xFF111B21)),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          border: InputBorder.none,
                          hintText: 'Add a caption…',
                          hintStyle: TextStyle(
                              color: Color(0xFF8696A0), fontSize: 14.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00A884),
                    shape: BoxShape.circle,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.pop(context, _caption.text),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePreviewCard extends StatelessWidget {
  const _FilePreviewCard({required this.fileName});
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(28),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_rounded,
              size: 64, color: Colors.white70),
          const SizedBox(height: 14),
          Text(
            fileName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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

/// Fullscreen image viewer: pinch-zoom + pan (InteractiveViewer), double-tap to
/// zoom to the tapped point, 90° rotate, and tap-to-toggle chrome. Mirrors the
/// web ImageViewer's interaction model, dependency-free.
class _ImageViewerScreen extends StatefulWidget {
  const _ImageViewerScreen({required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _zoomAnim;
  TapDownDetails? _lastTap;
  bool _chrome = true;
  int _quarterTurns = 0;

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _zoomAnim = Matrix4Tween(begin: _controller.value, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    )..addListener(() => _controller.value = _zoomAnim!.value);
    _anim.forward(from: 0);
  }

  void _handleDoubleTap() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed) {
      _animateTo(Matrix4.identity());
    } else {
      final pos = _lastTap?.localPosition ?? Offset.zero;
      const scale = 2.5;
      // Zoom toward the tapped point.
      final target = Matrix4.identity()
        ..translate(-pos.dx * (scale - 1), -pos.dy * (scale - 1))
        ..scale(scale);
      _animateTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Zoom + pan + rotate surface.
          GestureDetector(
            onTap: () => setState(() => _chrome = !_chrome),
            onDoubleTapDown: (d) => _lastTap = d,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 8,
              child: Center(
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  child: Image.network(
                    widget.url,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70),
                            ),
                          ),
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image_rounded,
                        color: Colors.white38, size: 48),
                  ),
                ),
              ),
            ),
          ),

          // Top chrome: back + title + rotate.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            top: _chrome ? 0 : -120,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top, left: 4, right: 4, bottom: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rotate',
                    icon: const Icon(Icons.rotate_right, color: Colors.white),
                    onPressed: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
