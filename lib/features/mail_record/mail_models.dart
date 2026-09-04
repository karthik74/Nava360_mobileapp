// Admin Tools — Mail Record models — mirror of the backend
// `AdminMail*`/`AdminComplaint*` DTOs (see nava360-web `src/types.ts` lines
// ~3425-3613 and `src/api/adminMail.ts`, and the Spring Mail controller/DTOs).
// Ported near-verbatim from the standalone office "Mail_Record" app: an
// inward/outward mail register with per-record edit history, a monthly
// branch-audit workflow (start → complete), stationery stock per branch with
// inter-branch shipments (dispatch → partially received → received),
// configurable complaint departments, a complaint workflow (pending →
// in-progress → resolved/escalated/rejected) with a status-change history,
// and a shared audit trail — the biggest/most complex of the four Admin
// Tools screens, mirroring `AdminMailPage.tsx`'s six tabs.

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

int? _int(dynamic v) => (v as num?)?.toInt();

/// Mail register entry direction (`AdminMailType`).
class MailType {
  MailType._();
  static const inward = 'INWARD';
  static const outward = 'OUTWARD';
  static const values = <String>[inward, outward];
}

/// Branch-month audit workflow states (`AdminMailAuditStatus`).
class MailAuditStatus {
  MailAuditStatus._();
  static const pending = 'PENDING';
  static const inProgress = 'IN_PROGRESS';
  static const completed = 'COMPLETED';
}

/// Inter-branch stationery shipment workflow states (`AdminMailShipmentStatus`).
class MailShipmentStatus {
  MailShipmentStatus._();
  static const dispatched = 'DISPATCHED';
  static const partiallyReceived = 'PARTIALLY_RECEIVED';
  static const received = 'RECEIVED';
}

/// Complaint workflow states (`AdminComplaintStatus`).
class MailComplaintStatus {
  MailComplaintStatus._();
  static const pending = 'PENDING';
  static const inProgress = 'IN_PROGRESS';
  static const resolved = 'RESOLVED';
  static const escalated = 'ESCALATED';
  static const rejected = 'REJECTED';
  static const values = <String>[pending, inProgress, resolved, escalated, rejected];
}

/// Lightweight branch option for pickers (`/api/org/branches`), shared
/// across the register/audit/stock/complaint forms.
class MailBranchOption {
  final int id;
  final String label;
  final bool active;

  const MailBranchOption({required this.id, required this.label, this.active = true});

  factory MailBranchOption.fromJson(Map<String, dynamic> j) => MailBranchOption(
        id: (j['id'] as num).toInt(),
        label: (j['label'] as String?) ?? (j['code'] as String?) ?? 'Branch',
        active: j['active'] as bool? ?? true,
      );
}

/// One mail-register entry (`AdminMailRecord`).
class MailRecord {
  final int id;
  final String mailType;
  final DateTime? date;
  final int? branchId;
  final String? branchLabel;
  final int? employeeId;
  final String? employeeName;
  final String? department;
  final String? documents;
  final String? docketNumber;
  final String? courierStatus;
  final String? particular;
  final String? details;
  final String? customersJson;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MailRecord({
    required this.id,
    required this.mailType,
    this.date,
    this.branchId,
    this.branchLabel,
    this.employeeId,
    this.employeeName,
    this.department,
    this.documents,
    this.docketNumber,
    this.courierStatus,
    this.particular,
    this.details,
    this.customersJson,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory MailRecord.fromJson(Map<String, dynamic> j) => MailRecord(
        id: (j['id'] as num).toInt(),
        mailType: j['mailType'] as String? ?? MailType.inward,
        date: _date(j['date']),
        branchId: _int(j['branchId']),
        branchLabel: j['branchLabel'] as String?,
        employeeId: _int(j['employeeId']),
        employeeName: j['employeeName'] as String?,
        department: j['department'] as String?,
        documents: j['documents'] as String?,
        docketNumber: j['docketNumber'] as String?,
        courierStatus: j['courierStatus'] as String?,
        particular: j['particular'] as String?,
        details: j['details'] as String?,
        customersJson: j['customersJson'] as String?,
        createdBy: j['createdBy'] as String?,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// One field-level edit-history row of a mail record (`AdminMailEditLog`).
class MailEditLog {
  final int id;
  final int recordId;
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String? editedBy;
  final DateTime? editedAt;

  MailEditLog({
    required this.id,
    required this.recordId,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    this.editedBy,
    this.editedAt,
  });

  factory MailEditLog.fromJson(Map<String, dynamic> j) => MailEditLog(
        id: (j['id'] as num).toInt(),
        recordId: (j['recordId'] as num?)?.toInt() ?? 0,
        fieldName: j['fieldName'] as String? ?? '',
        oldValue: j['oldValue'] as String?,
        newValue: j['newValue'] as String?,
        editedBy: j['editedBy'] as String?,
        editedAt: _date(j['editedAt']),
      );
}

/// One branch's audit status for a given month (`AdminMailAuditBranchMonth`).
class MailAuditBranchMonth {
  final int id;
  final String auditMonth;
  final int branchId;
  final String branchLabel;
  final String status;
  final String? startedBy;
  final DateTime? startedAt;
  final String? completedBy;
  final DateTime? completedAt;

  MailAuditBranchMonth({
    required this.id,
    required this.auditMonth,
    required this.branchId,
    required this.branchLabel,
    required this.status,
    this.startedBy,
    this.startedAt,
    this.completedBy,
    this.completedAt,
  });

  factory MailAuditBranchMonth.fromJson(Map<String, dynamic> j) => MailAuditBranchMonth(
        id: (j['id'] as num).toInt(),
        auditMonth: j['auditMonth'] as String? ?? '',
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchLabel: j['branchLabel'] as String? ?? '',
        status: j['status'] as String? ?? MailAuditStatus.pending,
        startedBy: j['startedBy'] as String?,
        startedAt: _date(j['startedAt']),
        completedBy: j['completedBy'] as String?,
        completedAt: _date(j['completedAt']),
      );
}

/// One branch's stock level for one item (`AdminMailStockEntry`).
class MailStockEntry {
  final int id;
  final int branchId;
  final String branchLabel;
  final String itemName;
  final num quantity;
  final String? unit;
  final String? updatedBy;
  final DateTime? updatedAt;

  MailStockEntry({
    required this.id,
    required this.branchId,
    required this.branchLabel,
    required this.itemName,
    required this.quantity,
    this.unit,
    this.updatedBy,
    this.updatedAt,
  });

  factory MailStockEntry.fromJson(Map<String, dynamic> j) => MailStockEntry(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchLabel: j['branchLabel'] as String? ?? '',
        itemName: j['itemName'] as String? ?? '',
        quantity: (j['quantity'] as num?) ?? 0,
        unit: j['unit'] as String?,
        updatedBy: j['updatedBy'] as String?,
        updatedAt: _date(j['updatedAt']),
      );
}

/// One inter-branch stationery shipment (`AdminMailShipment`). Workflow:
/// DISPATCHED → (partial receive) → PARTIALLY_RECEIVED → (full receive) →
/// RECEIVED, or DISPATCHED straight to RECEIVED on a single full receipt.
class MailShipment {
  final int id;
  final String batchId;
  final int fromBranchId;
  final String fromBranchLabel;
  final int toBranchId;
  final String toBranchLabel;
  final String itemName;
  final num quantity;
  final num receivedQuantity;
  final String status;
  final String? dispatchedBy;
  final String? receivedBy;
  final DateTime? receivedAt;
  final DateTime? createdAt;

  MailShipment({
    required this.id,
    required this.batchId,
    required this.fromBranchId,
    required this.fromBranchLabel,
    required this.toBranchId,
    required this.toBranchLabel,
    required this.itemName,
    required this.quantity,
    required this.receivedQuantity,
    required this.status,
    this.dispatchedBy,
    this.receivedBy,
    this.receivedAt,
    this.createdAt,
  });

  factory MailShipment.fromJson(Map<String, dynamic> j) => MailShipment(
        id: (j['id'] as num).toInt(),
        batchId: j['batchId'] as String? ?? '',
        fromBranchId: (j['fromBranchId'] as num?)?.toInt() ?? 0,
        fromBranchLabel: j['fromBranchLabel'] as String? ?? '',
        toBranchId: (j['toBranchId'] as num?)?.toInt() ?? 0,
        toBranchLabel: j['toBranchLabel'] as String? ?? '',
        itemName: j['itemName'] as String? ?? '',
        quantity: (j['quantity'] as num?) ?? 0,
        receivedQuantity: (j['receivedQuantity'] as num?) ?? 0,
        status: j['status'] as String? ?? MailShipmentStatus.dispatched,
        dispatchedBy: j['dispatchedBy'] as String?,
        receivedBy: j['receivedBy'] as String?,
        receivedAt: _date(j['receivedAt']),
        createdAt: _date(j['createdAt']),
      );
}

/// One configured complaint department (`AdminComplaintDeptConfig`).
class MailComplaintDept {
  final int id;
  final String deptKey;
  final String name;
  final String? icon;
  final String? problemsJson;
  final String? deptCode;
  final int sortOrder;
  final bool active;

  MailComplaintDept({
    required this.id,
    required this.deptKey,
    required this.name,
    this.icon,
    this.problemsJson,
    this.deptCode,
    this.sortOrder = 0,
    this.active = true,
  });

  factory MailComplaintDept.fromJson(Map<String, dynamic> j) => MailComplaintDept(
        id: (j['id'] as num).toInt(),
        deptKey: j['deptKey'] as String? ?? '',
        name: j['name'] as String? ?? '',
        icon: j['icon'] as String?,
        problemsJson: j['problemsJson'] as String?,
        deptCode: j['deptCode'] as String?,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        active: j['active'] as bool? ?? true,
      );
}

/// One complaint (`AdminComplaint`). Workflow: PENDING → IN_PROGRESS →
/// (RESOLVED | ESCALATED | REJECTED); the web allows a direct jump to any
/// other status from the "Change status…" dropdown, so this app mirrors
/// that — every non-current status is offered as a transition, not a
/// strict linear state machine.
class MailComplaint {
  final int id;
  final int branchId;
  final String branchLabel;
  final DateTime? date;
  final int? deptId;
  final String? deptName;
  final String subject;
  final String? content;
  final int? raisedByEmployeeId;
  final String? raisedByName;
  final String? phone;
  final String status;
  final String? resolutionNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MailComplaint({
    required this.id,
    required this.branchId,
    required this.branchLabel,
    this.date,
    this.deptId,
    this.deptName,
    required this.subject,
    this.content,
    this.raisedByEmployeeId,
    this.raisedByName,
    this.phone,
    required this.status,
    this.resolutionNote,
    this.createdAt,
    this.updatedAt,
  });

  factory MailComplaint.fromJson(Map<String, dynamic> j) => MailComplaint(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchLabel: j['branchLabel'] as String? ?? '',
        date: _date(j['date']),
        deptId: _int(j['deptId']),
        deptName: j['deptName'] as String?,
        subject: j['subject'] as String? ?? '',
        content: j['content'] as String?,
        raisedByEmployeeId: _int(j['raisedByEmployeeId']),
        raisedByName: j['raisedByName'] as String?,
        phone: j['phone'] as String?,
        status: j['status'] as String? ?? MailComplaintStatus.pending,
        resolutionNote: j['resolutionNote'] as String?,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// One status-change history row of a complaint (`AdminComplaintLog`).
class MailComplaintLog {
  final int id;
  final int complaintId;
  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? note;
  final String? byUser;
  final DateTime? createdAt;

  MailComplaintLog({
    required this.id,
    required this.complaintId,
    required this.action,
    this.fromStatus,
    this.toStatus,
    this.note,
    this.byUser,
    this.createdAt,
  });

  factory MailComplaintLog.fromJson(Map<String, dynamic> j) => MailComplaintLog(
        id: (j['id'] as num).toInt(),
        complaintId: (j['complaintId'] as num?)?.toInt() ?? 0,
        action: j['action'] as String? ?? '',
        fromStatus: j['fromStatus'] as String?,
        toStatus: j['toStatus'] as String?,
        note: j['note'] as String?,
        byUser: j['byUser'] as String?,
        createdAt: _date(j['createdAt']),
      );
}

/// One row of `/api/admin/mail/audit` (`AdminMailAuditLog`).
class MailAuditLog {
  final int id;
  final String entityType;
  final int? entityId;
  final String action;
  final int? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String? beforeJson;
  final String? afterJson;
  final String? metaJson;
  final DateTime? createdAt;

  MailAuditLog({
    required this.id,
    required this.entityType,
    required this.action,
    this.entityId,
    this.actorUserId,
    this.actorName,
    this.actorRole,
    this.beforeJson,
    this.afterJson,
    this.metaJson,
    this.createdAt,
  });

  factory MailAuditLog.fromJson(Map<String, dynamic> j) => MailAuditLog(
        id: (j['id'] as num).toInt(),
        entityType: j['entityType'] as String? ?? '',
        entityId: _int(j['entityId']),
        action: j['action'] as String? ?? '',
        actorUserId: _int(j['actorUserId']),
        actorName: j['actorName'] as String?,
        actorRole: j['actorRole'] as String?,
        beforeJson: j['beforeJson'] as String?,
        afterJson: j['afterJson'] as String?,
        metaJson: j['metaJson'] as String?,
        createdAt: _date(j['createdAt']),
      );
}
