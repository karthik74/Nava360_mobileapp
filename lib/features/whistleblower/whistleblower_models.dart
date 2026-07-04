/// A file the user has staged as evidence before/after submission.
class EvidenceFile {
  final String path;
  final String fileName;
  final String category; // 'audio' | 'image' | 'document'
  final int? durationSeconds;

  EvidenceFile({
    required this.path,
    required this.fileName,
    required this.category,
    this.durationSeconds,
  });

  String get mime {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}

class WbCategoryOption {
  final String value;
  final String label;
  WbCategoryOption(this.value, this.label);
  factory WbCategoryOption.fromJson(Map<String, dynamic> j) =>
      WbCategoryOption(j['value'] as String, j['label'] as String);
}

class WbAttachment {
  final int id;
  final String? fileName;
  final String fileCategory; // AUDIO | IMAGE | PDF | DOCUMENT
  final String? mimeType;
  final int? fileSize;
  final int? durationSeconds;
  final bool employeeUploaded;
  final DateTime? createdAt;

  WbAttachment({
    required this.id,
    required this.fileCategory,
    required this.employeeUploaded,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.durationSeconds,
    this.createdAt,
  });

  factory WbAttachment.fromJson(Map<String, dynamic> j) => WbAttachment(
        id: (j['id'] as num).toInt(),
        fileName: j['fileName'] as String?,
        fileCategory: j['fileCategory'] as String? ?? 'DOCUMENT',
        mimeType: j['mimeType'] as String?,
        fileSize: (j['fileSize'] as num?)?.toInt(),
        durationSeconds: (j['durationSeconds'] as num?)?.toInt(),
        employeeUploaded: j['employeeUploaded'] as bool? ?? true,
        createdAt: _date(j['createdAt']),
      );
}

class WbComment {
  final int id;
  final String commentText;
  final String commentType;
  final String? authorDisplay;
  final DateTime? createdAt;

  WbComment({
    required this.id,
    required this.commentText,
    required this.commentType,
    this.authorDisplay,
    this.createdAt,
  });

  factory WbComment.fromJson(Map<String, dynamic> j) => WbComment(
        id: (j['id'] as num).toInt(),
        commentText: j['commentText'] as String? ?? '',
        commentType: j['commentType'] as String? ?? 'EMPLOYEE_VISIBLE',
        authorDisplay: j['authorDisplay'] as String?,
        createdAt: _date(j['createdAt']),
      );
}

class WbTimelineEntry {
  final String status;
  final DateTime? at;
  WbTimelineEntry(this.status, this.at);
  factory WbTimelineEntry.fromJson(Map<String, dynamic> j) =>
      WbTimelineEntry(j['status'] as String? ?? '', _date(j['at']));
}

class WbCase {
  final int id;
  final String? trackingNumber;
  final String category;
  final String subject;
  final String? description;
  final DateTime? incidentDate;
  final String? branch;
  final String? department;
  final String? personsInvolved;
  final bool anonymous;
  final String status;
  final bool canAddEvidence;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final List<WbAttachment> attachments;
  final List<WbComment> comments;
  final List<WbTimelineEntry> timeline;

  WbCase({
    required this.id,
    required this.category,
    required this.subject,
    required this.anonymous,
    required this.status,
    required this.canAddEvidence,
    required this.attachments,
    required this.comments,
    required this.timeline,
    this.trackingNumber,
    this.description,
    this.incidentDate,
    this.branch,
    this.department,
    this.personsInvolved,
    this.createdAt,
    this.closedAt,
  });

  factory WbCase.fromJson(Map<String, dynamic> j) => WbCase(
        id: (j['id'] as num).toInt(),
        trackingNumber: j['trackingNumber'] as String?,
        category: j['category'] as String? ?? 'OTHER',
        subject: j['subject'] as String? ?? '',
        description: j['description'] as String?,
        incidentDate: _date(j['incidentDate']),
        branch: j['branch'] as String?,
        department: j['department'] as String?,
        personsInvolved: j['personsInvolved'] as String?,
        anonymous: j['anonymous'] as bool? ?? false,
        status: j['status'] as String? ?? 'SUBMITTED',
        canAddEvidence: j['canAddEvidence'] as bool? ?? false,
        createdAt: _date(j['createdAt']),
        closedAt: _date(j['closedAt']),
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((e) => WbAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        comments: ((j['comments'] as List?) ?? const [])
            .map((e) => WbComment.fromJson(e as Map<String, dynamic>))
            .toList(),
        timeline: ((j['timeline'] as List?) ?? const [])
            .map((e) => WbTimelineEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class WbCreated {
  final int id;
  final String trackingNumber;
  final String status;
  WbCreated(this.id, this.trackingNumber, this.status);
  factory WbCreated.fromJson(Map<String, dynamic> j) => WbCreated(
        (j['id'] as num).toInt(),
        j['trackingNumber'] as String? ?? '',
        j['status'] as String? ?? 'SUBMITTED',
      );
}

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}
