// Employee-facing announcement models (mirror of the backend
// `AnnouncementMyResponse` + attachment DTO).

DateTime? _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

class AnnouncementAttachment {
  final int id;
  final String kind; // FILE | LINK
  final String? fileName;
  final String? fileType;
  final String? caption;
  final String url;

  AnnouncementAttachment({
    required this.id,
    required this.kind,
    required this.url,
    this.fileName,
    this.fileType,
    this.caption,
  });

  factory AnnouncementAttachment.fromJson(Map<String, dynamic> j) =>
      AnnouncementAttachment(
        id: (j['id'] as num).toInt(),
        kind: j['kind'] as String? ?? 'FILE',
        fileName: j['fileName'] as String?,
        fileType: j['fileType'] as String?,
        caption: j['caption'] as String?,
        url: j['url'] as String? ?? '',
      );
}

class MyAnnouncement {
  final int id;
  final String title;
  final String? description;
  final String category;
  final String priority;
  final bool pinned;
  final bool mandatory;
  final bool requiresAcknowledgement;
  final bool allowComments;
  final DateTime? publishedAt;
  final DateTime? expiryDatetime;
  final bool read;
  final DateTime? readAt;
  final bool acknowledged;
  final DateTime? acknowledgedAt;
  final List<AnnouncementAttachment> attachments;

  MyAnnouncement({
    required this.id,
    required this.title,
    required this.category,
    required this.priority,
    required this.pinned,
    required this.mandatory,
    required this.requiresAcknowledgement,
    required this.allowComments,
    required this.read,
    required this.acknowledged,
    required this.attachments,
    this.description,
    this.publishedAt,
    this.expiryDatetime,
    this.readAt,
    this.acknowledgedAt,
  });

  factory MyAnnouncement.fromJson(Map<String, dynamic> j) => MyAnnouncement(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? 'Announcement',
        description: j['description'] as String?,
        category: j['category'] as String? ?? 'GENERAL',
        priority: j['priority'] as String? ?? 'NORMAL',
        pinned: j['pinned'] as bool? ?? false,
        mandatory: j['mandatory'] as bool? ?? false,
        requiresAcknowledgement: j['requiresAcknowledgement'] as bool? ?? false,
        allowComments: j['allowComments'] as bool? ?? false,
        publishedAt: _parseDate(j['publishedAt']),
        expiryDatetime: _parseDate(j['expiryDatetime']),
        read: j['read'] as bool? ?? false,
        readAt: _parseDate(j['readAt']),
        acknowledged: j['acknowledged'] as bool? ?? false,
        acknowledgedAt: _parseDate(j['acknowledgedAt']),
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((e) => AnnouncementAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AnnouncementComment {
  final int id;
  final int? employeeId;
  final String? employeeName;
  final String comment;
  final DateTime? createdAt;

  AnnouncementComment({
    required this.id,
    required this.comment,
    this.employeeId,
    this.employeeName,
    this.createdAt,
  });

  factory AnnouncementComment.fromJson(Map<String, dynamic> j) =>
      AnnouncementComment(
        id: (j['id'] as num).toInt(),
        employeeId: (j['employeeId'] as num?)?.toInt(),
        employeeName: j['employeeName'] as String?,
        comment: j['comment'] as String? ?? '',
        createdAt: _parseDate(j['createdAt']),
      );
}
