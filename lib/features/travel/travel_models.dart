// Travel Management models — mirror of the backend `com.hrms.backend.dto.travel`
// records (plans, claims, expenses, approval steps, settlement, policies,
// the policy-violation evaluation, and report tables).

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String && v.isNotEmpty) return double.tryParse(v);
  return null;
}

/// ── Enum value catalogues (kept as plain strings, matching the backend names).
/// Use these for dropdowns; the API serialises/accepts the enum constant name.
class TravelEnums {
  TravelEnums._();

  /// `TravelMode`
  static const travelModes = <String>[
    'BIKE',
    'BUS',
    'TRAIN',
    'TAXI',
    'OWN_CAR',
    'OFFICE_CAR',
    'OTHER',
  ];

  /// `TravelExpenseCategory`
  static const expenseCategories = <String>[
    'TRAVEL_FARE',
    'ACCOMMODATION',
    'MEALS',
    'LOCAL_CONVEYANCE',
    'FUEL',
    'COMMUNICATION',
    'MISCELLANEOUS',
  ];

  /// `TravelPaymentMode`
  static const paymentModes = <String>[
    'BANK_TRANSFER',
    'CASH',
    'UPI',
    'CHEQUE',
    'PAYROLL',
  ];

  /// `TravelPlanStatus`
  static const planStatuses = <String>[
    'ACTIVE',
    'COMPLETED',
    'CANCELLED',
  ];

  /// `TravelClaimStatus`
  static const claimStatuses = <String>[
    'DRAFT',
    'SUBMITTED',
    'LEVEL_1_APPROVED',
    'LEVEL_2_APPROVED',
    'LEVEL_3_APPROVED',
    'APPROVED',
    'REJECTED',
    'SENT_BACK',
    'SETTLED',
  ];

  /// `TravelApprovalStepStatus`
  static const approvalStepStatuses = <String>[
    'NOT_STARTED',
    'PENDING',
    'APPROVED',
    'REJECTED',
    'SENT_BACK',
    'SKIPPED',
  ];

  /// `TravelPolicyScopeType`
  static const scopeTypes = <String>[
    'ALL',
    'DEPARTMENT',
    'DESIGNATION',
    'BRANCH',
    'GRADE',
    'BUSINESS_VERTICAL',
    'EMPLOYEE_TYPE',
  ];

  /// Pretty label for any of the SCREAMING_SNAKE enum constants above.
  static String label(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return raw
        .split('_')
        .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
        .join(' ');
  }
}

/// One DB-driven expense-category option from
/// `/api/lookups/travel-expense-categories` (the backend enum was removed —
/// companies define their own codes). [TravelEnums.expenseCategories] remains
/// only as an offline fallback.
class TravelCategoryOption {
  final String code;
  final String label;

  const TravelCategoryOption({required this.code, required this.label});

  factory TravelCategoryOption.fromJson(Map<String, dynamic> j) {
    final code = j['code'] as String? ?? '';
    final label = (j['label'] as String?)?.trim() ?? '';
    return TravelCategoryOption(
      code: code,
      label: label.isEmpty ? TravelEnums.label(code) : label,
    );
  }
}

/// A file staged on-device for upload as a plan/claim/expense bill or evidence.
class TravelUploadFile {
  final String path;
  final String fileName;

  TravelUploadFile({required this.path, required this.fileName});

  String get mime {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
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

/// Attachment metadata (`TravelAttachmentResponse`).
class TravelAttachment {
  final int id;
  final String? fileName;
  final String? fileType;
  final String? caption;
  final DateTime? uploadedAt;

  /// Backend-relative path like `/api/files/12` — wrap with `Env.fileUrl` for a
  /// viewable URL, or use the claim attachment download endpoint for bills.
  final String? downloadUrl;

  TravelAttachment({
    required this.id,
    this.fileName,
    this.fileType,
    this.caption,
    this.uploadedAt,
    this.downloadUrl,
  });

  factory TravelAttachment.fromJson(Map<String, dynamic> j) => TravelAttachment(
        id: (j['id'] as num).toInt(),
        fileName: j['fileName'] as String?,
        fileType: j['fileType'] as String?,
        caption: j['caption'] as String?,
        uploadedAt: _date(j['uploadedAt']),
        downloadUrl: j['downloadUrl'] as String?,
      );
}

/// A self-created travel plan (`TravelPlanResponse`).
class TravelPlan {
  final int id;
  final int? employeeId;
  final String? employeeCode;
  final String? employeeName;
  final String title;
  final String? destination;
  final String? fromLocation;
  final String? purpose;
  final String? travelMode; // TravelMode
  final DateTime? startDate;
  final DateTime? endDate;
  final double? estimatedCost;
  final String status; // TravelPlanStatus
  final List<TravelAttachment> attachments;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TravelPlan({
    required this.id,
    required this.title,
    required this.status,
    required this.attachments,
    this.employeeId,
    this.employeeCode,
    this.employeeName,
    this.destination,
    this.fromLocation,
    this.purpose,
    this.travelMode,
    this.startDate,
    this.endDate,
    this.estimatedCost,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory TravelPlan.fromJson(Map<String, dynamic> j) => TravelPlan(
        id: (j['id'] as num).toInt(),
        employeeId: (j['employeeId'] as num?)?.toInt(),
        employeeCode: j['employeeCode'] as String?,
        employeeName: j['employeeName'] as String?,
        title: j['title'] as String? ?? '',
        destination: j['destination'] as String?,
        fromLocation: j['fromLocation'] as String?,
        purpose: j['purpose'] as String?,
        travelMode: j['travelMode'] as String?,
        startDate: _date(j['startDate']),
        endDate: _date(j['endDate']),
        estimatedCost: _num(j['estimatedCost']),
        status: j['status'] as String? ?? 'ACTIVE',
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((e) => TravelAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdBy: j['createdBy'] as String?,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// One expense line of a claim (`TravelClaimExpenseResponse`).
class TravelClaimExpense {
  final int id;
  final String category; // TravelExpenseCategory
  final DateTime? expenseDate;
  final String? description;
  final double? amount;
  final double? approvedAmount;
  final double? limitAmount;
  final bool exceedsLimit;
  final bool billRequired;
  final bool hasBill;

  TravelClaimExpense({
    required this.id,
    required this.category,
    required this.exceedsLimit,
    required this.billRequired,
    required this.hasBill,
    this.expenseDate,
    this.description,
    this.amount,
    this.approvedAmount,
    this.limitAmount,
  });

  factory TravelClaimExpense.fromJson(Map<String, dynamic> j) => TravelClaimExpense(
        id: (j['id'] as num).toInt(),
        category: j['category'] as String? ?? 'MISCELLANEOUS',
        expenseDate: _date(j['expenseDate']),
        description: j['description'] as String?,
        amount: _num(j['amount']),
        approvedAmount: _num(j['approvedAmount']),
        limitAmount: _num(j['limitAmount']),
        exceedsLimit: j['exceedsLimit'] as bool? ?? false,
        billRequired: j['billRequired'] as bool? ?? false,
        hasBill: j['hasBill'] as bool? ?? false,
      );
}

/// One row of the immutable approval-chain snapshot (`TravelClaimApprovalStepResponse`).
class TravelClaimApprovalStep {
  final int id;
  final int? levelOrder;
  final int? approverEmployeeId;
  final String? approverName;
  final String status; // TravelApprovalStepStatus
  final bool current;
  final DateTime? actionAt;
  final String? remarks;

  TravelClaimApprovalStep({
    required this.id,
    required this.status,
    required this.current,
    this.levelOrder,
    this.approverEmployeeId,
    this.approverName,
    this.actionAt,
    this.remarks,
  });

  factory TravelClaimApprovalStep.fromJson(Map<String, dynamic> j) =>
      TravelClaimApprovalStep(
        id: (j['id'] as num).toInt(),
        levelOrder: (j['levelOrder'] as num?)?.toInt(),
        approverEmployeeId: (j['approverEmployeeId'] as num?)?.toInt(),
        approverName: j['approverName'] as String?,
        status: j['status'] as String? ?? 'NOT_STARTED',
        current: j['current'] as bool? ?? false,
        actionAt: _date(j['actionAt']),
        remarks: j['remarks'] as String?,
      );
}

/// Settlement view for a SETTLED claim (`TravelSettlementResponse`).
class TravelSettlement {
  final int id;
  final double? settledAmount;
  final String? paymentMode; // TravelPaymentMode
  final String? paymentReference;
  final String? remarks;
  final String? settledBy;
  final DateTime? settledAt;

  TravelSettlement({
    required this.id,
    this.settledAmount,
    this.paymentMode,
    this.paymentReference,
    this.remarks,
    this.settledBy,
    this.settledAt,
  });

  factory TravelSettlement.fromJson(Map<String, dynamic> j) => TravelSettlement(
        id: (j['id'] as num).toInt(),
        settledAmount: _num(j['settledAmount']),
        paymentMode: j['paymentMode'] as String?,
        paymentReference: j['paymentReference'] as String?,
        remarks: j['remarks'] as String?,
        settledBy: j['settledBy'] as String?,
        settledAt: _date(j['settledAt']),
      );
}

/// Full claim detail (`TravelClaimResponse`).
class TravelClaim {
  final int id;
  final String? claimCode;
  final int? employeeId;
  final String? employeeCode;
  final String? employeeName;
  final int? travelPlanId;
  final int? policyId;
  final String? policyNameSnapshot;
  final int? approvalLevels;
  final int? currentLevel;
  final String status; // TravelClaimStatus
  final String title;
  final String? purpose;
  final DateTime? fromDate;
  final DateTime? toDate;
  final double? totalClaimedAmount;
  final double? totalApprovedAmount;
  final bool hasPolicyViolation;
  final String? violationDetails;
  final String? submissionRemarks;
  final List<TravelClaimExpense> expenses;
  final List<TravelClaimApprovalStep> approvalSteps;
  final List<TravelAttachment> attachments;
  final TravelSettlement? settlement;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? settledAt;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TravelClaim({
    required this.id,
    required this.status,
    required this.title,
    required this.hasPolicyViolation,
    required this.expenses,
    required this.approvalSteps,
    required this.attachments,
    this.claimCode,
    this.employeeId,
    this.employeeCode,
    this.employeeName,
    this.travelPlanId,
    this.policyId,
    this.policyNameSnapshot,
    this.approvalLevels,
    this.currentLevel,
    this.purpose,
    this.fromDate,
    this.toDate,
    this.totalClaimedAmount,
    this.totalApprovedAmount,
    this.violationDetails,
    this.submissionRemarks,
    this.settlement,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.settledAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory TravelClaim.fromJson(Map<String, dynamic> j) => TravelClaim(
        id: (j['id'] as num).toInt(),
        claimCode: j['claimCode'] as String?,
        employeeId: (j['employeeId'] as num?)?.toInt(),
        employeeCode: j['employeeCode'] as String?,
        employeeName: j['employeeName'] as String?,
        travelPlanId: (j['travelPlanId'] as num?)?.toInt(),
        policyId: (j['policyId'] as num?)?.toInt(),
        policyNameSnapshot: j['policyNameSnapshot'] as String?,
        approvalLevels: (j['approvalLevels'] as num?)?.toInt(),
        currentLevel: (j['currentLevel'] as num?)?.toInt(),
        status: j['status'] as String? ?? 'DRAFT',
        title: j['title'] as String? ?? '',
        purpose: j['purpose'] as String?,
        fromDate: _date(j['fromDate']),
        toDate: _date(j['toDate']),
        totalClaimedAmount: _num(j['totalClaimedAmount']),
        totalApprovedAmount: _num(j['totalApprovedAmount']),
        hasPolicyViolation: j['hasPolicyViolation'] as bool? ?? false,
        violationDetails: j['violationDetails'] as String?,
        submissionRemarks: j['submissionRemarks'] as String?,
        expenses: ((j['expenses'] as List?) ?? const [])
            .map((e) => TravelClaimExpense.fromJson(e as Map<String, dynamic>))
            .toList(),
        approvalSteps: ((j['approvalSteps'] as List?) ?? const [])
            .map((e) => TravelClaimApprovalStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((e) => TravelAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        settlement: j['settlement'] == null
            ? null
            : TravelSettlement.fromJson(j['settlement'] as Map<String, dynamic>),
        submittedAt: _date(j['submittedAt']),
        approvedAt: _date(j['approvedAt']),
        rejectedAt: _date(j['rejectedAt']),
        settledAt: _date(j['settledAt']),
        createdBy: j['createdBy'] as String?,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// Lightweight claim row for lists/inbox/settlement-queue (`TravelClaimSummaryResponse`).
class TravelClaimSummary {
  final int id;
  final String? claimCode;
  final int? employeeId;
  final String? employeeName;
  final String title;
  final String status; // TravelClaimStatus
  final int? currentLevel;
  final double? totalClaimedAmount;
  final bool hasPolicyViolation;
  final DateTime? submittedAt;

  TravelClaimSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.hasPolicyViolation,
    this.claimCode,
    this.employeeId,
    this.employeeName,
    this.currentLevel,
    this.totalClaimedAmount,
    this.submittedAt,
  });

  factory TravelClaimSummary.fromJson(Map<String, dynamic> j) => TravelClaimSummary(
        id: (j['id'] as num).toInt(),
        claimCode: j['claimCode'] as String?,
        employeeId: (j['employeeId'] as num?)?.toInt(),
        employeeName: j['employeeName'] as String?,
        title: j['title'] as String? ?? '',
        status: j['status'] as String? ?? 'DRAFT',
        currentLevel: (j['currentLevel'] as num?)?.toInt(),
        totalClaimedAmount: _num(j['totalClaimedAmount']),
        hasPolicyViolation: j['hasPolicyViolation'] as bool? ?? false,
        submittedAt: _date(j['submittedAt']),
      );
}

/// One targeting rule of a policy (`TravelClaimPolicyScopeDto`).
class TravelPolicyScope {
  final String type; // TravelPolicyScopeType
  final String? value;

  TravelPolicyScope({required this.type, this.value});

  factory TravelPolicyScope.fromJson(Map<String, dynamic> j) => TravelPolicyScope(
        type: j['type'] as String? ?? 'ALL',
        value: j['value'] as String?,
      );

  Map<String, dynamic> toJson() => {'type': type, 'value': value};
}

/// One per-category monetary limit + bill rule (`TravelClaimPolicyLimitDto`).
class TravelPolicyLimit {
  final String category; // TravelExpenseCategory
  final double? maxAmount;
  final double? dailyLimit;
  final bool billRequired;

  TravelPolicyLimit({
    required this.category,
    required this.billRequired,
    this.maxAmount,
    this.dailyLimit,
  });

  factory TravelPolicyLimit.fromJson(Map<String, dynamic> j) => TravelPolicyLimit(
        category: j['category'] as String? ?? 'MISCELLANEOUS',
        maxAmount: _num(j['maxAmount']),
        dailyLimit: _num(j['dailyLimit']),
        billRequired: j['billRequired'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        if (maxAmount != null) 'maxAmount': maxAmount,
        if (dailyLimit != null) 'dailyLimit': dailyLimit,
        'billRequired': billRequired,
      };
}

/// Full policy detail (`TravelClaimPolicyResponse`).
class TravelPolicy {
  final int id;
  final String policyName;
  final String? description;
  final int? approvalLevels;
  final DateTime? effectiveDate;
  final bool active;
  final bool blockOnViolation;
  final bool billMandatory;
  final double? billMandatoryThreshold;
  final double? maxClaimAmount;
  final List<TravelPolicyScope> scopes;
  final List<TravelPolicyLimit> limits;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TravelPolicy({
    required this.id,
    required this.policyName,
    required this.active,
    required this.blockOnViolation,
    required this.billMandatory,
    required this.scopes,
    required this.limits,
    this.description,
    this.approvalLevels,
    this.effectiveDate,
    this.billMandatoryThreshold,
    this.maxClaimAmount,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory TravelPolicy.fromJson(Map<String, dynamic> j) => TravelPolicy(
        id: (j['id'] as num).toInt(),
        policyName: j['policyName'] as String? ?? '',
        description: j['description'] as String?,
        approvalLevels: (j['approvalLevels'] as num?)?.toInt(),
        effectiveDate: _date(j['effectiveDate']),
        active: j['active'] as bool? ?? true,
        blockOnViolation: j['blockOnViolation'] as bool? ?? false,
        billMandatory: j['billMandatory'] as bool? ?? false,
        billMandatoryThreshold: _num(j['billMandatoryThreshold']),
        maxClaimAmount: _num(j['maxClaimAmount']),
        scopes: ((j['scopes'] as List?) ?? const [])
            .map((e) => TravelPolicyScope.fromJson(e as Map<String, dynamic>))
            .toList(),
        limits: ((j['limits'] as List?) ?? const [])
            .map((e) => TravelPolicyLimit.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdBy: j['createdBy'] as String?,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// Per-category claimed-vs-limit line of the evaluation
/// (`TravelPolicyEvaluationResponse.CategoryEvaluation`).
class TravelCategoryEvaluation {
  final String category; // TravelExpenseCategory
  final double? claimed;
  final double? limit;
  final bool exceeds;
  final bool billRequired;
  final bool billMissing;

  TravelCategoryEvaluation({
    required this.category,
    required this.exceeds,
    required this.billRequired,
    required this.billMissing,
    this.claimed,
    this.limit,
  });

  factory TravelCategoryEvaluation.fromJson(Map<String, dynamic> j) =>
      TravelCategoryEvaluation(
        category: j['category'] as String? ?? 'MISCELLANEOUS',
        claimed: _num(j['claimed']),
        limit: _num(j['limit']),
        exceeds: j['exceeds'] as bool? ?? false,
        billRequired: j['billRequired'] as bool? ?? false,
        billMissing: j['billMissing'] as bool? ?? false,
      );
}

/// Limit-vs-claimed evaluation (`TravelPolicyEvaluationResponse`).
class TravelPolicyEvaluation {
  final int? policyId;
  final String? policyName;
  final int? approvalLevels;
  final double? totalClaimed;
  final double? maxClaimAmount;
  final bool blockOnViolation;
  final bool hasViolation;
  final List<TravelCategoryEvaluation> categories;

  TravelPolicyEvaluation({
    required this.blockOnViolation,
    required this.hasViolation,
    required this.categories,
    this.policyId,
    this.policyName,
    this.approvalLevels,
    this.totalClaimed,
    this.maxClaimAmount,
  });

  factory TravelPolicyEvaluation.fromJson(Map<String, dynamic> j) =>
      TravelPolicyEvaluation(
        policyId: (j['policyId'] as num?)?.toInt(),
        policyName: j['policyName'] as String?,
        approvalLevels: (j['approvalLevels'] as num?)?.toInt(),
        totalClaimed: _num(j['totalClaimed']),
        maxClaimAmount: _num(j['maxClaimAmount']),
        blockOnViolation: j['blockOnViolation'] as bool? ?? false,
        hasViolation: j['hasViolation'] as bool? ?? false,
        categories: ((j['categories'] as List?) ?? const [])
            .map((e) => TravelCategoryEvaluation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A tabular report payload (`TravelReportService.Table`): a title, column headers
/// and rows of stringly-typed cells.
class TravelReportTable {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  TravelReportTable({
    required this.title,
    required this.headers,
    required this.rows,
  });

  factory TravelReportTable.fromJson(Map<String, dynamic> j) => TravelReportTable(
        title: j['title'] as String? ?? '',
        headers: ((j['headers'] as List?) ?? const [])
            .map((e) => e?.toString() ?? '')
            .toList(),
        rows: ((j['rows'] as List?) ?? const [])
            .map((row) => ((row as List?) ?? const [])
                .map((c) => c?.toString() ?? '')
                .toList())
            .toList(),
      );
}
