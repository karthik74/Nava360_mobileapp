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
      },
      parse: (d) => ChatMessage.fromJson(d as Map<String, dynamic>),
    );
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
