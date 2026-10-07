import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/secure_screen.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'chat_socket_service.dart';
import 'forward_message_screen.dart';
import 'group_info_screen.dart';

class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversation,
    this.initialReplyTo,
  });
  final Conversation conversation;

  /// Pre-seeded reply quote — used by "Reply Privately", which opens the DM
  /// with the sender and quotes their (possibly group) message there.
  final ChatMessage? initialReplyTo;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  /// Set once the open group vanishes from the live conversation list (an admin
  /// deleted it, or we were removed). We swap the body for a notice instead of
  /// popping, so a concurrent pop from Group Info can't over-pop the stack.
  bool _conversationGone = false;

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

  /// The conversation's single pinned message (null = nothing pinned).
  PinnedMessage? _pinned;
  StreamSubscription? _pinSub;

  @override
  void initState() {
    super.initState();
    // Chat is confidential — block screenshots/recording while it's open
    // (covers the thread, attachments and the fullscreen image viewer).
    SecureScreen.acquire();
    _scrollCtrl.addListener(_onScroll);
    _msgCtrl.addListener(_onTextChanged);
    _replyingTo = widget.initialReplyTo;
    _loadPinned();
    // REACTION events are applied by the messages notifier; the pin banner is
    // screen state, so PIN events are handled here.
    _pinSub = ref.read(chatSocketProvider).stream.listen(_onPinEvent);
  }

  @override
  void dispose() {
    SecureScreen.release();
    _pinSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPinned() async {
    try {
      final p = await ref
          .read(chatRepositoryProvider)
          .getPinnedMessage(widget.conversation.id);
      if (mounted) setState(() => _pinned = p);
    } catch (_) {
      // Banner is best-effort; the thread still works without it.
    }
  }

  void _onPinEvent(Map<String, dynamic> event) {
    if (event['type'] != 'PIN') return;
    if ((event['conversationId'] as num?)?.toInt() != widget.conversation.id) {
      return;
    }
    final p = event['pinned'];
    if (mounted) {
      setState(() => _pinned =
          p == null ? null : PinnedMessage.fromJson(p as Map<String, dynamic>));
    }
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
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProSheet(
        title: 'Emoji',
        scrollable: true,
        children: [
          GridView.count(
            crossAxisCount: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _emojis
                .map((e) => InkWell(
                      borderRadius: BorderRadius.circular(12),
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
        ],
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
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProSheet(
        title: 'Attach',
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AttachTile(
                    icon: Icons.photo_library_rounded,
                    label: 'Photo / Gallery',
                    color: AppColors.primary,
                    onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AttachTile(
                    icon: Icons.photo_camera_rounded,
                    label: 'Camera',
                    color: const Color(0xFF4253A8),
                    onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AttachTile(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'Document',
                    color: AppColors.danger,
                    onTap: () { Navigator.pop(ctx); _pickDocument(); },
                  ),
                ),
              ],
            ),
          ),
        ],
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

  // ── Message options (long-press), reactions & pin — mirrors the web menu ───

  /// WhatsApp's quick-reaction set (same as the web EmojiPicker).
  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  String? _myReactionOf(ChatMessage msg) {
    final myId = ref.read(authUserProvider)?.employeeId;
    for (final r in msg.reactions) {
      if (r.employeeId == myId) return r.emoji;
    }
    return null;
  }

  /// One reaction per person: same emoji removes it, a different one replaces it.
  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    final repo = ref.read(chatRepositoryProvider);
    try {
      final updated = _myReactionOf(msg) == emoji
          ? await repo.removeReaction(msg.id)
          : await repo.addReaction(msg.id, emoji);
      // The REACTION socket echo also lands; both apply the same full snapshot.
      ref
          .read(chatMessagesProvider(widget.conversation.id).notifier)
          .applyReactions(msg.id, updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to react: $e')),
        );
      }
    }
  }

  /// Long-pressing a reaction chip lists who reacted (hover tooltip on web).
  void _showReactors(ChatMessage msg) {
    final myId = ref.read(authUserProvider)?.employeeId;
    final byEmoji = <String, List<String>>{};
    for (final r in msg.reactions) {
      byEmoji
          .putIfAbsent(r.emoji, () => [])
          .add(r.employeeId == myId ? 'You' : r.employeeName);
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ProSheet(
        title: 'Reactions',
        scrollable: true,
        children: [
          _SheetGroup(
            children: [
              for (final entry in byEmoji.entries)
                for (final name in entry.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        Text(entry.key, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (name == 'You')
                          const Text(
                            'Tap your emoji to remove',
                            style:
                                TextStyle(fontSize: 12, color: AppColors.faint),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pin (or unpin, when it's already the pinned one) — one pin per conversation.
  Future<void> _togglePin(ChatMessage msg) async {
    final repo = ref.read(chatRepositoryProvider);
    try {
      if (_pinned?.messageId == msg.id) {
        await repo.unpinMessage(widget.conversation.id);
        if (mounted) setState(() => _pinned = null);
      } else {
        final p = await repo.pinMessage(widget.conversation.id, msg.id);
        if (mounted) setState(() => _pinned = p);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pin: $e')),
        );
      }
    }
  }

  /// Open the forward picker; toast once the copies are sent.
  Future<void> _forward(ChatMessage msg) async {
    final count = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => ForwardMessageScreen(message: msg)),
    );
    if (!mounted || count == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Forwarded to $count chat${count == 1 ? '' : 's'}')),
    );
  }

  /// "Reply Privately" / "Message": open (or create) the DM with the sender.
  /// A reply-privately quote of the original rides along when [replyPrivately].
  Future<void> _openDirectWithSender(ChatMessage msg,
      {required bool replyPrivately}) async {
    final conv = widget.conversation;
    // Already in the DM with this sender — replying here IS private.
    if (conv.isDirect && conv.otherEmployeeId == msg.senderId) {
      if (replyPrivately) setState(() => _replyingTo = msg);
      return;
    }
    try {
      final dm =
          await ref.read(chatRepositoryProvider).getOrCreateDirect(msg.senderId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            conversation: dm,
            initialReplyTo: replyPrivately ? msg : null,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open chat: $e')),
        );
      }
    }
  }

  /// Long-press options sheet — quick reactions on top, then the same actions
  /// as the web context menu (Reply Privately / Message / React / Pin) plus the
  /// existing delete actions.
  void _showMessageOptions(ChatMessage msg, bool isMine) {
    final myReaction = _myReactionOf(msg);
    final isPinned = _pinned?.messageId == msg.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ProSheet(
        scrollable: true,
        children: [
          // ── The message being acted on ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairlineSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isMine ? 'You' : msg.senderName} · '
                  '${DateFormat('h:mm a').format(msg.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  msg.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          // ── Quick reactions (React) ─────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final emoji in _quickReactions)
                Material(
                  color: myReaction == emoji
                      ? AppColors.primary
                      : const Color(0xFFF1F4F5),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _toggleReaction(msg, emoji);
                    },
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          _SheetGroup(
            children: [
              _SheetAction(
                icon: Icons.reply_rounded,
                label: 'Reply',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _replyingTo = msg);
                },
              ),
              if (!msg.deletedForEveryone &&
                  !msg.isSystem &&
                  msg.type.name != 'ACTION_CARD')
                _SheetAction(
                  icon: Icons.forward_rounded,
                  label: 'Forward',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _forward(msg);
                  },
                ),
              if (!isMine) ...[
                _SheetAction(
                  icon: Icons.person_outline_rounded,
                  label: 'Reply privately',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openDirectWithSender(msg, replyPrivately: true);
                  },
                ),
                _SheetAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Message ${msg.senderName}',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openDirectWithSender(msg, replyPrivately: false);
                  },
                ),
              ],
              _SheetAction(
                icon: isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                label: isPinned ? 'Unpin' : 'Pin',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(msg);
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
                      .read(chatMessagesProvider(widget.conversation.id)
                          .notifier)
                      .loadMore(); // Quick refresh.
                },
              ),
              if (isMine)
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
            ],
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _goneScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          widget.conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ProEmpty(
            icon: Icons.group_off_rounded,
            title: 'This group is no longer available',
            message:
                'It was deleted by a group admin, or you were removed from it.',
            action: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to chats'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the live list copy (renames / membership changes arrive over the
    // socket); fall back to the conversation we were opened with (drafts).
    final convId = widget.conversation.id;
    ref.listen<AsyncValue<List<Conversation>>>(conversationsProvider, (prev, next) {
      if (!widget.conversation.isGroup || _conversationGone) return;
      final was = prev?.valueOrNull?.any((c) => c.id == convId) ?? false;
      final now = next.valueOrNull?.any((c) => c.id == convId) ?? true;
      if (was && !now && mounted) setState(() => _conversationGone = true);
    });
    if (_conversationGone) return _goneScaffold(context);
    final conv = ref
            .watch(conversationsProvider)
            .valueOrNull
            ?.where((c) => c.id == convId)
            .firstOrNull ??
        widget.conversation;
    final msgs = ref.watch(chatMessagesProvider(conv.id));
    final user = ref.watch(authUserProvider);
    final myEmpId = user?.employeeId;
    final mq = MediaQuery.of(context);
    final mentionMatches = _mentionMatches();

    void openGroupInfo() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoScreen(conversation: conv),
          ),
        );
    final online = conv.isDirect && conv.otherOnline;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // ── Deep header: back, avatar + name + presence, group info ─────────
      appBar: PreferredSize(
        preferredSize:
            Size.fromHeight(mq.padding.top + AppChrome.appBarHeight + 8),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: ProDeepSurface(
            padding: EdgeInsets.zero,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: AppChrome.appBarHeight + 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      ProHeroIconButton(
                        icon: Icons.chevron_left_rounded,
                        iconSize: 24,
                        tooltip: 'Back',
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: conv.isGroup ? openGroupInfo : null,
                          child: Row(
                            children: [
                              _HeaderAvatar(
                                name: conv.title,
                                ringColor: online || conv.isGroup
                                    ? AppColors.live.withOpacity(0.85)
                                    : Colors.white.withOpacity(0.28),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      conv.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        height: 1.3,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.3,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        if (online) ...[
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                              color: AppColors.live,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Flexible(
                                          child: Text(
                                            conv.isDirect
                                                ? (conv.otherOnline
                                                    ? 'online'
                                                    : 'offline')
                                                : 'Group · ${conv.members.length} members',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.35,
                                              color: online
                                                  ? const Color(0xFFCDEE9E)
                                                  : Colors.white70,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures()
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (conv.isGroup) ...[
                        const SizedBox(width: 10),
                        ProHeroIconButton(
                          icon: Icons.info_outline_rounded,
                          tooltip: 'Group info',
                          onTap: openGroupInfo,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // The pinned strip sits in the Column ABOVE the message list, so the
      // list always starts below it and no message is ever hidden behind it.
      body: Column(
        children: [
          // ── Pinned message banner (one pin per conversation) ──────────────
          if (_pinned != null)
            _PinnedBanner(
              pinned: _pinned!,
              onTap: () => _jumpToMessage(_pinned!.messageId),
              onUnpin: () async {
                try {
                  await ref
                      .read(chatRepositoryProvider)
                      .unpinMessage(conv.id);
                  if (mounted) setState(() => _pinned = null);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to unpin: $e')),
                    );
                  }
                }
              },
            ),
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
                          ProIconWell(
                            icon: Icons.chat_bubble_outline_rounded,
                            color: AppColors.primary,
                            size: 56,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No messages yet',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Say hello! 👋', style: AppText.caption),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
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
                      isRead = !msg.createdAt.isAfter(conv.otherLastReadAt!);
                    }

                    return AnimatedContainer(
                      key: _msgKeys.putIfAbsent(msg.id, () => GlobalKey()),
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: _highlightMsgId == msg.id
                            ? AppColors.primary.withOpacity(0.10)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
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
                              myEmployeeId: myEmpId,
                              onLongPress: () =>
                                  _showMessageOptions(msg, isMine),
                              onTapReply: msg.replyToId != null
                                  ? () => _jumpToMessage(msg.replyToId!)
                                  : null,
                              onToggleReaction: (emoji) =>
                                  _toggleReaction(msg, emoji),
                              onShowReactors: () => _showReactors(msg),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: AppLoadingBlock(height: 80),
                ),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppErrorPanel(message: err.toString()),
                ),
              ),
            ),
          ),
          // ── Composer: white bar with a hairline top ───────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            padding: EdgeInsets.fromLTRB(12, 8, 12, mq.padding.bottom + 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // @mention suggestions (shown above the input while tagging)
                if (mentionMatches.isNotEmpty) ...[
                  _MentionSuggestions(
                    matches: mentionMatches,
                    onSelect: _applyMention,
                  ),
                  const SizedBox(height: 8),
                ],
                // Reply preview (shown above the input while replying)
                if (_replyingTo != null) ...[
                  _ReplyComposerBar(
                    message: _replyingTo!,
                    // A quote from another conversation = "reply privately".
                    privately: _replyingTo!.conversationId != conv.id,
                    onCancel: () => setState(() => _replyingTo = null),
                  ),
                  const SizedBox(height: 8),
                ],
                _InputBar(
                  controller: _msgCtrl,
                  sending: _sending,
                  onSend: _send,
                  onEmoji: _showEmojiPicker,
                  onAttach: _pickAttachment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────────────────────────────────────
// Header avatar — white squircle with a deep gap and a coloured ring
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.name, required this.ringColor});
  final String name;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(color: AppColors.deep, spreadRadius: 2),
          BoxShadow(color: ringColor, spreadRadius: 3.5),
        ],
      ),
      child: Text(
        ProAvatar.initialsOf(name),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: AppColors.deep,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble — mine: brand fill, white text; theirs: white + hairline
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.isMine,
    required this.isRead,
    required this.showSender,
    required this.onLongPress,
    this.onTapReply,
    this.myEmployeeId,
    this.onToggleReaction,
    this.onShowReactors,
  });
  final ChatMessage msg;
  final bool isMine;
  final bool isRead;
  final bool showSender;
  final VoidCallback onLongPress;
  /// Tapping the quoted reply jumps to the original message (null = no original).
  final VoidCallback? onTapReply;
  /// Current user's employee id — highlights their own reaction chip.
  final int? myEmployeeId;
  /// Tapping a reaction chip toggles the caller's reaction of that emoji.
  final void Function(String emoji)? onToggleReaction;
  /// Long-pressing a reaction chip lists who reacted.
  final VoidCallback? onShowReactors;

  /// Display width of inline images — the caption below wraps to this same
  /// width so the bubble hugs the picture, WhatsApp-style.
  static const double _imageWidth = 240;

  /// Whether this message renders as an inline image (vs a file chip).
  bool get _isInlineImage =>
      _attachmentUrlOf(msg) != null &&
      (msg.type == ChatMessageType.IMAGE ||
          (msg.attachmentContentType?.startsWith('image/') ?? false));

  /// Renders an inline image preview for image attachments, else a file chip.
  Widget _attachment(BuildContext context) {
    final url = _attachmentUrlOf(msg);
    if (_isInlineImage && url != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () => _openImage(context, url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              // Fixed width (not just a max) so image, caption and bubble all
              // share one width; tall images crop via BoxFit.cover like WhatsApp.
              constraints: const BoxConstraints(
                  minWidth: _imageWidth,
                  maxWidth: _imageWidth,
                  maxHeight: 260),
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
    final isImage = msg.type == ChatMessageType.IMAGE;
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withOpacity(0.14) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isMine
                  ? Colors.white.withOpacity(0.18)
                  : (isImage ? AppColors.infoTint : AppColors.dangerTint),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isImage ? Icons.image_rounded : Icons.attach_file_rounded,
              size: 18,
              color: isMine
                  ? Colors.white
                  : (isImage ? AppColors.info : AppColors.danger),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              msg.attachmentName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isMine ? Colors.white : AppColors.ink,
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
      pageBuilder: (_, __, ___) => _ImageViewerScreen(
        url: url,
        // WhatsApp-style header: who sent it and when (not the file name).
        title: isMine ? 'You' : msg.senderName,
        subtitle: DateFormat('d MMM yyyy, h:mm a').format(msg.createdAt),
      ),
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

    // Pro bubbles: mine 18/18/5/18, theirs 5/18/18/18 (TL/TR/BR/BL).
    final radius = isMine
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(5),
            bottomLeft: Radius.circular(18),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(5),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
          );

    final Color fill;
    final Border? border;
    if (deleted) {
      fill = AppColors.neutralTint;
      border = Border.all(color: const Color(0xFFCBD6D9));
    } else if (isMine) {
      fill = AppColors.primary;
      border = null;
    } else {
      fill = AppColors.surface;
      border = Border.all(color: AppColors.hairline);
    }
    final onMine = isMine && !deleted;
    final textColor = onMine ? Colors.white : AppColors.ink;
    final softColor =
        onMine ? Colors.white.withOpacity(0.76) : AppColors.muted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (showSender)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 3),
              child: Text(
                msg.senderName,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.33,
                  fontWeight: FontWeight.w600,
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: border,
                boxShadow: deleted
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x0A0B1D21),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
              ),
              // IntrinsicWidth sizes the bubble to its widest child, so the
              // content can be START-aligned (reads left-to-right) while only
              // the time row floats bottom-right. The Column was previously
              // end-aligned, which pushed the text to the right edge whenever
              // a quote/image/wrapped line was wider.
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (deleted)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block_rounded,
                              size: 14, color: AppColors.muted),
                          SizedBox(width: 6),
                          Text(
                            'This message was deleted',
                            style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      if (msg.forwarded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.forward_rounded,
                                  size: 13, color: softColor),
                              const SizedBox(width: 4),
                              Text(
                                'Forwarded',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: softColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (msg.replyToId != null)
                        // Full bubble width quote block.
                        SizedBox(
                          width: double.infinity,
                          child: _QuotedReply(
                              msg: msg, isMine: isMine, onTap: onTapReply),
                        ),
                      if (msg.attachmentName != null) ...[
                        _attachment(context),
                      ],
                      if (msg.content != null && msg.content!.isNotEmpty)
                        // Under an inline image the caption wraps at the
                        // image's width (bounding it here also caps the
                        // IntrinsicWidth bubble), so the bubble hugs the
                        // picture instead of growing wider than it.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: msg.attachmentName != null &&
                                    _isInlineImage
                                ? _imageWidth
                                : double.infinity,
                          ),
                          child: LinkifiedText(
                            msg.content!,
                            style: TextStyle(
                              fontSize: 15,
                              color: textColor,
                              height: 1.4,
                            ),
                            // White links on the brand bubble, brand links on
                            // the white one.
                            linkColor:
                                isMine ? Colors.white : AppColors.primary,
                          ),
                        ),
                    ],
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('h:mm a').format(msg.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: onMine
                                  ? Colors.white.withOpacity(0.76)
                                  : AppColors.faint,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          if (isMine && !deleted) ...[
                            const SizedBox(width: 3),
                            Icon(
                              isRead
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 14,
                              // Read = soft lime, sent = translucent white.
                              color: isRead
                                  ? const Color(0xFFCDEE9E)
                                  : Colors.white.withOpacity(0.76),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Reactions under the bubble ───────────────────────────────────
          if (!deleted && msg.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: _ReactionChips(
                reactions: msg.reactions,
                myEmployeeId: myEmployeeId,
                onToggle: onToggleReaction,
                onShowReactors: onShowReactors,
              ),
            ),
        ],
      ),
    );
  }

  /// Calm, readable name tints (same family as the Pro avatar palette).
  Color _senderColor(String name) {
    const colors = [
      Color(0xFF00748C),
      Color(0xFF4253A8),
      Color(0xFF1D7A3E),
      Color(0xFF6B46A8),
      Color(0xFF9A5B00),
      Color(0xFF2C5FB3),
      Color(0xFF0F766E),
      Color(0xFFB4501F),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reaction chips — grouped by emoji with a count; own reaction highlighted
// ─────────────────────────────────────────────────────────────────────────────

class _ReactionChips extends StatelessWidget {
  const _ReactionChips({
    required this.reactions,
    this.myEmployeeId,
    this.onToggle,
    this.onShowReactors,
  });
  final List<MessageReaction> reactions;
  final int? myEmployeeId;
  final void Function(String emoji)? onToggle;
  final VoidCallback? onShowReactors;

  @override
  Widget build(BuildContext context) {
    // Group by emoji, preserving first-seen order.
    final counts = <String, int>{};
    final mine = <String>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
      if (r.employeeId == myEmployeeId) mine.add(r.emoji);
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in counts.entries)
          GestureDetector(
            onTap: onToggle == null ? null : () => onToggle!(entry.key),
            onLongPress: onShowReactors,
            child: Container(
              height: 28,
              constraints: const BoxConstraints(minWidth: 40),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: mine.contains(entry.key)
                    ? Color.alphaBlend(
                        AppColors.primary.withOpacity(0.10), Colors.white)
                    : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: mine.contains(entry.key)
                      ? AppColors.primary.withOpacity(0.4)
                      : AppColors.hairline,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D0B1D21),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 13.5)),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: mine.contains(entry.key)
                            ? AppColors.primary
                            : AppColors.inkSoft,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pinned message banner — top of the thread; tap to jump, X to unpin
// ─────────────────────────────────────────────────────────────────────────────

class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({
    required this.pinned,
    required this.onTap,
    required this.onUnpin,
  });
  final PinnedMessage pinned;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      ProIconWell(
                        icon: Icons.push_pin_rounded,
                        color: AppColors.primary,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pinned · ${pinned.senderName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.33,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              pinned.messageDeleted
                                  ? 'This message was deleted'
                                  : (pinned.preview ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.38,
                                fontStyle: pinned.messageDeleted
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: const Color(0xFF43585D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.muted),
              onPressed: onUnpin,
              tooltip: 'Unpin',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// System message (centred brand-tint pill)
// ─────────────────────────────────────────────────────────────────────────────

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.msg});
  final ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
                AppColors.primary.withOpacity(0.10), Colors.white),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            msg.content ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date separator (white hairline pill)
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
    if (target == today) return 'Today';
    if (target == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('d MMMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      child: Center(
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Text(
            _label(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF43585D),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Composer row: rounded field (emoji · text · attach) + brand send button
// ─────────────────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onEmoji,
    required this.onAttach,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onEmoji;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 46, maxHeight: 140),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFDBE3E5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Emoji',
                  icon: const Icon(Icons.sentiment_satisfied_alt_rounded,
                      color: AppColors.muted, size: 22),
                  onPressed: onEmoji,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: controller,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: AppColors.primary,
                      cursorWidth: 1.5,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 9,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Message',
                        hintStyle: TextStyle(
                          color: AppColors.faint,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Attach',
                  icon: const Icon(Icons.attach_file_rounded,
                      color: AppColors.muted, size: 22),
                  onPressed: onAttach,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Brand circular send button
        Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: InkWell(
            onTap: sending ? null : onSend,
            child: SizedBox(
              width: 46,
              height: 46,
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
                        size: 20,
                      ),
              ),
            ),
          ),
        ),
      ],
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
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withOpacity(0.14)
              : const Color(0xFFF1F6F7),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                color: isMine ? Colors.white : AppColors.primary,
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.replyToSenderName ?? 'Reply',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isMine ? Colors.white : AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.38,
                          fontStyle:
                              deleted ? FontStyle.italic : FontStyle.normal,
                          color: isMine
                              ? Colors.white.withOpacity(0.85)
                              : const Color(0xFF43585D),
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
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0B1D21),
            blurRadius: 24,
            spreadRadius: -12,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(4),
        itemCount: matches.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          indent: 52,
          color: AppColors.hairlineSoft,
        ),
        itemBuilder: (_, i) {
          final c = matches[i];
          final hasDesignation =
              c.designation != null && c.designation!.isNotEmpty;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(c),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    _PhotoAvatar(
                      name: c.name,
                      size: 32,
                      imageUrl: Env.fileUrl(c.avatarUrl),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          if (hasDesignation)
                            Text(
                              c.designation!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
  const _ReplyComposerBar({
    required this.message,
    required this.onCancel,
    this.privately = false,
  });
  final ChatMessage message;
  final VoidCallback onCancel;
  /// True when quoting a message from another conversation ("reply privately").
  final bool privately;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F7),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${privately ? "Replying privately to" : "Replying to"} ${message.senderName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      message.previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF43585D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Cancel reply',
              icon: const Icon(Icons.close_rounded,
                  size: 20, color: AppColors.muted),
              onPressed: onCancel,
            ),
          ],
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
      backgroundColor: AppColors.deep,
      appBar: AppBar(
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(12, 12, 12, mq.padding.bottom + 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints:
                        const BoxConstraints(minHeight: 46, maxHeight: 140),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFDBE3E5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _caption,
                        maxLines: null,
                        autofocus: false,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: AppColors.primary,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.ink),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 9),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Add a caption…',
                          hintStyle:
                              TextStyle(color: AppColors.faint, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, _caption.text),
                    child: const SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(Icons.send_rounded,
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.dangerTint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.insert_drive_file_rounded,
                size: 28, color: AppColors.danger),
          ),
          const SizedBox(height: 12),
          Text(
            fileName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet building blocks (white, 24 top radius, drag handle)
// ─────────────────────────────────────────────────────────────────────────────

class _ProSheet extends StatelessWidget {
  const _ProSheet({
    required this.children,
    this.title,
    this.scrollable = false,
  });
  final String? title;
  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFC6D3D6),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              title!,
              style: const TextStyle(
                fontSize: 19,
                height: 1.3,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: scrollable ? SingleChildScrollView(child: content) : content,
        ),
      ),
    );
  }
}

/// Hairline-bordered group of sheet rows with inset dividers.
class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 56,
                color: AppColors.hairlineSoft,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

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
    final danger = color == AppColors.danger;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            child: Row(
              children: [
                ProIconWell(icon: icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: danger ? AppColors.danger : AppColors.ink,
                    ),
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

/// Tile in the "Attach" sheet.
class _AttachTile extends StatelessWidget {
  const _AttachTile({
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
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
          child: Column(
            children: [
              ProIconWell(icon: icon, color: color, size: 48),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [ProAvatar] squircle with the person's photo on top when there is one.
class _PhotoAvatar extends StatelessWidget {
  const _PhotoAvatar({required this.name, this.size = 32, this.imageUrl});
  final String name;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ProAvatar(name: name, size: size),
          if (url != null && url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.31),
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fullscreen image viewer: pinch-zoom + pan (InteractiveViewer), double-tap to
/// zoom to the tapped point, 90° rotate, and tap-to-toggle chrome. Mirrors the
/// web ImageViewer's interaction model, dependency-free.
class _ImageViewerScreen extends StatefulWidget {
  const _ImageViewerScreen({required this.url, required this.title, this.subtitle});
  final String url;
  final String title;
  /// Secondary line under the title (e.g. when the image was sent).
  final String? subtitle;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                        if (widget.subtitle != null)
                          Text(
                            widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
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
