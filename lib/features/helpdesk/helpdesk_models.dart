// Enterprise Helpdesk — mobile models (Phase 1). Mirrors the backend DTOs.

const kHelpdeskStatuses = <String>[
  'OPEN', 'IN_PROGRESS', 'ON_HOLD', 'RESOLVED', 'CLOSED', 'REOPENED', 'CANCELLED',
];
const kHelpdeskPriorities = <String>['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

class HdTicketSummary {
  final int id;
  final String ticketNumber;
  final String title;
  final String? category;
  final String status;
  final String priority;
  final String? raisedByName;
  final String? assignedToName;
  final String? branchName;
  final String? department;
  final DateTime? resolutionDueAt;
  final bool responseBreached;
  final bool resolutionBreached;
  final int escalationLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HdTicketSummary({
    required this.id,
    required this.ticketNumber,
    required this.title,
    this.category,
    required this.status,
    required this.priority,
    this.raisedByName,
    this.assignedToName,
    this.branchName,
    this.department,
    this.resolutionDueAt,
    this.responseBreached = false,
    this.resolutionBreached = false,
    this.escalationLevel = 0,
    this.createdAt,
    this.updatedAt,
  });

  bool get slaBreached => responseBreached || resolutionBreached;

  factory HdTicketSummary.fromJson(Map<String, dynamic> j) => HdTicketSummary(
        id: (j['id'] as num).toInt(),
        ticketNumber: j['ticketNumber'] as String,
        title: j['title'] as String,
        category: j['category'] as String?,
        status: j['status'] as String? ?? 'OPEN',
        priority: j['priority'] as String? ?? 'MEDIUM',
        raisedByName: j['raisedByName'] as String?,
        assignedToName: j['assignedToName'] as String?,
        branchName: j['branchName'] as String?,
        department: j['department'] as String?,
        resolutionDueAt: _date(j['resolutionDueAt']),
        responseBreached: j['responseBreached'] == true,
        resolutionBreached: j['resolutionBreached'] == true,
        escalationLevel: (j['escalationLevel'] as num?)?.toInt() ?? 0,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// Config lookups for the raise screen.
class HdCategory {
  final int id;
  final String name;
  final String? departmentName;
  const HdCategory({required this.id, required this.name, this.departmentName});
  factory HdCategory.fromJson(Map<String, dynamic> j) => HdCategory(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        departmentName: j['departmentName'] as String?,
      );
}

class HdTicketType {
  final int id;
  final String name;
  const HdTicketType({required this.id, required this.name});
  factory HdTicketType.fromJson(Map<String, dynamic> j) =>
      HdTicketType(id: (j['id'] as num).toInt(), name: j['name'] as String);
}

/// A dynamic-form field definition (Phase 3).
class HdFormField {
  final String key;
  final String type;
  final String label;
  final String? placeholder;
  final String? helpText;
  final bool required;
  final bool hidden;
  final String? defaultValue;
  final List<String> options;
  final double? min;
  final double? max;
  final String? regex;
  final String? visibleWhenField;
  final String? visibleWhenEquals;

  const HdFormField({
    required this.key,
    required this.type,
    required this.label,
    this.placeholder,
    this.helpText,
    this.required = false,
    this.hidden = false,
    this.defaultValue,
    this.options = const [],
    this.min,
    this.max,
    this.regex,
    this.visibleWhenField,
    this.visibleWhenEquals,
  });

  factory HdFormField.fromJson(Map<String, dynamic> j) => HdFormField(
        key: j['key'] as String? ?? '',
        type: j['type'] as String? ?? 'text',
        label: j['label'] as String? ?? (j['key'] as String? ?? ''),
        placeholder: j['placeholder'] as String?,
        helpText: j['helpText'] as String?,
        required: j['required'] == true,
        hidden: j['hidden'] == true,
        defaultValue: j['defaultValue'] as String?,
        options: ((j['options'] as List?) ?? const []).map((e) => e.toString()).toList(),
        min: (j['min'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
        regex: j['regex'] as String?,
        visibleWhenField: j['visibleWhenField'] as String?,
        visibleWhenEquals: j['visibleWhenEquals'] as String?,
      );
}

class HdFormVersion {
  final int id;
  final int version;
  final List<HdFormField> fields;
  const HdFormVersion({required this.id, required this.version, required this.fields});
  factory HdFormVersion.fromJson(Map<String, dynamic> j) {
    final schema = (j['schema'] as Map<String, dynamic>?) ?? const {};
    return HdFormVersion(
      id: (j['id'] as num).toInt(),
      version: (j['version'] as num?)?.toInt() ?? 1,
      fields: ((schema['fields'] as List?) ?? const [])
          .map((e) => HdFormField.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class HdFormAnswer {
  final String key;
  final String label;
  final String value;
  const HdFormAnswer({required this.key, required this.label, required this.value});
  factory HdFormAnswer.fromJson(Map<String, dynamic> j) => HdFormAnswer(
        key: j['key'] as String? ?? '',
        label: j['label'] as String? ?? '',
        value: j['value'] as String? ?? '',
      );
}

// ── Knowledge Base (Phase 5) ──
class HdKbArticleSummary {
  final int id;
  final String title;
  final String? tags;
  final int helpfulCount;
  const HdKbArticleSummary({required this.id, required this.title, this.tags, this.helpfulCount = 0});
  factory HdKbArticleSummary.fromJson(Map<String, dynamic> j) => HdKbArticleSummary(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        tags: j['tags'] as String?,
        helpfulCount: (j['helpfulCount'] as num?)?.toInt() ?? 0,
      );
}

class HdKbArticle {
  final int id;
  final String title;
  final String? bodyHtml;
  final int helpfulCount;
  final int notHelpfulCount;
  const HdKbArticle({required this.id, required this.title, this.bodyHtml, this.helpfulCount = 0, this.notHelpfulCount = 0});
  factory HdKbArticle.fromJson(Map<String, dynamic> j) => HdKbArticle(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        bodyHtml: j['bodyHtml'] as String?,
        helpfulCount: (j['helpfulCount'] as num?)?.toInt() ?? 0,
        notHelpfulCount: (j['notHelpfulCount'] as num?)?.toInt() ?? 0,
      );
}

class HdKbSuggestion {
  final int id;
  final String title;
  final String snippet;
  const HdKbSuggestion({required this.id, required this.title, required this.snippet});
  factory HdKbSuggestion.fromJson(Map<String, dynamic> j) => HdKbSuggestion(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        snippet: j['snippet'] as String? ?? '',
      );
}

class HdComment {
  final int id;
  final String? authorName;
  final String body;
  final bool internalNote;
  final DateTime? createdAt;
  const HdComment({required this.id, this.authorName, required this.body, required this.internalNote, this.createdAt});
  factory HdComment.fromJson(Map<String, dynamic> j) => HdComment(
        id: (j['id'] as num).toInt(),
        authorName: j['authorName'] as String?,
        body: j['body'] as String? ?? '',
        internalNote: j['internalNote'] == true,
        createdAt: _date(j['createdAt']),
      );
}

class HdActivity {
  final int id;
  final String? actorName;
  final String type;
  final String? detail;
  final DateTime? createdAt;
  const HdActivity({required this.id, this.actorName, required this.type, this.detail, this.createdAt});
  factory HdActivity.fromJson(Map<String, dynamic> j) => HdActivity(
        id: (j['id'] as num).toInt(),
        actorName: j['actorName'] as String?,
        type: j['type'] as String? ?? '',
        detail: j['detail'] as String?,
        createdAt: _date(j['createdAt']),
      );
}

class HdAttachment {
  final int id;
  final String? fileName;
  const HdAttachment({required this.id, this.fileName});
  factory HdAttachment.fromJson(Map<String, dynamic> j) =>
      HdAttachment(id: (j['id'] as num).toInt(), fileName: j['fileName'] as String?);
}

class HdTicket {
  final HdTicketSummary summary;
  final String? description;
  final String? regionName;
  final String? reportingManagerName;
  final String? ticketTypeName;
  final DateTime? responseDueAt;
  final String? currentStageName;
  final List<String> availableActions;
  final List<HdComment> comments;
  final List<HdActivity> activities;
  final List<HdAttachment> attachments;
  final List<HdFormAnswer> formAnswers;

  const HdTicket({
    required this.summary,
    this.description,
    this.regionName,
    this.reportingManagerName,
    this.ticketTypeName,
    this.responseDueAt,
    this.currentStageName,
    this.availableActions = const [],
    this.comments = const [],
    this.activities = const [],
    this.attachments = const [],
    this.formAnswers = const [],
  });

  int get id => summary.id;

  factory HdTicket.fromJson(Map<String, dynamic> j) => HdTicket(
        summary: HdTicketSummary.fromJson(j),
        description: j['description'] as String?,
        regionName: j['regionName'] as String?,
        reportingManagerName: j['reportingManagerName'] as String?,
        ticketTypeName: j['ticketTypeName'] as String?,
        responseDueAt: _date(j['responseDueAt']),
        currentStageName: j['currentStageName'] as String?,
        availableActions: ((j['availableActions'] as List?) ?? const []).map((e) => e.toString()).toList(),
        formAnswers: ((j['formAnswers'] as List?) ?? const [])
            .map((e) => HdFormAnswer.fromJson(e as Map<String, dynamic>))
            .toList(),
        comments: ((j['comments'] as List?) ?? const [])
            .map((e) => HdComment.fromJson(e as Map<String, dynamic>))
            .toList(),
        activities: ((j['activities'] as List?) ?? const [])
            .map((e) => HdActivity.fromJson(e as Map<String, dynamic>))
            .toList(),
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((e) => HdAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A single label/value bucket in a dashboard breakdown.
class HdCount {
  const HdCount({required this.label, required this.value});
  final String label;
  final int value;

  factory HdCount.fromJson(Map<String, dynamic> j) => HdCount(
        label: (j['label'] ?? '').toString(),
        value: (j['value'] as num?)?.toInt() ?? 0,
      );
}

/// Scoped helpdesk dashboard metrics (Phase 6).
class HdDashboard {
  const HdDashboard({
    required this.total,
    required this.open,
    required this.inProgress,
    required this.onHold,
    required this.awaitingInfo,
    required this.resolved,
    required this.closed,
    required this.rejected,
    required this.cancelled,
    required this.slaBreached,
    this.avgFirstResponseMins,
    this.avgResolutionMins,
    required this.byStatus,
    required this.byPriority,
    required this.byCategory,
    required this.byBranch,
    required this.byAgent,
  });

  final int total, open, inProgress, onHold, awaitingInfo, resolved, closed, rejected, cancelled, slaBreached;
  final double? avgFirstResponseMins;
  final double? avgResolutionMins;
  final List<HdCount> byStatus, byPriority, byCategory, byBranch, byAgent;

  static List<HdCount> _counts(dynamic v) =>
      ((v as List?) ?? const []).map((e) => HdCount.fromJson(e as Map<String, dynamic>)).toList();

  factory HdDashboard.fromJson(Map<String, dynamic> j) => HdDashboard(
        total: (j['total'] as num?)?.toInt() ?? 0,
        open: (j['open'] as num?)?.toInt() ?? 0,
        inProgress: (j['inProgress'] as num?)?.toInt() ?? 0,
        onHold: (j['onHold'] as num?)?.toInt() ?? 0,
        awaitingInfo: (j['awaitingInfo'] as num?)?.toInt() ?? 0,
        resolved: (j['resolved'] as num?)?.toInt() ?? 0,
        closed: (j['closed'] as num?)?.toInt() ?? 0,
        rejected: (j['rejected'] as num?)?.toInt() ?? 0,
        cancelled: (j['cancelled'] as num?)?.toInt() ?? 0,
        slaBreached: (j['slaBreached'] as num?)?.toInt() ?? 0,
        avgFirstResponseMins: (j['avgFirstResponseMins'] as num?)?.toDouble(),
        avgResolutionMins: (j['avgResolutionMins'] as num?)?.toDouble(),
        byStatus: _counts(j['byStatus']),
        byPriority: _counts(j['byPriority']),
        byCategory: _counts(j['byCategory']),
        byBranch: _counts(j['byBranch']),
        byAgent: _counts(j['byAgent']),
      );
}
