// Admin Tools — Mail Record models — mirror of the backend
// `AdminMail*`/`AdminComplaint*` DTOs (see nava360-web `src/types.ts` lines
// ~3425-3613 and `src/api/adminMail.ts`, and the Spring Mail controller/DTOs).
// Ported near-verbatim from the standalone office "Mail_Record" app: an
// inward/outward mail register with per-record edit history, stationery
// stock per branch with
// inter-branch shipments (dispatch → partially received → received),
// configurable complaint departments, a complaint workflow (pending →
// in-progress → resolved/rejected) with a status-change history,
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
  static const rejected = 'REJECTED';
  static const values = <String>[pending, inProgress, resolved, rejected];
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
  /// The branch label, or the free-text "Others" party when there's no branch.
  final String? branchLabel;
  /// Free-text counterparty when the mail isn't from/to a listed branch.
  final String? otherParty;
  /// Outward entries only.
  final double? amount;
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
    this.otherParty,
    this.amount,
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
        otherParty: j['otherParty'] as String?,
        amount: (j['amount'] as num?)?.toDouble(),
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

/// One branch's stock level for one item (`AdminMailStockEntry`).
class MailStockEntry {
  final int id;
  final int branchId;
  final String branchLabel;
  final String itemName;
  final num quantity;
  /// Invoice this item was bought on.
  final String? invoice;
  final bool lowStock;
  final String? updatedBy;
  final DateTime? updatedAt;

  MailStockEntry({
    required this.id,
    required this.branchId,
    required this.branchLabel,
    required this.itemName,
    required this.quantity,
    this.invoice,
    this.lowStock = false,
    this.updatedBy,
    this.updatedAt,
  });

  factory MailStockEntry.fromJson(Map<String, dynamic> j) => MailStockEntry(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchLabel: j['branchLabel'] as String? ?? '',
        itemName: j['itemName'] as String? ?? '',
        quantity: (j['quantity'] as num?) ?? 0,
        invoice: j['invoice'] as String?,
        lowStock: j['lowStock'] as bool? ?? false,
        updatedBy: j['updatedBy'] as String?,
        updatedAt: _date(j['updatedAt']),
      );
}

/// One (branch, item) at or below the item's low-stock threshold (`AdminMailStockLowStockResponse.Row`).
class MailLowStockRow {
  final int branchId;
  final String branchLabel;
  final String itemName;
  final String? invoice;
  final int quantity;
  final int lowStockThreshold;

  MailLowStockRow({
    required this.branchId,
    required this.branchLabel,
    required this.itemName,
    this.invoice,
    required this.quantity,
    required this.lowStockThreshold,
  });

  factory MailLowStockRow.fromJson(Map<String, dynamic> j) => MailLowStockRow(
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchLabel: j['branchLabel'] as String? ?? '',
        itemName: j['itemName'] as String? ?? '',
        invoice: j['invoice'] as String?,
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (j['lowStockThreshold'] as num?)?.toInt() ?? 0,
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

/// One complaint (`AdminComplaint`). Workflow: PENDING → IN_PROGRESS → (RESOLVED | REJECTED); only a
/// full-access admin moves it, and the server sends exactly which moves are allowed from the current status
/// ([allowedNext]), so this app never guesses at the state machine.
class MailComplaint {
  final int id;
  final int branchId;
  final String branchLabel;
  final String? stateName;
  final String? regionName;
  final String? divisionName;
  final String? areaName;
  final DateTime? date;
  /// Department name from the HR department list.
  final String? department;
  final String subject;
  final String? content;
  final int? raisedByEmployeeId;
  final String? raisedByName;
  final String? raisedByCode;
  final String? phone;
  final String status;
  final List<String> allowedNext;
  final String? resolutionNote;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MailComplaint({
    required this.id,
    required this.branchId,
    required this.branchLabel,
    this.stateName,
    this.regionName,
    this.divisionName,
    this.areaName,
    this.date,
    this.department,
    required this.subject,
    this.content,
    this.raisedByEmployeeId,
    this.raisedByName,
    this.raisedByCode,
    this.phone,
    required this.status,
    this.allowedNext = const [],
    this.resolutionNote,
    this.resolvedBy,
    this.resolvedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory MailComplaint.fromJson(Map<String, dynamic> j) => MailComplaint(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchLabel: j['branchLabel'] as String? ?? '',
        stateName: j['stateName'] as String?,
        regionName: j['regionName'] as String?,
        divisionName: j['divisionName'] as String?,
        areaName: j['areaName'] as String?,
        date: _date(j['date']),
        department: j['department'] as String?,
        subject: j['subject'] as String? ?? '',
        content: j['content'] as String?,
        raisedByEmployeeId: _int(j['raisedByEmployeeId']),
        raisedByName: j['raisedByName'] as String?,
        raisedByCode: j['raisedByCode'] as String?,
        phone: j['phone'] as String?,
        status: j['status'] as String? ?? MailComplaintStatus.pending,
        allowedNext: ((j['allowedNext'] as List?) ?? const []).map((e) => '$e').toList(),
        resolutionNote: j['resolutionNote'] as String?,
        resolvedBy: j['resolvedBy'] as String?,
        resolvedAt: _date(j['resolvedAt']),
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// How many complaints were raised on one day (`AdminComplaintDateCount`) — shows the user where the data is.
class MailComplaintDate {
  final DateTime date;
  final int count;

  MailComplaintDate({required this.date, required this.count});

  factory MailComplaintDate.fromJson(Map<String, dynamic> j) => MailComplaintDate(
        date: _date(j['date']) ?? DateTime.now(),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// What the raise-complaint form pre-fills from the signed-in user's own record and the HR department list.
class MailComplaintFormDefaults {
  final String? raisedByName;
  final String? employeeCode;
  final int? branchId;
  final String? branchLabel;
  final String? stateName;
  final String? regionName;
  final String? divisionName;
  final String? areaName;
  final String? phone;
  final String? department;
  final List<String> departments;

  MailComplaintFormDefaults({
    this.raisedByName,
    this.employeeCode,
    this.branchId,
    this.branchLabel,
    this.stateName,
    this.regionName,
    this.divisionName,
    this.areaName,
    this.phone,
    this.department,
    this.departments = const [],
  });

  factory MailComplaintFormDefaults.fromJson(Map<String, dynamic> j) => MailComplaintFormDefaults(
        raisedByName: j['raisedByName'] as String?,
        employeeCode: j['employeeCode'] as String?,
        branchId: _int(j['branchId']),
        branchLabel: j['branchLabel'] as String?,
        stateName: j['stateName'] as String?,
        regionName: j['regionName'] as String?,
        divisionName: j['divisionName'] as String?,
        areaName: j['areaName'] as String?,
        phone: j['phone'] as String?,
        department: j['department'] as String?,
        departments: ((j['departments'] as List?) ?? const []).map((e) => '$e').toList(),
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


/// Per-branch dashboard summary (`AdminMailDashboard`).
class MailDashboard {
  final String fyLabel;
  final int outwardFyCount;
  final int inwardFyCount;
  final int todayOutwardCount;
  final int todayInwardCount;
  final List<MailRecord> recentOutward;
  final List<MailRecord> recentInward;

  MailDashboard({
    required this.fyLabel,
    required this.outwardFyCount,
    required this.inwardFyCount,
    required this.todayOutwardCount,
    required this.todayInwardCount,
    required this.recentOutward,
    required this.recentInward,
  });

  factory MailDashboard.fromJson(Map<String, dynamic> j) {
    List<MailRecord> recs(dynamic v) =>
        ((v as List?) ?? const []).cast<Map<String, dynamic>>().map(MailRecord.fromJson).toList();
    return MailDashboard(
      fyLabel: j['fyLabel'] as String? ?? '',
      outwardFyCount: _int(j['outwardFyCount']) ?? 0,
      inwardFyCount: _int(j['inwardFyCount']) ?? 0,
      todayOutwardCount: _int(j['todayOutwardCount']) ?? 0,
      todayInwardCount: _int(j['todayInwardCount']) ?? 0,
      recentOutward: recs(j['recentOutward']),
      recentInward: recs(j['recentInward']),
    );
  }
}
