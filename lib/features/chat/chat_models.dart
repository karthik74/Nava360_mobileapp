/// Data models for the chat feature, mirroring the backend DTOs.

// ── Enums ────────────────────────────────────────────────────────────────────

enum ConversationType { DIRECT, GROUP }

enum ChatMessageType { TEXT, FILE, IMAGE, SYSTEM }

enum WorkStatus { ON_LEAVE, WORKING, OFF }

// ── ChatContact ──────────────────────────────────────────────────────────────

class ChatContact {
  final int employeeId;
  final String name;
  final String? designation;
  final String? employeeCode;
  final String? avatarUrl;
  final String? department;
  final int? reportingManagerId;
  final String? reportingManagerName;
  final bool isAdmin;
  final WorkStatus status;
  final bool online;

  const ChatContact({
    required this.employeeId,
    required this.name,
    this.designation,
    this.employeeCode,
    this.avatarUrl,
    this.department,
    this.reportingManagerId,
    this.reportingManagerName,
    this.isAdmin = false,
    this.status = WorkStatus.OFF,
    this.online = false,
  });

  factory ChatContact.fromJson(Map<String, dynamic> j) => ChatContact(
        employeeId: (j['employeeId'] as num).toInt(),
        name: j['name'] as String? ?? 'Unknown',
        designation: j['designation'] as String?,
        employeeCode: j['employeeCode'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        department: j['department'] as String?,
        reportingManagerId: (j['reportingManagerId'] as num?)?.toInt(),
        reportingManagerName: j['reportingManagerName'] as String?,
        isAdmin: j['isAdmin'] == true,
        status: _parseWorkStatus(j['status'] as String?),
        online: j['online'] == true,
      );
}

// ── Conversation ─────────────────────────────────────────────────────────────

class Conversation {
  final int id;
  final ConversationType type;
  final String title;
  final int? createdByEmployeeId;
  final int? otherEmployeeId;
  final List<ChatContact> members;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime? otherLastReadAt;
  final WorkStatus? otherStatus;
  final bool otherOnline;

  const Conversation({
    required this.id,
    required this.type,
    required this.title,
    this.createdByEmployeeId,
    this.otherEmployeeId,
    this.members = const [],
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.otherLastReadAt,
    this.otherStatus,
    this.otherOnline = false,
  });

  bool get isDirect => type == ConversationType.DIRECT;
  bool get isGroup => type == ConversationType.GROUP;

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final membersList = (j['members'] as List<dynamic>?)
            ?.map((e) => ChatContact.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return Conversation(
      id: (j['id'] as num).toInt(),
      type: (j['type'] as String?) == 'GROUP'
          ? ConversationType.GROUP
          : ConversationType.DIRECT,
      title: j['title'] as String? ?? '',
      createdByEmployeeId: (j['createdByEmployeeId'] as num?)?.toInt(),
      otherEmployeeId: (j['otherEmployeeId'] as num?)?.toInt(),
      members: membersList,
      lastMessagePreview: j['lastMessagePreview'] as String?,
      lastMessageAt: _parseDateTime(j['lastMessageAt']),
      unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
      otherLastReadAt: _parseDateTime(j['otherLastReadAt']),
      otherStatus: _parseWorkStatus(j['otherStatus'] as String?),
      otherOnline: j['otherOnline'] == true,
    );
  }

  /// Returns a copy with mutated fields (for live-updating from WS events).
  Conversation copyWith({
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? otherLastReadAt,
    bool? otherOnline,
  }) =>
      Conversation(
        id: id,
        type: type,
        title: title,
        createdByEmployeeId: createdByEmployeeId,
        otherEmployeeId: otherEmployeeId,
        members: members,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        unreadCount: unreadCount ?? this.unreadCount,
        otherLastReadAt: otherLastReadAt ?? this.otherLastReadAt,
        otherStatus: otherStatus,
        otherOnline: otherOnline ?? this.otherOnline,
      );
}

// ── ChatMessage ──────────────────────────────────────────────────────────────

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final ChatMessageType type;
  final String? content;
  final int? attachmentFileId;
  final String? attachmentName;
  final String? attachmentContentType;
  final int? attachmentSizeBytes;
  final String? attachmentUrl;
  final DateTime createdAt;
  final bool deletedForEveryone;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.type,
    this.content,
    this.attachmentFileId,
    this.attachmentName,
    this.attachmentContentType,
    this.attachmentSizeBytes,
    this.attachmentUrl,
    required this.createdAt,
    this.deletedForEveryone = false,
  });

  bool get isSystem => type == ChatMessageType.SYSTEM;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] as num).toInt(),
        conversationId: (j['conversationId'] as num).toInt(),
        senderId: (j['senderId'] as num).toInt(),
        senderName: j['senderName'] as String? ?? '',
        type: _parseMsgType(j['type'] as String?),
        content: j['content'] as String?,
        attachmentFileId: (j['attachmentFileId'] as num?)?.toInt(),
        attachmentName: j['attachmentName'] as String?,
        attachmentContentType: j['attachmentContentType'] as String?,
        attachmentSizeBytes: (j['attachmentSizeBytes'] as num?)?.toInt(),
        attachmentUrl: j['attachmentUrl'] as String?,
        createdAt: _parseDateTime(j['createdAt']) ?? DateTime.now(),
        deletedForEveryone: j['deletedForEveryone'] == true,
      );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

DateTime? _parseDateTime(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

WorkStatus _parseWorkStatus(String? s) {
  switch (s) {
    case 'ON_LEAVE':
      return WorkStatus.ON_LEAVE;
    case 'WORKING':
      return WorkStatus.WORKING;
    default:
      return WorkStatus.OFF;
  }
}

ChatMessageType _parseMsgType(String? s) {
  switch (s) {
    case 'FILE':
      return ChatMessageType.FILE;
    case 'IMAGE':
      return ChatMessageType.IMAGE;
    case 'SYSTEM':
      return ChatMessageType.SYSTEM;
    default:
      return ChatMessageType.TEXT;
  }
}
