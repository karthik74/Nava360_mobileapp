import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'chat_models.dart';

/// REST client for `/api/chat/*` endpoints.
class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  // ── Contacts ──────────────────────────────────────────────────────────────

  Future<List<ChatContact>> searchContacts(String query) {
    return _api.get<List<ChatContact>>(
      '/api/chat/contacts',
      query: {'q': query},
      parse: (d) => (d as List)
          .map((e) => ChatContact.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ── Conversations ─────────────────────────────────────────────────────────

  Future<List<Conversation>> listConversations() {
    return _api.get<List<Conversation>>(
      '/api/chat/conversations',
      parse: (d) => (d as List)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Conversation> getOrCreateDirect(int employeeId) {
    return _api.post<Conversation>(
      '/api/chat/conversations/direct',
      body: {'employeeId': employeeId},
      parse: (d) => Conversation.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<Conversation> createGroup(String name, List<int> memberIds) {
    return _api.post<Conversation>(
      '/api/chat/conversations/group',
      body: {'name': name, 'memberEmployeeIds': memberIds},
      parse: (d) => Conversation.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<Conversation> addMembers(int conversationId, List<int> memberIds) {
    return _api.post<Conversation>(
      '/api/chat/conversations/$conversationId/members',
      body: {'memberEmployeeIds': memberIds},
      parse: (d) => Conversation.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> removeMember(int conversationId, int employeeId) async {
    await _api.raw.delete(
      '/api/chat/conversations/$conversationId/members/$employeeId',
    );
  }

  Future<void> makeAdmin(int conversationId, int employeeId) async {
    await _api.post<void>(
      '/api/chat/conversations/$conversationId/members/$employeeId/admin',
      parse: (_) {},
    );
  }

  Future<void> demoteAdmin(int conversationId, int employeeId) async {
    await _api.post<void>(
      '/api/chat/conversations/$conversationId/members/$employeeId/demote',
      parse: (_) {},
    );
  }

  Future<void> leaveGroup(int conversationId) async {
    await _api.post<void>(
      '/api/chat/conversations/$conversationId/leave',
      parse: (_) {},
    );
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<ChatMessage>> loadMessages(
    int conversationId, {
    int? before,
    int size = 30,
  }) {
    return _api.get<List<ChatMessage>>(
      '/api/chat/conversations/$conversationId/messages',
      query: {
        'size': size.toString(),
        if (before != null) 'before': before.toString(),
      },
      parse: (d) => (d as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<ChatMessage> sendMessage(
    int conversationId, {
    String? content,
    int? attachmentFileId,
    String? attachmentName,
    String? attachmentContentType,
    int? attachmentSizeBytes,
    int? replyToMessageId,
  }) {
    return _api.post<ChatMessage>(
      '/api/chat/conversations/$conversationId/messages',
      body: {
        if (content != null) 'content': content,
        if (attachmentFileId != null) 'attachmentFileId': attachmentFileId,
        if (attachmentName != null) 'attachmentName': attachmentName,
        if (attachmentContentType != null)
          'attachmentContentType': attachmentContentType,
        if (attachmentSizeBytes != null)
          'attachmentSizeBytes': attachmentSizeBytes,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      },
      parse: (d) => ChatMessage.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Uploads a file to the shared file store and returns its details so it can be
  /// attached to a chat message.
  Future<({int fileId, String name, String? contentType, int? sizeBytes})>
      uploadAttachment(String filePath, {String? filename}) async {
    final name = filename ?? filePath.split(RegExp(r'[\\/]+')).last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: name),
    });
    final res = await _api.raw.post<Map<String, dynamic>>('/api/files', data: form);
    final data = (res.data?['data'] as Map<String, dynamic>?) ?? const {};
    return (
      fileId: (data['id'] as num).toInt(),
      name: (data['originalName'] as String?) ?? name,
      contentType: data['contentType'] as String?,
      sizeBytes: (data['sizeBytes'] as num?)?.toInt(),
    );
  }

  // ── Reactions (one per person; same emoji removes, different replaces) ────

  /// Add or switch your reaction; resolves to the message's full reaction set.
  Future<List<MessageReaction>> addReaction(int messageId, String emoji) {
    return _api.post<List<MessageReaction>>(
      '/api/chat/messages/$messageId/reactions',
      body: {'emoji': emoji},
      parse: _parseReactions,
    );
  }

  /// Remove your own reaction; resolves to the message's remaining reactions.
  Future<List<MessageReaction>> removeReaction(int messageId) async {
    final res = await _api.raw.delete<Map<String, dynamic>>(
      '/api/chat/messages/$messageId/reactions',
    );
    return _parseReactions(res.data?['data']);
  }

  static List<MessageReaction> _parseReactions(dynamic d) =>
      (d as List<dynamic>? ?? const [])
          .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
          .toList();

  // ── Pinned message (one per conversation, pinning another replaces it) ────

  Future<PinnedMessage?> getPinnedMessage(int conversationId) {
    return _api.get<PinnedMessage?>(
      '/api/chat/conversations/$conversationId/pin',
      parse: (d) =>
          d == null ? null : PinnedMessage.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<PinnedMessage> pinMessage(int conversationId, int messageId) {
    return _api.post<PinnedMessage>(
      '/api/chat/conversations/$conversationId/pin',
      body: {'messageId': messageId},
      parse: (d) => PinnedMessage.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> unpinMessage(int conversationId) async {
    await _api.raw.delete('/api/chat/conversations/$conversationId/pin');
  }

  Future<void> markRead(int conversationId) async {
    await _api.post<void>(
      '/api/chat/conversations/$conversationId/read',
      parse: (_) {},
    );
  }

  Future<void> deleteMessage(
    int conversationId,
    int messageId, {
    bool forEveryone = false,
  }) async {
    await _api.raw.delete(
      '/api/chat/conversations/$conversationId/messages/$messageId',
      queryParameters: {'forEveryone': forEveryone.toString()},
    );
  }
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);
