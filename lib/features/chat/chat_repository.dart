import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'chat_models.dart';

/// REST client for `/api/chat/*` endpoints.
class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  // ── Contacts ──────────────────────────────────────────────────────────────

  /// [scoped] limits results to the caller's reporting hierarchy / assigned
  /// branches (server-side) — used when picking group members.
  Future<List<ChatContact>> searchContacts(String query, {bool scoped = false}) {
    return _api.get<List<ChatContact>>(
      '/api/chat/contacts',
      query: {'q': query, if (scoped) 'scoped': 'true'},
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

  /// Rename a group (group admins only).
  Future<Conversation> renameGroup(int conversationId, String name) {
    return _api.patch<Conversation>(
      '/api/chat/conversations/$conversationId',
      body: {'name': name},
      parse: (d) => Conversation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Delete a group for everyone (group admins only). Soft delete — history kept server-side.
  Future<void> deleteGroup(int conversationId) async {
    await _api.raw.delete('/api/chat/conversations/$conversationId');
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

  /// Forward a message into other chats and/or to colleagues (their direct
  /// chat is found-or-created).
  ///
  /// Mirrors the web: a pure client-side re-send. The copy carries the
  /// original's text/caption AND its attachment (same stored file id — nothing
  /// is re-uploaded), flagged `forwarded`, but never its reply-quote or
  /// reactions. Targets are sent independently; returns the copies that
  /// succeeded and throws only when none did.
  Future<List<ChatMessage>> forwardMessage(
    ChatMessage message, {
    List<int> conversationIds = const [],
    List<int> employeeIds = const [],
  }) async {
    final targets = <int>{...conversationIds};
    for (final empId in employeeIds) {
      targets.add((await getOrCreateDirect(empId)).id);
    }
    if (targets.isEmpty) return const [];

    final content = message.content?.trim();
    final results = await Future.wait(
      targets.map(
        (convId) => sendMessage(
          convId,
          content: (content == null || content.isEmpty) ? null : content,
          attachmentFileId: message.attachmentFileId,
          attachmentName:
              message.attachmentFileId == null ? null : message.attachmentName,
          attachmentContentType: message.attachmentFileId == null
              ? null
              : message.attachmentContentType,
          attachmentSizeBytes: message.attachmentFileId == null
              ? null
              : message.attachmentSizeBytes,
          forwarded: true,
        ).then<ChatMessage?>((m) => m, onError: (Object e) => null),
      ),
    );
    final ok = results.whereType<ChatMessage>().toList();
    if (ok.isEmpty) {
      throw Exception('Could not forward the message');
    }
    return ok;
  }

  Future<ChatMessage> sendMessage(
    int conversationId, {
    String? content,
    int? attachmentFileId,
    String? attachmentName,
    String? attachmentContentType,
    int? attachmentSizeBytes,
    int? replyToMessageId,
    bool forwarded = false,
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
        if (forwarded) 'forwarded': true,
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
