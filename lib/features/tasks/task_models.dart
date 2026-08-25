import 'dart:convert';

/// The task lifecycle states exposed by the new backend API.
/// (`PENDING` no longer exists — the initial state is `TODO`.)
class TaskStatuses {
  static const todo = 'TODO';
  static const inProgress = 'IN_PROGRESS';
  static const inReview = 'IN_REVIEW';
  static const done = 'DONE';
  static const cancelled = 'CANCELLED';
  static const rejected = 'REJECTED';
}

DateTime? _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

double? _parseDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String && v.isNotEmpty) return double.tryParse(v);
  return null;
}

class Task {
  Task({
    required this.id,
    required this.title,
    required this.status,
    this.taskCode,
    this.taskType,
    this.customerId,
    this.customerName,
    this.description,
    this.dueDate,
    this.dueTime,
    this.assignedToId,
    this.assignedToName,
    this.assignedById,
    this.assignedByName,
    this.reviewerId,
    this.reviewerName,
    this.categoryId,
    this.categoryName,
    this.priority,
    this.startDate,
    this.estimatedHours,
    this.completedAt,
    this.completionLat,
    this.completionLng,
    this.completionAddress,
    this.createdAt,
    this.formSchema,
    this.formResponse,
    this.requiresReview = false,
    this.allowSelfCompletion = true,
    this.allowAttachments = false,
    this.completionPercentage = 0,
  });

  final int id;
  final String title;
  final String status;
  final String? taskCode;
  /// INTERNAL or CUSTOMER.
  final String? taskType;
  final int? customerId;
  final String? customerName;
  final String? description;

  bool get isCustomerTask => (taskType ?? '').toUpperCase() == 'CUSTOMER';
  final DateTime? dueDate;
  /// Time-of-day deadline, serialized as "HH:mm[:ss]" by the backend.
  final String? dueTime;
  final int? assignedToId;
  final String? assignedToName;
  final int? assignedById;
  final String? assignedByName;
  final int? reviewerId;
  final String? reviewerName;
  final int? categoryId;
  final String? categoryName;
  final String? priority;
  final DateTime? startDate;
  final double? estimatedHours;
  final DateTime? completedAt;
  final double? completionLat;
  final double? completionLng;
  final String? completionAddress;
  final DateTime? createdAt;

  /// JSON string describing the form fields the assignee must fill.
  final String? formSchema;

  /// JSON string with the submitted values (null if not submitted yet).
  final String? formResponse;

  final bool requiresReview;
  final bool allowSelfCompletion;
  final bool allowAttachments;
  final int completionPercentage;

  /// Terminal states — no further action is expected from the assignee.
  bool get isClosed =>
      status == TaskStatuses.done ||
      status == TaskStatuses.cancelled ||
      status == TaskStatuses.rejected;

  bool get isDone => status == TaskStatuses.done;
  bool get isInReview => status == TaskStatuses.inReview;

  /// Whether the assignee can still move this task forward.
  bool get isActionable =>
      status == TaskStatuses.todo || status == TaskStatuses.inProgress;

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? 'Untitled task',
      status: json['status'] as String? ?? 'UNKNOWN',
      taskCode: json['taskCode'] as String?,
      taskType: json['taskType'] as String?,
      customerId: (json['customerId'] as num?)?.toInt(),
      customerName: json['customerName'] as String?,
      description: json['description'] as String?,
      dueDate: _parseDate(json['dueDate']),
      dueTime: json['dueTime'] as String?,
      assignedToId: (json['assignedToId'] as num?)?.toInt(),
      assignedToName: json['assignedToName'] as String?,
      assignedById: (json['assignedById'] as num?)?.toInt(),
      assignedByName: json['assignedByName'] as String?,
      reviewerId: (json['reviewerEmployeeId'] as num?)?.toInt(),
      reviewerName: json['reviewerName'] as String?,
      categoryId: (json['categoryId'] as num?)?.toInt(),
      categoryName: json['categoryName'] as String?,
      priority: json['priority'] as String?,
      startDate: _parseDate(json['startDate']),
      estimatedHours: _parseDouble(json['estimatedHours']),
      completedAt: _parseDate(json['completedAt']),
      completionLat: _parseDouble(json['completionLat']),
      completionLng: _parseDouble(json['completionLng']),
      completionAddress: json['completionAddress'] as String?,
      createdAt: _parseDate(json['createdAt']),
      formSchema: json['formSchema'] as String?,
      formResponse: json['formResponse'] as String?,
      requiresReview: json['requiresReview'] == true,
      allowSelfCompletion: json['allowSelfCompletion'] != false,
      allowAttachments: json['allowAttachments'] == true,
      completionPercentage: (json['completionPercentage'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A comment on the task's discussion thread (`GET/POST /api/tasks/{id}/comments`).
class TaskComment {
  TaskComment({
    required this.id,
    required this.commentText,
    this.employeeId,
    this.employeeName,
    this.commentType,
    this.createdAt,
  });

  final int id;
  final String commentText;
  final int? employeeId;
  final String? employeeName;
  final String? commentType;
  final DateTime? createdAt;

  factory TaskComment.fromJson(Map<String, dynamic> j) => TaskComment(
        id: (j['id'] as num).toInt(),
        commentText: j['commentText'] as String? ?? '',
        employeeId: (j['employeeId'] as num?)?.toInt(),
        employeeName: j['employeeName'] as String?,
        commentType: j['commentType'] as String?,
        createdAt: _parseDate(j['createdAt']),
      );
}

/// One entry in a task's status/audit history (`GET /api/tasks/{id}/history`).
class TaskHistoryEntry {
  TaskHistoryEntry({
    required this.id,
    this.oldStatus,
    this.newStatus,
    this.changedByName,
    this.changeReason,
    this.changedField,
    this.oldValue,
    this.newValue,
    this.createdAt,
  });

  final int id;
  final String? oldStatus;
  final String? newStatus;
  final String? changedByName;
  final String? changeReason;
  final String? changedField;
  final String? oldValue;
  final String? newValue;
  final DateTime? createdAt;

  /// True for a status transition (vs a field edit).
  bool get isStatusChange => (newStatus ?? '').isNotEmpty;

  factory TaskHistoryEntry.fromJson(Map<String, dynamic> j) => TaskHistoryEntry(
        id: (j['id'] as num).toInt(),
        oldStatus: j['oldStatus'] as String?,
        newStatus: j['newStatus'] as String?,
        changedByName: j['changedByName'] as String?,
        changeReason: j['changeReason'] as String?,
        changedField: j['changedField'] as String?,
        oldValue: j['oldValue'] as String?,
        newValue: j['newValue'] as String?,
        createdAt: _parseDate(j['createdAt']),
      );
}

/// Logged-in employee's task summary (`GET /api/tasks/dashboard`).
class TaskDashboard {
  TaskDashboard({
    required this.totalTasks,
    required this.myPending,
    required this.myInProgress,
    required this.myInReview,
    required this.myOverdue,
    required this.myDoneThisMonth,
    required this.pendingReview,
    required this.createdByMe,
    required this.urgentTasks,
  });

  final int totalTasks;
  final int myPending;
  final int myInProgress;
  final int myInReview;
  final int myOverdue;
  final int myDoneThisMonth;
  final int pendingReview;
  final int createdByMe;
  final int urgentTasks;

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory TaskDashboard.fromJson(Map<String, dynamic> j) => TaskDashboard(
        totalTasks: _i(j['totalTasks']),
        myPending: _i(j['myPending']),
        myInProgress: _i(j['myInProgress']),
        myInReview: _i(j['myInReview']),
        myOverdue: _i(j['myOverdue']),
        myDoneThisMonth: _i(j['myDoneThisMonth']),
        pendingReview: _i(j['pendingReview']),
        createdByMe: _i(j['createdByMe']),
        urgentTasks: _i(j['urgentTasks']),
      );
}

// ---------------- Form schema (mirrors web FormBuilder JSON) ----------------

/// Supported field types. Unknown types fall back to plain text.
/// Every field type the task form builder can author.
///
/// This list is the mirror of the backend's `TaskFormFieldType`: one value per
/// `fieldKey` it defines. Keeping it complete is the point — anything missing
/// used to fall through to [FieldType.text], so a form asking for a GPS reading,
/// a signature or a rating quietly became a box to type into.
enum FieldType {
  // ── Basic ────────────────────────────────────────────────────────────────
  text,
  textarea,
  number,
  decimal,
  mobile,
  email,
  url,
  password,
  otp,

  // ── Date & time ──────────────────────────────────────────────────────────
  date,
  time,
  datetime,
  daterange,
  day,
  month,
  year,
  dateofbirth,
  duration,

  // ── Selection ────────────────────────────────────────────────────────────
  select,
  multiselect,
  radio,
  checkbox,
  toggle,
  buttongroup,
  likert,

  // ── File & media ─────────────────────────────────────────────────────────
  file,
  multiimage,
  image,
  video,
  audio,
  signature,
  drawing,
  webcam,

  // ── HRMS master data ─────────────────────────────────────────────────────
  employeeSelector,
  departmentSelector,
  branchSelector,
  designationSelector,
  roleSelector,
  leaveTypeSelector,
  shiftSelector,
  locationSelector,

  // ── Task ─────────────────────────────────────────────────────────────────
  taskSelector,
  taskStatusField,
  taskPriorityField,
  taskCategoryField,

  // ── Approval ─────────────────────────────────────────────────────────────
  approval,
  esignature,
  witness,
  checklistApproval,

  // ── Layout (renders itself, stores nothing) ──────────────────────────────
  section,
  divider,
  heading,
  paragraph,
  spacer,

  // ── Table / repeatable ───────────────────────────────────────────────────
  table,
  repeatableSection,
  matrix,

  // ── Calculation & system (filled for the user, not by them) ──────────────
  formula,
  hidden,
  readOnly,
  sequenceNumber,
  timestampField,
  currentUserField,
  currentBranchField,

  // ── Location & scanner ───────────────────────────────────────────────────
  gpsLocation,
  mapPoint,
  qrScanner,
  barcodeScanner,
  nfcTag,

  // ── Rating & feedback ────────────────────────────────────────────────────
  starRating,
  npsScore,
  emojiRating,
  sliderRating,
  ranking,

  // ── Finance & business ───────────────────────────────────────────────────
  currency,
  percentage,
  quantity,
  uomSelector,
  bankAccount,
  ifscLookup,
  panNumber,
  aadhaarNumber,
  gstNumber;

  /// Field types that draw their own block: no label, no value, no validation.
  bool get isLayout =>
      this == section ||
      this == divider ||
      this == heading ||
      this == paragraph ||
      this == spacer;

  /// Field types the server or the form fills in — the user never types them.
  bool get isSystem =>
      this == formula ||
      this == hidden ||
      this == readOnly ||
      this == sequenceNumber ||
      this == timestampField ||
      this == currentUserField ||
      this == currentBranchField;

  /// Whether an answer is a free-length string that character limits shouldn't
  /// police (a captured coordinate, a scanned code, an uploaded signature).
  bool get isCaptured =>
      this == gpsLocation ||
      this == mapPoint ||
      this == qrScanner ||
      this == barcodeScanner ||
      this == nfcTag;

  /// Resolves a `formSchema` type key onto a value.
  ///
  /// Matching ignores case and separators, so `gps_location`, `GPS_LOCATION` and
  /// `gpsLocation` all land on the same type. Legacy and web-only keys are then
  /// mapped by hand, and only after all of that does an unrecognised key fall
  /// back to a text box.
  static FieldType from(String s) {
    final v = s.trim().toLowerCase();
    final squashed = v.replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final t in values) {
      if (t.name.toLowerCase() == squashed) return t;
    }

    switch (squashed) {
      // Media-capture aliases authored by older versions of the web builder.
      case 'photo':
      case 'camera':
      case 'imagecapture':
      case 'singleimage':
        return FieldType.image;
      case 'images':
      case 'multiimages':
        return FieldType.multiimage;
      case 'attachment':
      case 'document':
      case 'fileupload':
        return FieldType.file;
      // Location capture.
      case 'gps':
      case 'geolocation':
      case 'geo':
        return FieldType.gpsLocation;
      case 'map':
      case 'mappicker':
        return FieldType.mapPoint;
      case 'qr':
      case 'qrcode':
      case 'scanner':
        return FieldType.qrScanner;
      case 'barcode':
        return FieldType.barcodeScanner;
      case 'nfc':
        return FieldType.nfcTag;
      // Date keys the web renderer accepts but the backend enum does not list.
      case 'taskduedate':
      case 'taskstartdate':
      case 'taskcompletiondate':
        return FieldType.date;
      case 'dob':
        return FieldType.dateofbirth;
      case 'rating':
        return FieldType.starRating;
      case 'dropdown':
        return FieldType.select;
      case 'switch':
        return FieldType.toggle;
      case 'signaturepad':
        return FieldType.signature;
    }

    // Last resort: a variant key that still names a media field should open an
    // uploader rather than a text box.
    if (squashed.contains('multiimage')) return FieldType.multiimage;
    if (squashed.contains('image') ||
        squashed.contains('photo') ||
        squashed.contains('camera') ||
        squashed.contains('webcam') ||
        squashed.contains('picture')) {
      return FieldType.image;
    }
    if (squashed.contains('video')) return FieldType.video;
    if (squashed.contains('audio') || squashed.contains('voice')) {
      return FieldType.audio;
    }
    if (squashed.contains('file') ||
        squashed.contains('attach') ||
        squashed.contains('upload')) {
      return FieldType.file;
    }
    return FieldType.text;
  }
}

class FieldCondition {
  final String field;
  final String operator;
  final String? value;
  FieldCondition({required this.field, required this.operator, this.value});

  factory FieldCondition.fromJson(Map<String, dynamic> j) => FieldCondition(
        field: j['field'] as String,
        operator: j['operator'] as String,
        value: j['value'] as String?,
      );
}

class FormFieldDef {
  final String id;
  final FieldType type;
  final String label;
  final String name;
  final bool required;
  final String? placeholder;
  final String? helpText;
  final List<String> options;
  final int? maxLength;
  final int? minLength;
  final num? min;
  final num? max;
  /// Currency code for a `currency` field (e.g. "INR"). Null = the app default.
  final String? currencyCode;
  /// The expression behind a `formula` field, shown so the user knows what is
  /// being computed for them.
  final String? expression;
  final List<FieldCondition> visibleWhen;
  final String visibleWhenLogic; // "all" | "any"
  /// True when the assigner pre-fills this field at task-creation time.
  /// The assignee sees the value but cannot edit it.
  final bool assigned;

  FormFieldDef({
    required this.id,
    required this.type,
    required this.label,
    required this.name,
    required this.required,
    this.placeholder,
    this.helpText,
    this.options = const [],
    this.maxLength,
    this.minLength,
    this.min,
    this.max,
    this.currencyCode,
    this.expression,
    this.visibleWhen = const [],
    this.visibleWhenLogic = 'all',
    this.assigned = false,
  });

  factory FormFieldDef.fromJson(Map<String, dynamic> j) {
    final opts = (j['options'] as List?)?.cast<String>() ?? const <String>[];
    final conds = (j['visibleWhen'] as List?)
            ?.map((e) => FieldCondition.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <FieldCondition>[];
    return FormFieldDef(
      id: j['id'] as String,
      type: FieldType.from(j['type'] as String),
      label: j['label'] as String? ?? '',
      name: j['name'] as String,
      required: j['required'] == true,
      placeholder: j['placeholder'] as String?,
      helpText: j['helpText'] as String?,
      options: opts,
      maxLength: (j['maxLength'] as num?)?.toInt(),
      minLength: (j['minLength'] as num?)?.toInt(),
      min: j['min'] as num?,
      max: j['max'] as num?,
      currencyCode: j['currencyCode'] as String?,
      expression: j['expression'] as String?,
      visibleWhen: conds,
      visibleWhenLogic: (j['visibleWhenLogic'] as String?) ?? 'all',
      assigned: j['assigned'] == true,
    );
  }
}

class FormSchema {
  final List<FormFieldDef> fields;
  FormSchema(this.fields);

  static FormSchema? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic> && j['fields'] is List) {
        final list = (j['fields'] as List)
            .map((e) => FormFieldDef.fromJson(e as Map<String, dynamic>))
            .toList();
        return FormSchema(list);
      }
    } catch (_) {/* ignore */}
    return null;
  }
}

typedef FormValues = Map<String, dynamic>;

FormValues parseFormValues(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final j = jsonDecode(raw);
    if (j is Map<String, dynamic>) return j;
  } catch (_) {/* ignore */}
  return {};
}

bool isFieldVisible(FormFieldDef f, FormValues values) {
  if (f.visibleWhen.isEmpty) return true;
  final results = f.visibleWhen.map((c) => _match(c, values[c.field]));
  return f.visibleWhenLogic == 'any'
      ? results.any((r) => r)
      : results.every((r) => r);
}

bool _match(FieldCondition c, dynamic v) {
  final isEmpty = v == null || v == '' || (v is List && v.isEmpty);
  if (c.operator == 'is_empty') return isEmpty;
  if (c.operator == 'is_not_empty') return !isEmpty;
  final target = (c.value ?? '').trim();
  if (v is List) {
    final list = v.cast<String>();
    switch (c.operator) {
      case 'equals': return list.length == 1 && list.first == target;
      case 'not_equals': return !(list.length == 1 && list.first == target);
      case 'contains': return list.contains(target);
      case 'not_contains': return !list.contains(target);
    }
  }
  final s = v == null ? '' : v.toString();
  switch (c.operator) {
    case 'equals': return s == target;
    case 'not_equals': return s != target;
    case 'contains': return s.toLowerCase().contains(target.toLowerCase());
    case 'not_contains': return !s.toLowerCase().contains(target.toLowerCase());
  }
  return false;
}
