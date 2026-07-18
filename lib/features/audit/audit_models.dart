// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — data models.
//
//  Mirrors the backend audit DTOs. Parsing is defensive: numbers come through as
//  num / String / null, enums are kept as Strings. Percentages / scores are on a
//  0–100 scale (NOT ratios). All `(v as num?)?.toDouble()`-style parsing.
// ─────────────────────────────────────────────────────────────────────────────

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _i(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _s(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

bool _b(dynamic v) => v == true || v == 'true' || v == 1;

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : const []).whereType<Map<String, dynamic>>().toList();

// ── Generic page ─────────────────────────────────────────────────────────────

/// One page of [T] rows from a Spring `Page<T>` payload
/// ({content,page,size,totalElements,totalPages,first,last}).
class AuditPage<T> {
  final List<T> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool first;
  final bool last;

  const AuditPage({
    this.content = const [],
    this.page = 0,
    this.size = 0,
    this.totalElements = 0,
    this.totalPages = 0,
    this.first = true,
    this.last = true,
  });

  factory AuditPage.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) item,
  ) {
    return AuditPage<T>(
      content: _maps(j['content']).map(item).toList(),
      page: _i(j['page']) ?? 0,
      size: _i(j['size']) ?? 0,
      totalElements: _i(j['totalElements']) ?? 0,
      totalPages: _i(j['totalPages']) ?? 0,
      first: j['first'] == true,
      last: j['last'] != false,
    );
  }
}

// ── Audit plan ───────────────────────────────────────────────────────────────

class AuditPlan {
  final int? id;
  final String? code;
  final String? title;
  final int? branchId;
  final String? branchName;
  final int? templateVersionId;
  final String? templateName;
  final int? assignedAuditorId;
  final String? assignedAuditorName;
  final String? plannedStartDate;
  final String? plannedEndDate;
  final String? periodFrom;
  final String? periodTo;
  final String? status;
  final double? finalScore;
  final String? riskFlag;
  final String? grade;
  final int? executionId;
  final String? createdAt;

  const AuditPlan({
    this.id,
    this.code,
    this.title,
    this.branchId,
    this.branchName,
    this.templateVersionId,
    this.templateName,
    this.assignedAuditorId,
    this.assignedAuditorName,
    this.plannedStartDate,
    this.plannedEndDate,
    this.periodFrom,
    this.periodTo,
    this.status,
    this.finalScore,
    this.riskFlag,
    this.grade,
    this.executionId,
    this.createdAt,
  });

  factory AuditPlan.fromJson(Map<String, dynamic> j) => AuditPlan(
        id: _i(j['id']),
        code: _s(j['code']),
        title: _s(j['title']),
        branchId: _i(j['branchId']),
        branchName: _s(j['branchName']),
        templateVersionId: _i(j['templateVersionId']),
        templateName: _s(j['templateName']),
        assignedAuditorId: _i(j['assignedAuditorId']),
        assignedAuditorName: _s(j['assignedAuditorName']),
        plannedStartDate: _s(j['plannedStartDate']),
        plannedEndDate: _s(j['plannedEndDate']),
        periodFrom: _s(j['periodFrom']),
        periodTo: _s(j['periodTo']),
        status: _s(j['status']),
        finalScore: _d(j['finalScore']),
        riskFlag: _s(j['riskFlag']),
        grade: _s(j['grade']),
        executionId: _i(j['executionId']),
        createdAt: _s(j['createdAt']),
      );
}

// ── Execution detail (+ nested blocks) ───────────────────────────────────────

class QuestionLine {
  final int? questionId;
  final String? code;
  final String? text;
  final String? groupLabel;
  final double? weightage;
  final bool naAllowed;
  final bool mandatory;
  final String? attachmentRule; // NOT_REQUIRED | REQUIRED_ALWAYS | REQUIRED_IF_YES | REQUIRED_IF_NO
  final String? observationRule;
  final String? riskLevel; // HIGH | MODERATE | LOW
  final String? answer; // YES | NO | NA | null
  final String? auditorObservation;
  final int attachmentCount;

  const QuestionLine({
    this.questionId,
    this.code,
    this.text,
    this.groupLabel,
    this.weightage,
    this.naAllowed = false,
    this.mandatory = true,
    this.attachmentRule,
    this.observationRule,
    this.riskLevel,
    this.answer,
    this.auditorObservation,
    this.attachmentCount = 0,
  });

  factory QuestionLine.fromJson(Map<String, dynamic> j) => QuestionLine(
        questionId: _i(j['questionId']),
        code: _s(j['code']),
        text: _s(j['text']),
        groupLabel: _s(j['groupLabel']),
        weightage: _d(j['weightage']),
        naAllowed: _b(j['naAllowed']),
        mandatory: j['mandatory'] == null ? true : _b(j['mandatory']),
        attachmentRule: _s(j['attachmentRule']),
        observationRule: _s(j['observationRule']),
        riskLevel: _s(j['riskLevel']),
        answer: _s(j['answer']),
        auditorObservation: _s(j['auditorObservation']),
        attachmentCount: _i(j['attachmentCount']) ?? 0,
      );

  bool get isAnswered => answer != null;

  /// True when this row is incomplete under its rules + current answer (mandatory-unanswered,
  /// required-observation-missing, or required-attachment-missing). Used for offline highlighting.
  bool get isIncomplete {
    if (mandatory && !isAnswered) return true;
    if (_ruleRequires(observationRule) && (auditorObservation == null || auditorObservation!.trim().isEmpty)) {
      return true;
    }
    if (_ruleRequires(attachmentRule) && attachmentCount <= 0) return true;
    return false;
  }

  bool _ruleRequires(String? rule) {
    if (rule == null || answer == null || answer == 'NA') return false;
    switch (rule) {
      case 'REQUIRED_ALWAYS':
        return true;
      case 'REQUIRED_IF_YES':
        return answer == 'YES';
      case 'REQUIRED_IF_NO':
        return answer == 'NO';
      default:
        return false;
    }
  }
}

class SubsectionBlock {
  final int? sectionId;
  final String? code;
  final String? name;
  final double? weightage;
  final List<QuestionLine> questions;

  const SubsectionBlock({
    this.sectionId,
    this.code,
    this.name,
    this.weightage,
    this.questions = const [],
  });

  factory SubsectionBlock.fromJson(Map<String, dynamic> j) => SubsectionBlock(
        sectionId: _i(j['sectionId']),
        code: _s(j['code']),
        name: _s(j['name']),
        weightage: _d(j['weightage']),
        questions:
            _maps(j['questions']).map(QuestionLine.fromJson).toList(),
      );
}

/// Pre-submit validation result (mirrors backend AuditValidationResponse).
class AuditValidation {
  final bool canSubmit;
  final bool scoreValid;
  final int totalQuestions;
  final int answeredQuestions;
  final List<AuditValidationItem> pendingQuestions;
  final List<AuditValidationItem> missingAttachments;
  final List<AuditValidationItem> missingObservations;
  final List<AuditSectionCompletion> sectionWiseCompletion;

  const AuditValidation({
    this.canSubmit = false,
    this.scoreValid = false,
    this.totalQuestions = 0,
    this.answeredQuestions = 0,
    this.pendingQuestions = const [],
    this.missingAttachments = const [],
    this.missingObservations = const [],
    this.sectionWiseCompletion = const [],
  });

  int get pendingCount =>
      pendingQuestions.length + missingAttachments.length + missingObservations.length;

  factory AuditValidation.fromJson(Map<String, dynamic> j) => AuditValidation(
        canSubmit: _b(j['canSubmit']),
        scoreValid: _b(j['scoreValid']),
        totalQuestions: _i(j['totalQuestions']) ?? 0,
        answeredQuestions: _i(j['answeredQuestions']) ?? 0,
        pendingQuestions: _maps(j['pendingQuestions']).map(AuditValidationItem.fromJson).toList(),
        missingAttachments: _maps(j['missingAttachments']).map(AuditValidationItem.fromJson).toList(),
        missingObservations: _maps(j['missingObservations']).map(AuditValidationItem.fromJson).toList(),
        sectionWiseCompletion:
            _maps(j['sectionWiseCompletion']).map(AuditSectionCompletion.fromJson).toList(),
      );
}

class AuditValidationItem {
  final int? questionId;
  final String? code;
  final String? sectionCode;
  final String? category;
  final String? reason;
  const AuditValidationItem({this.questionId, this.code, this.sectionCode, this.category, this.reason});
  factory AuditValidationItem.fromJson(Map<String, dynamic> j) => AuditValidationItem(
        questionId: _i(j['questionId']),
        code: _s(j['code']),
        sectionCode: _s(j['sectionCode']),
        category: _s(j['category']),
        reason: _s(j['reason']),
      );
}

class AuditSectionCompletion {
  final String? sectionCode;
  final String? sectionName;
  final int answered;
  final int total;
  final bool complete;
  const AuditSectionCompletion(
      {this.sectionCode, this.sectionName, this.answered = 0, this.total = 0, this.complete = false});
  factory AuditSectionCompletion.fromJson(Map<String, dynamic> j) => AuditSectionCompletion(
        sectionCode: _s(j['sectionCode']),
        sectionName: _s(j['sectionName']),
        answered: _i(j['answered']) ?? 0,
        total: _i(j['total']) ?? 0,
        complete: _b(j['complete']),
      );
}

class CategoryBlock {
  final int? sectionId;
  final String? code;
  final String? name;
  final double? weightage;
  final List<SubsectionBlock> subsections;

  const CategoryBlock({
    this.sectionId,
    this.code,
    this.name,
    this.weightage,
    this.subsections = const [],
  });

  factory CategoryBlock.fromJson(Map<String, dynamic> j) => CategoryBlock(
        sectionId: _i(j['sectionId']),
        code: _s(j['code']),
        name: _s(j['name']),
        weightage: _d(j['weightage']),
        subsections:
            _maps(j['subsections']).map(SubsectionBlock.fromJson).toList(),
      );
}

class ScoreSummary {
  final String? sectionCode;
  final String? sectionName;
  final double? maxWeightage;
  final double? applicableWeightage;
  final double? achievedScore;
  final double? percentage; // 0–100
  final String? riskLevel;

  const ScoreSummary({
    this.sectionCode,
    this.sectionName,
    this.maxWeightage,
    this.applicableWeightage,
    this.achievedScore,
    this.percentage,
    this.riskLevel,
  });

  factory ScoreSummary.fromJson(Map<String, dynamic> j) => ScoreSummary(
        sectionCode: _s(j['sectionCode']),
        sectionName: _s(j['sectionName']),
        maxWeightage: _d(j['maxWeightage']),
        applicableWeightage: _d(j['applicableWeightage']),
        achievedScore: _d(j['achievedScore']),
        percentage: _d(j['percentage']),
        riskLevel: _s(j['riskLevel']),
      );
}

class AuditExecutionDetail {
  final int? id;
  final int? planId;
  final String? planCode;
  final String? status;
  final String? branchName;
  final String? branchCode;
  final String? state;
  final String? branchManagerName;
  final String? areaManagerName;
  final String? divisionManagerName;
  final String? auditorName;
  final String? auditFromDate;
  final String? auditToDate;
  final String? periodFrom;
  final String? periodTo;
  final int? totalCustomers;
  final int? totalCenters;
  final double? portfolioOutstanding;
  final int? odCustomers;
  final double? odAmount;
  final double? parPercent;
  final double? finalScore;
  final String? grade;
  final String? riskFlag;
  final String? executiveSummary;
  final String? auditorFinalRemark;
  final String? bmActionRequirement;
  final String? complianceDueDate;
  final List<CategoryBlock> categories;
  final List<ScoreSummary> scoreSummary;

  const AuditExecutionDetail({
    this.id,
    this.planId,
    this.planCode,
    this.status,
    this.branchName,
    this.branchCode,
    this.state,
    this.branchManagerName,
    this.areaManagerName,
    this.divisionManagerName,
    this.auditorName,
    this.auditFromDate,
    this.auditToDate,
    this.periodFrom,
    this.periodTo,
    this.totalCustomers,
    this.totalCenters,
    this.portfolioOutstanding,
    this.odCustomers,
    this.odAmount,
    this.parPercent,
    this.finalScore,
    this.grade,
    this.riskFlag,
    this.executiveSummary,
    this.auditorFinalRemark,
    this.bmActionRequirement,
    this.complianceDueDate,
    this.categories = const [],
    this.scoreSummary = const [],
  });

  /// Editable only while the auditor is actively filling.
  bool get isEditable => status == 'IN_PROGRESS' || status == 'REOPENED';

  factory AuditExecutionDetail.fromJson(Map<String, dynamic> j) =>
      AuditExecutionDetail(
        id: _i(j['id']),
        planId: _i(j['planId']),
        planCode: _s(j['planCode']),
        status: _s(j['status']),
        branchName: _s(j['branchName']),
        branchCode: _s(j['branchCode']),
        state: _s(j['state']),
        branchManagerName: _s(j['branchManagerName']),
        areaManagerName: _s(j['areaManagerName']),
        divisionManagerName: _s(j['divisionManagerName']),
        auditorName: _s(j['auditorName']),
        auditFromDate: _s(j['auditFromDate']),
        auditToDate: _s(j['auditToDate']),
        periodFrom: _s(j['periodFrom']),
        periodTo: _s(j['periodTo']),
        totalCustomers: _i(j['totalCustomers']),
        totalCenters: _i(j['totalCenters']),
        portfolioOutstanding: _d(j['portfolioOutstanding']),
        odCustomers: _i(j['odCustomers']),
        odAmount: _d(j['odAmount']),
        parPercent: _d(j['parPercent']),
        finalScore: _d(j['finalScore']),
        grade: _s(j['grade']),
        riskFlag: _s(j['riskFlag']),
        executiveSummary: _s(j['executiveSummary']),
        auditorFinalRemark: _s(j['auditorFinalRemark']),
        bmActionRequirement: _s(j['bmActionRequirement']),
        complianceDueDate: _s(j['complianceDueDate']),
        categories: _maps(j['categories']).map(CategoryBlock.fromJson).toList(),
        scoreSummary:
            _maps(j['scoreSummary']).map(ScoreSummary.fromJson).toList(),
      );
}

// ── Findings ─────────────────────────────────────────────────────────────────

class AuditFinding {
  final int? id;
  final String? code;
  final int? executionId;
  final int? planId;
  final String? questionCode;
  final String? sectionCode;
  final String? category;
  final String? title;
  final String? description;
  final String? severity; // HIGH | MODERATE | LOW
  final String? status;
  final String? dueDate;

  const AuditFinding({
    this.id,
    this.code,
    this.executionId,
    this.planId,
    this.questionCode,
    this.sectionCode,
    this.category,
    this.title,
    this.description,
    this.severity,
    this.status,
    this.dueDate,
  });

  factory AuditFinding.fromJson(Map<String, dynamic> j) => AuditFinding(
        id: _i(j['id']),
        code: _s(j['code']),
        executionId: _i(j['executionId']),
        planId: _i(j['planId']),
        questionCode: _s(j['questionCode']),
        sectionCode: _s(j['sectionCode']),
        category: _s(j['category']),
        title: _s(j['title']),
        description: _s(j['description']),
        severity: _s(j['severity']),
        status: _s(j['status']),
        dueDate: _s(j['dueDate']),
      );
}

/// A single CAPA submission against a finding (BM corrective/preventive plan).
class Capa {
  final int? id;
  final String? rootCause;
  final String? correctiveAction;
  final String? preventiveAction;
  final String? complianceRemarks;
  final String? expectedClosureDate;
  final String? submittedByName;
  final String? createdAt;

  const Capa({
    this.id,
    this.rootCause,
    this.correctiveAction,
    this.preventiveAction,
    this.complianceRemarks,
    this.expectedClosureDate,
    this.submittedByName,
    this.createdAt,
  });

  factory Capa.fromJson(Map<String, dynamic> j) => Capa(
        id: _i(j['id']),
        rootCause: _s(j['rootCause']),
        correctiveAction: _s(j['correctiveAction']),
        preventiveAction: _s(j['preventiveAction']),
        complianceRemarks: _s(j['complianceRemarks']),
        expectedClosureDate: _s(j['expectedClosureDate']),
        submittedByName: _s(j['submittedByName']) ?? _s(j['submittedBy']),
        createdAt: _s(j['createdAt']),
      );
}

/// An auditor verification action against a finding.
class Verification {
  final int? id;
  final String? action; // ACCEPT | REJECT | REOPEN | ESCALATE | CLOSE
  final String? remarks;
  final String? dueDate;
  final String? verifiedByName;
  final String? createdAt;

  const Verification({
    this.id,
    this.action,
    this.remarks,
    this.dueDate,
    this.verifiedByName,
    this.createdAt,
  });

  factory Verification.fromJson(Map<String, dynamic> j) => Verification(
        id: _i(j['id']),
        action: _s(j['action']),
        remarks: _s(j['remarks']),
        dueDate: _s(j['dueDate']),
        verifiedByName: _s(j['verifiedByName']) ?? _s(j['verifiedBy']),
        createdAt: _s(j['createdAt']),
      );
}

class AuditFindingDetail {
  final AuditFinding finding;
  final bool complianceSubmitted;
  final bool canSubmitCompliance;
  final bool canVerify;
  final List<Capa> capaHistory;
  final List<Verification> verifications;

  const AuditFindingDetail({
    required this.finding,
    this.complianceSubmitted = false,
    this.canSubmitCompliance = true,
    this.canVerify = false,
    this.capaHistory = const [],
    this.verifications = const [],
  });

  factory AuditFindingDetail.fromJson(Map<String, dynamic> j) {
    final f = j['finding'];
    return AuditFindingDetail(
      finding: f is Map<String, dynamic>
          ? AuditFinding.fromJson(f)
          : AuditFinding.fromJson(j),
      complianceSubmitted: j['complianceSubmitted'] as bool? ?? false,
      canSubmitCompliance: j['canSubmitCompliance'] as bool? ?? true,
      canVerify: j['canVerify'] as bool? ?? false,
      capaHistory: _maps(j['capaHistory']).map(Capa.fromJson).toList(),
      verifications:
          _maps(j['verifications']).map(Verification.fromJson).toList(),
    );
  }
}

// ── Annexure rows ────────────────────────────────────────────────────────────

class AuditCenterVisit {
  final int? id;
  final String? branchName;
  final String? centerName;
  final String? loanProduct;
  final String? foName;
  final String? meetingDate;
  final String? attendance;
  final String? collectionStatus;
  final String? disciplineStatus;
  final String? deviation;
  final String? auditorRemarks;
  final int? sortOrder;

  const AuditCenterVisit({
    this.id,
    this.branchName,
    this.centerName,
    this.loanProduct,
    this.foName,
    this.meetingDate,
    this.attendance,
    this.collectionStatus,
    this.disciplineStatus,
    this.deviation,
    this.auditorRemarks,
    this.sortOrder,
  });

  factory AuditCenterVisit.fromJson(Map<String, dynamic> j) => AuditCenterVisit(
        id: _i(j['id']),
        branchName: _s(j['branchName']),
        centerName: _s(j['centerName']),
        loanProduct: _s(j['loanProduct']),
        foName: _s(j['foName']),
        meetingDate: _s(j['meetingDate']),
        attendance: _s(j['attendance']),
        collectionStatus: _s(j['collectionStatus']),
        disciplineStatus: _s(j['disciplineStatus']),
        deviation: _s(j['deviation']),
        auditorRemarks: _s(j['auditorRemarks']),
        sortOrder: _i(j['sortOrder']),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'branchName': branchName,
        'centerName': centerName,
        'loanProduct': loanProduct,
        'foName': foName,
        'meetingDate': meetingDate,
        'attendance': attendance,
        'collectionStatus': collectionStatus,
        'disciplineStatus': disciplineStatus,
        'deviation': deviation,
        'auditorRemarks': auditorRemarks,
        if (sortOrder != null) 'sortOrder': sortOrder,
      };
}

class AuditClientVisit {
  final int? id;
  final String? visitDate;
  final String? villageCenterName;
  final String? loanProduct;
  final String? customerLoanNumber;
  final String? customerName;
  final String? customerContact;
  final String? disbursementDate;
  final double? loanAmount;
  final String? lucStatus;
  final String? houseVisitStatus;
  final String? customerFeedback;
  final String? deviation;
  final String? auditorRemarks;
  final int? sortOrder;

  const AuditClientVisit({
    this.id,
    this.visitDate,
    this.villageCenterName,
    this.loanProduct,
    this.customerLoanNumber,
    this.customerName,
    this.customerContact,
    this.disbursementDate,
    this.loanAmount,
    this.lucStatus,
    this.houseVisitStatus,
    this.customerFeedback,
    this.deviation,
    this.auditorRemarks,
    this.sortOrder,
  });

  factory AuditClientVisit.fromJson(Map<String, dynamic> j) => AuditClientVisit(
        id: _i(j['id']),
        visitDate: _s(j['visitDate']),
        villageCenterName: _s(j['villageCenterName']),
        loanProduct: _s(j['loanProduct']),
        customerLoanNumber: _s(j['customerLoanNumber']),
        customerName: _s(j['customerName']),
        customerContact: _s(j['customerContact']),
        disbursementDate: _s(j['disbursementDate']),
        loanAmount: _d(j['loanAmount']),
        lucStatus: _s(j['lucStatus']),
        houseVisitStatus: _s(j['houseVisitStatus']),
        customerFeedback: _s(j['customerFeedback']),
        deviation: _s(j['deviation']),
        auditorRemarks: _s(j['auditorRemarks']),
        sortOrder: _i(j['sortOrder']),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'visitDate': visitDate,
        'villageCenterName': villageCenterName,
        'loanProduct': loanProduct,
        'customerLoanNumber': customerLoanNumber,
        'customerName': customerName,
        'customerContact': customerContact,
        'disbursementDate': disbursementDate,
        'loanAmount': loanAmount,
        'lucStatus': lucStatus,
        'houseVisitStatus': houseVisitStatus,
        'customerFeedback': customerFeedback,
        'deviation': deviation,
        'auditorRemarks': auditorRemarks,
        if (sortOrder != null) 'sortOrder': sortOrder,
      };
}

class AuditOdVisit {
  final int? id;
  final String? clientName;
  final String? loanAccountNumber;
  final String? centerName;
  final String? village;
  final String? foName;
  final String? bmName;
  final String? loanProduct;
  final double? outstandingAmount;
  final double? overdueAmount;
  final String? dpdBucket;
  final String? reasonForOverdue;
  final String? rootCause;
  final String? clientAvailableStatus;
  final String? promiseToPayDate;
  final String? staffFollowupStatus;
  final String? auditorRemarks;
  final int? sortOrder;

  const AuditOdVisit({
    this.id,
    this.clientName,
    this.loanAccountNumber,
    this.centerName,
    this.village,
    this.foName,
    this.bmName,
    this.loanProduct,
    this.outstandingAmount,
    this.overdueAmount,
    this.dpdBucket,
    this.reasonForOverdue,
    this.rootCause,
    this.clientAvailableStatus,
    this.promiseToPayDate,
    this.staffFollowupStatus,
    this.auditorRemarks,
    this.sortOrder,
  });

  factory AuditOdVisit.fromJson(Map<String, dynamic> j) => AuditOdVisit(
        id: _i(j['id']),
        clientName: _s(j['clientName']),
        loanAccountNumber: _s(j['loanAccountNumber']),
        centerName: _s(j['centerName']),
        village: _s(j['village']),
        foName: _s(j['foName']),
        bmName: _s(j['bmName']),
        loanProduct: _s(j['loanProduct']),
        outstandingAmount: _d(j['outstandingAmount']),
        overdueAmount: _d(j['overdueAmount']),
        dpdBucket: _s(j['dpdBucket']),
        reasonForOverdue: _s(j['reasonForOverdue']),
        rootCause: _s(j['rootCause']),
        clientAvailableStatus: _s(j['clientAvailableStatus']),
        promiseToPayDate: _s(j['promiseToPayDate']),
        staffFollowupStatus: _s(j['staffFollowupStatus']),
        auditorRemarks: _s(j['auditorRemarks']),
        sortOrder: _i(j['sortOrder']),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'clientName': clientName,
        'loanAccountNumber': loanAccountNumber,
        'centerName': centerName,
        'village': village,
        'foName': foName,
        'bmName': bmName,
        'loanProduct': loanProduct,
        'outstandingAmount': outstandingAmount,
        'overdueAmount': overdueAmount,
        'dpdBucket': dpdBucket,
        'reasonForOverdue': reasonForOverdue,
        'rootCause': rootCause,
        'clientAvailableStatus': clientAvailableStatus,
        'promiseToPayDate': promiseToPayDate,
        'staffFollowupStatus': staffFollowupStatus,
        'auditorRemarks': auditorRemarks,
        if (sortOrder != null) 'sortOrder': sortOrder,
      };

  /// Allowed root-cause options for the OD annexure dropdown.
  static const List<String> rootCauseOptions = [
    'Client migrated/absconding',
    'Crisis in family/Health',
    'Willingful defaulter',
    'Loss of Assets/Business income',
    'Loan pipelining/Middlemen',
    'Dummy/Ghost Client',
    'Insurance Claim related',
    'Staff Fraud',
    'Wrong behavior/ promise by staff',
    'Natural Calamities',
    'EMI misutilize by group member',
    'Wrong selection of client',
    'System/Recon/non geniune case',
  ];
}

class AuditBranchAnnexure {
  final int? id;
  final String? annexureType;
  final String? particular;
  final String? available; // YES | NO | NA
  final String? observation;
  final String? complianceByBm;
  final int? sortOrder;

  const AuditBranchAnnexure({
    this.id,
    this.annexureType,
    this.particular,
    this.available,
    this.observation,
    this.complianceByBm,
    this.sortOrder,
  });

  factory AuditBranchAnnexure.fromJson(Map<String, dynamic> j) =>
      AuditBranchAnnexure(
        id: _i(j['id']),
        annexureType: _s(j['annexureType']),
        particular: _s(j['particular']),
        available: _s(j['available']),
        observation: _s(j['observation']),
        complianceByBm: _s(j['complianceByBm']),
        sortOrder: _i(j['sortOrder']),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'annexureType': annexureType,
        'particular': particular,
        'available': available,
        'observation': observation,
        'complianceByBm': complianceByBm,
        if (sortOrder != null) 'sortOrder': sortOrder,
      };
}

// ── Attachment (photo proof) ─────────────────────────────────────────────────

class AuditAttachment {
  final int? id;
  final String? parentType;
  final int? parentId;
  final int? executionId;
  final String? fileUrl;
  final String? fileName;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final String? capturedAt;
  final String? createdAt;

  const AuditAttachment({
    this.id,
    this.parentType,
    this.parentId,
    this.executionId,
    this.fileUrl,
    this.fileName,
    this.caption,
    this.latitude,
    this.longitude,
    this.capturedAt,
    this.createdAt,
  });

  factory AuditAttachment.fromJson(Map<String, dynamic> j) => AuditAttachment(
        id: _i(j['id']),
        parentType: _s(j['parentType']),
        parentId: _i(j['parentId']),
        executionId: _i(j['executionId']),
        fileUrl: _s(j['fileUrl']) ?? _s(j['url']) ?? _s(j['filePath']),
        fileName: _s(j['fileName']) ?? _s(j['name']),
        caption: _s(j['caption']),
        latitude: _d(j['latitude']),
        longitude: _d(j['longitude']),
        capturedAt: _s(j['capturedAt']),
        createdAt: _s(j['createdAt']),
      );
}
