/// AI-assistant models — mirror of the backend `/api/assistant` DTOs plus the
/// SSE event envelope streamed by `POST /api/assistant/chat`.
import 'dart:convert';

/// One structured card attached to an assistant reply. Card data is derived
/// server-side from TOOL RESULTS (never LLM output) — the mobile app renders
/// known types natively and silently ignores unknown ones (forward-compat).
class AssistantCard {
  final String type;
  final Map<String, dynamic> data;

  const AssistantCard(this.type, this.data);

  static List<AssistantCard> listFrom(dynamic raw) {
    // Accepts either the raw JSON string persisted on the message or the
    // already-decoded list from the SSE done event.
    dynamic decoded = raw;
    if (raw is String) {
      if (raw.isEmpty) return const [];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    final out = <AssistantCard>[];
    for (final e in decoded) {
      if (e is Map && e['type'] is String && e['data'] is Map) {
        out.add(AssistantCard(
            e['type'] as String, (e['data'] as Map).cast<String, dynamic>()));
      }
    }
    return out;
  }
}

class AssistantConversation {
  final int id;
  final String? title;
  final bool pinned;
  final DateTime? updatedAt;

  const AssistantConversation({
    required this.id,
    this.title,
    this.pinned = false,
    this.updatedAt,
  });

  factory AssistantConversation.fromJson(Map<String, dynamic> j) =>
      AssistantConversation(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String?,
        pinned: j['pinned'] == true,
        updatedAt: j['updatedAt'] is String
            ? DateTime.tryParse(j['updatedAt'] as String)
            : null,
      );

  AssistantConversation copyWith({String? title, bool? pinned}) =>
      AssistantConversation(
        id: id,
        title: title ?? this.title,
        pinned: pinned ?? this.pinned,
        updatedAt: updatedAt,
      );
}

class AssistantMessage {
  static const roleUser = 'USER';
  static const roleAssistant = 'ASSISTANT';

  /// Null while the reply is still streaming (not yet persisted server-side).
  final int? id;
  final String role;
  final String content;
  final String? feedback; // UP | DOWN | null
  final List<AssistantCard> cards;
  final DateTime? createdAt;

  const AssistantMessage({
    this.id,
    required this.role,
    required this.content,
    this.feedback,
    this.cards = const [],
    this.createdAt,
  });

  bool get isUser => role == roleUser;

  factory AssistantMessage.fromJson(Map<String, dynamic> j) => AssistantMessage(
        id: (j['id'] as num?)?.toInt(),
        role: j['role'] as String? ?? roleAssistant,
        content: j['content'] as String? ?? '',
        feedback: j['feedback'] as String?,
        cards: AssistantCard.listFrom(j['cards']),
        createdAt: j['createdAt'] is String
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
      );

  AssistantMessage copyWith({int? id, String? content, String? feedback}) =>
      AssistantMessage(
        id: id ?? this.id,
        role: role,
        content: content ?? this.content,
        feedback: feedback,
        cards: cards,
        createdAt: createdAt,
      );
}

class AssistantConversationDetail {
  final int id;
  final String? title;
  final bool pinned;
  final List<AssistantMessage> messages;

  const AssistantConversationDetail({
    required this.id,
    this.title,
    this.pinned = false,
    this.messages = const [],
  });

  factory AssistantConversationDetail.fromJson(Map<String, dynamic> j) =>
      AssistantConversationDetail(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String?,
        pinned: j['pinned'] == true,
        messages: ((j['messages'] as List?) ?? const [])
            .map((e) => AssistantMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One named SSE event from the chat stream. `data` is the decoded JSON body.
class AssistantEvent {
  final String name; // meta | status | token | done | error
  final Map<String, dynamic> data;

  const AssistantEvent(this.name, this.data);
}
