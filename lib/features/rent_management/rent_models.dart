// Admin Tools — Rent Management models — mirror of the backend
// `AdminRent*` DTOs (see nava360-web `src/types.ts` lines ~3305-3420 and
// `src/api/adminRent.ts`, and the Spring rent controller/DTOs). Ported
// near-verbatim from the standalone office "Rent App": per-branch landlord
// rent records, a monthly rent-payable workflow (generate → submit →
// approve → pay, with a hold/release-hold side path), rent notices, utility
// bills (electricity/internet), and an audit trail.

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String && v.isNotEmpty) return double.tryParse(v);
  return null;
}

double _num0(dynamic v) => _num(v) ?? 0;

/// Fixed utility-bill kinds (`AdminRentUtilityKind`).
class RentUtilityKind {
  RentUtilityKind._();
  static const electricity = 'ELECTRICITY';
  static const internet = 'INTERNET';
  static const values = <String>[electricity, internet];
}

/// Monthly rent-payable workflow states (`AdminRentPayableStatus`).
class RentPayableStatus {
  RentPayableStatus._();
  static const pending = 'PENDING';
  static const submitted = 'SUBMITTED';
  static const approved = 'APPROVED';
  static const paid = 'PAID';
  static const held = 'HELD';
}

/// One rent branch / landlord record (`AdminRentBranch`).
class RentBranch {
  final int id;
  final String branchName;
  final String? branchCode;
  final String? ownerName;
  final String? address;
  final double? rent;
  final double? rentAdvance;
  final DateTime? startDate;
  final bool? gstApplicable;
  final DateTime? gstLockedUntil;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RentBranch({
    required this.id,
    required this.branchName,
    this.branchCode,
    this.ownerName,
    this.address,
    this.rent,
    this.rentAdvance,
    this.startDate,
    this.gstApplicable,
    this.gstLockedUntil,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  factory RentBranch.fromJson(Map<String, dynamic> j) => RentBranch(
        id: (j['id'] as num).toInt(),
        branchName: j['branchName'] as String? ?? '',
        branchCode: j['branchCode'] as String?,
        ownerName: j['ownerName'] as String?,
        address: j['address'] as String?,
        rent: _num(j['rent']),
        rentAdvance: _num(j['rentAdvance']),
        startDate: _date(j['startDate']),
        gstApplicable: j['gstApplicable'] as bool?,
        gstLockedUntil: _date(j['gstLockedUntil']),
        active: j['active'] as bool? ?? true,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// One monthly rent-payable row (`AdminRentPayable`). `period` is always the
/// 1st of the month, e.g. `2026-09-01`.
class RentPayable {
  final int id;
  final int branchId;
  final String branchName;
  final String period;
  final double rentAmount;
  final String status;
  final String? holdReason;
  final int? holdNoticeId;
  final String? submittedBy;
  final DateTime? submittedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? paidAt;
  final String? paidUtr;
  final String? paidBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RentPayable({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.period,
    required this.rentAmount,
    required this.status,
    this.holdReason,
    this.holdNoticeId,
    this.submittedBy,
    this.submittedAt,
    this.approvedBy,
    this.approvedAt,
    this.paidAt,
    this.paidUtr,
    this.paidBy,
    this.createdAt,
    this.updatedAt,
  });

  factory RentPayable.fromJson(Map<String, dynamic> j) => RentPayable(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchName: j['branchName'] as String? ?? '',
        period: j['period'] as String? ?? '',
        rentAmount: _num0(j['rentAmount']),
        status: j['status'] as String? ?? RentPayableStatus.pending,
        holdReason: j['holdReason'] as String?,
        holdNoticeId: (j['holdNoticeId'] as num?)?.toInt(),
        submittedBy: j['submittedBy'] as String?,
        submittedAt: _date(j['submittedAt']),
        approvedBy: j['approvedBy'] as String?,
        approvedAt: _date(j['approvedAt']),
        paidAt: _date(j['paidAt']),
        paidUtr: j['paidUtr'] as String?,
        paidBy: j['paidBy'] as String?,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// One rent notice (`AdminRentNotice`).
class RentNotice {
  final int id;
  final int branchId;
  final String branchName;
  final String subject;
  final String? body;
  final DateTime? issuedOn;
  final bool holdRent;
  final String? issuedBy;
  final DateTime? createdAt;

  RentNotice({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.subject,
    this.body,
    this.issuedOn,
    this.holdRent = false,
    this.issuedBy,
    this.createdAt,
  });

  factory RentNotice.fromJson(Map<String, dynamic> j) => RentNotice(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchName: j['branchName'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        body: j['body'] as String?,
        issuedOn: _date(j['issuedOn']),
        holdRent: j['holdRent'] as bool? ?? false,
        issuedBy: j['issuedBy'] as String?,
        createdAt: _date(j['createdAt']),
      );
}

/// One utility bill — electricity/internet, one per branch/kind/period
/// (`AdminRentUtilityBill`). Saving again for the same
/// branch/kind/period upserts the existing bill (server-side).
class RentUtilityBill {
  final int id;
  final int branchId;
  final String branchName;
  final String period;
  final String kind;
  final double? amount;
  final String? billNumber;
  final DateTime? billDate;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String? paidUtr;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RentUtilityBill({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.period,
    required this.kind,
    this.amount,
    this.billNumber,
    this.billDate,
    this.dueDate,
    this.paidAt,
    this.paidUtr,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory RentUtilityBill.fromJson(Map<String, dynamic> j) => RentUtilityBill(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        branchName: j['branchName'] as String? ?? '',
        period: j['period'] as String? ?? '',
        kind: j['kind'] as String? ?? RentUtilityKind.electricity,
        amount: _num(j['amount']),
        billNumber: j['billNumber'] as String?,
        billDate: _date(j['billDate']),
        dueDate: _date(j['dueDate']),
        paidAt: _date(j['paidAt']),
        paidUtr: j['paidUtr'] as String?,
        notes: j['notes'] as String?,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// One row of `/api/admin/rent/audit` (`AdminRentAuditLog`).
class RentAuditLog {
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

  RentAuditLog({
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

  factory RentAuditLog.fromJson(Map<String, dynamic> j) => RentAuditLog(
        id: (j['id'] as num).toInt(),
        entityType: j['entityType'] as String? ?? '',
        entityId: (j['entityId'] as num?)?.toInt(),
        action: j['action'] as String? ?? '',
        actorUserId: (j['actorUserId'] as num?)?.toInt(),
        actorName: j['actorName'] as String?,
        actorRole: j['actorRole'] as String?,
        beforeJson: j['beforeJson'] as String?,
        afterJson: j['afterJson'] as String?,
        metaJson: j['metaJson'] as String?,
        createdAt: _date(j['createdAt']),
      );
}
