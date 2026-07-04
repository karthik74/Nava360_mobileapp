import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'chat_socket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Conversations list
// ─────────────────────────────────────────────────────────────────────────────

/// Fetches the current user's conversations and listens to the WebSocket
/// for live updates (new messages bump last-message preview + unread count).
class ConversationsNotifier extends StateNotifier<AsyncValue<List<Conversation>>> {
  ConversationsNotifier(this._repo, this._socket, this._myEmployeeId)
      : super(const AsyncValue.loading()) {
    _load();
    _sub = _socket.stream.listen(_onWsEvent);
  }

  final ChatRepository _repo;
  final ChatSocketService _socket;
  final int? _myEmployeeId;
  StreamSubscription? _sub;

  Future<void> _load() async {
    try {
      final list = await _repo.listConversations();
      // Sort newest-first.
      list.sort((a, b) => (b.lastMessageAt ?? DateTime(2000))
          .compareTo(a.lastMessageAt ?? DateTime(2000)));
      if (mounted) state = AsyncValue.data(list);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'MESSAGE') {
      final msg = ChatMessage.fromJson(event['message'] as Map<String, dynamic>);
      final convId = (event['conversationId'] as num).toInt();
      state.whenData((list) {
        final idx = list.indexWhere((c) => c.id == convId);
        if (idx < 0) {
          // New conversation — full refresh.
          _load();
          return;
        }
        final updated = List<Conversation>.from(list);
        final old = updated[idx];
        final isMine = msg.senderId == _myEmployeeId;
        updated[idx] = old.copyWith(
          lastMessagePreview: msg.content ?? '📎 Attachment',
          lastMessageAt: msg.createdAt,
          unreadCount: isMine ? old.unreadCount : old.unreadCount + 1,
        );
        // Re-sort.
        updated.sort((a, b) => (b.lastMessageAt ?? DateTime(2000))
            .compareTo(a.lastMessageAt ?? DateTime(2000)));
        state = AsyncValue.data(updated);
      });
    } else if (type == 'READ') {
      final convId = (event['conversationId'] as num).toInt();
      final byEmpId = (event['byEmployeeId'] as num).toInt();
      if (byEmpId == _myEmployeeId) {
        // We read a conversation — zero its unread count.
        state.whenData((list) {
          final idx = list.indexWhere((c) => c.id == convId);
          if (idx < 0) return;
          final updated = List<Conversation>.from(list);
          updated[idx] = updated[idx].copyWith(unreadCount: 0);
          state = AsyncValue.data(updated);
        });
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final conversationsProvider =
    StateNotifierProvider.autoDispose<ConversationsNotifier, AsyncValue<List<Conversation>>>(
  (ref) {
    final repo = ref.watch(chatRepositoryProvider);
    final socket = ref.watch(chatSocketProvider);
    final user = ref.watch(authUserProvider);
    return ConversationsNotifier(repo, socket, user?.employeeId);
  },
);

/// Total unread count across all conversations (for drawer badge).
final totalUnreadProvider = Provider.autoDispose<int>((ref) {
  final convs = ref.watch(conversationsProvider);
  return convs.asData?.value.fold<int>(0, (sum, c) => sum + c.unreadCount) ?? 0;
});

// ─────────────────────────────────────────────────────────────────────────────
// Messages for a single conversation
// ─────────────────────────────────────────────────────────────────────────────

class ChatMessagesNotifier extends StateNotifier<AsyncValue<List<ChatMessage>>> {
  ChatMessagesNotifier(this._repo, this._socket, this._conversationId, this._myEmployeeId)
      : super(const AsyncValue.loading()) {
    _loadInitial();
    _sub = _socket.stream.listen(_onWsEvent);
    // Mark the conversation as read when opened.
    _repo.markRead(_conversationId);
  }

  final ChatRepository _repo;
  final ChatSocketService _socket;
  final int _conversationId;
  final int? _myEmployeeId;
  StreamSubscription? _sub;
  bool _hasMore = true;

  bool get hasMore => _hasMore;

  Future<void> _loadInitial() async {
    try {
      final msgs = await _repo.loadMessages(_conversationId);
      _hasMore = msgs.length >= 30;
      if (mounted) state = AsyncValue.data(msgs);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  /// Append a message we just sent so it shows immediately, without waiting for
  /// the WebSocket echo or a refresh. Deduped by id, so a later echo is a no-op.
  void addLocal(ChatMessage msg) {
    state.whenData((list) {
      if (list.any((m) => m.id == msg.id)) return;
      state = AsyncValue.data([...list, msg]);
    });
  }

  /// Replace one message's reaction set (from a REST response or the REACTION
  /// socket echo — both carry the full snapshot, so applying twice is harmless).
  void applyReactions(int messageId, List<MessageReaction> reactions) {
    state.whenData((list) {
      state = AsyncValue.data([
        for (final m in list)
          m.id == messageId ? m.withReactions(reactions) : m,
      ]);
    });
  }

  /// Load earlier messages (cursor pagination).
  Future<void> loadMore() async {
    if (!_hasMore) return;
    final current = state.asData?.value ?? [];
    if (current.isEmpty) return;
    final oldest = current.first.id;
    try {
      final older = await _repo.loadMessages(_conversationId, before: oldest);
      _hasMore = older.length >= 30;
      if (mounted) {
        state = AsyncValue.data([...older, ...current]);
      }
    } catch (_) {
      // Silently fail — user can retry.
    }
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'MESSAGE') {
      final convId = (event['conversationId'] as num).toInt();
      if (convId != _conversationId) return;
      final msg = ChatMessage.fromJson(event['message'] as Map<String, dynamic>);
      state.whenData((list) {
        // Avoid duplicates.
        if (list.any((m) => m.id == msg.id)) return;
        state = AsyncValue.data([...list, msg]);
      });
      // Auto-mark read.
      _repo.markRead(_conversationId);
    } else if (type == 'REACTION') {
      final convId = (event['conversationId'] as num).toInt();
      if (convId != _conversationId) return;
      final msgId = (event['messageId'] as num).toInt();
      final reactions = (event['reactions'] as List<dynamic>? ?? const [])
          .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
          .toList();
      applyReactions(msgId, reactions);
    } else if (type == 'DELETED') {
      final convId = (event['conversationId'] as num).toInt();
      if (convId != _conversationId) return;
      final msgId = (event['messageId'] as num).toInt();
      state.whenData((list) {
        final updated = list.map((m) {
          if (m.id != msgId) return m;
          // Replace with tombstone version.
          return ChatMessage(
            id: m.id,
            conversationId: m.conversationId,
            senderId: m.senderId,
            senderName: m.senderName,
            type: m.type,
            content: null,
            createdAt: m.createdAt,
            deletedForEveryone: true,
          );
        }).toList();
        state = AsyncValue.data(updated);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final chatMessagesProvider = StateNotifierProvider.autoDispose
    .family<ChatMessagesNotifier, AsyncValue<List<ChatMessage>>, int>(
  (ref, conversationId) {
    final repo = ref.watch(chatRepositoryProvider);
    final socket = ref.watch(chatSocketProvider);
    final user = ref.watch(authUserProvider);
    return ChatMessagesNotifier(repo, socket, conversationId, user?.employeeId);
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Contacts search
// ─────────────────────────────────────────────────────────────────────────────

final contactsSearchProvider =
    FutureProvider.autoDispose.family<List<ChatContact>, String>((ref, query) {
  return ref.watch(chatRepositoryProvider).searchContacts(query);
});
