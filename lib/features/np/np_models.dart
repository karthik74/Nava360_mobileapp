// ─────────────────────────────────────────────────────────────────────────────
//  NP (Navachetana Prathinidhi) Onboarding — models + display constants.
//
//  Mirrors the backend DTOs one-for-one (and the web app's `src/types/np.ts`).
//  Field names are binding: do NOT rename them on this side. Dates arrive as
//  ISO strings ("2026-09-03" / "2026-09-03T10:15:30").
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../core/theme.dart';

// ── small parse helpers ──

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _intN(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double? _dblN(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String? _str(dynamic v) => v == null ? null : v.toString();
bool _bool(dynamic v) => v == true;
bool? _boolN(dynamic v) => v == null ? null : v == true;
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

Map<String, bool> _boolMap(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val == true)) : const {};
Map<String, String> _strMap(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), (val ?? '').toString())) : const {};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
List<String> _strList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

// ── shared shapes ──

class NpPerson {
  final int id;
  final String? employeeCode;
  final String name;
  const NpPerson({required this.id, this.employeeCode, required this.name});

  static NpPerson? fromJsonN(dynamic j) => j is Map<String, dynamic>
      ? NpPerson(id: _int(j['id']), employeeCode: _str(j['employeeCode']), name: _str(j['name']) ?? '')
      : null;
}

class NpFileRef {
  final int id;
  final String name;

  /// Server-relative path — resolve with `Env.fileUrl()`.
  final String url;
  final String? contentType;
  final int sizeBytes;
  const NpFileRef({
    required this.id,
    required this.name,
    required this.url,
    this.contentType,
    this.sizeBytes = 0,
  });

  bool get isImage => (contentType ?? '').startsWith('image/');
  bool get isPdf => (contentType ?? '') == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  static NpFileRef? fromJsonN(dynamic j) => j is Map<String, dynamic>
      ? NpFileRef(
          id: _int(j['id']),
          name: _str(j['name']) ?? 'file',
          url: _str(j['url']) ?? '/api/files/${j['id']}',
          contentType: _str(j['contentType']),
          sizeBytes: _int(j['sizeBytes']),
        )
      : null;
}

class NpDocument {
  final int id;
  final String stage; // KYC | BGV | AGREEMENT_PDC | ACTIVATION | OTHER
  final String docType;
  final String docTypeLabel;
  final String? parentType;
  final int? parentId;
  final NpFileRef file;
  final String? documentNumber;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final DateTime? capturedAt;
  final bool verified;
  final NpPerson? verifiedBy;
  final DateTime? verifiedAt;
  final bool superseded;
  final NpPerson? uploadedBy;
  final DateTime? uploadedAt;

  const NpDocument({
    required this.id,
    required this.stage,
    required this.docType,
    required this.docTypeLabel,
    this.parentType,
    this.parentId,
    required this.file,
    this.documentNumber,
    this.caption,
    this.latitude,
    this.longitude,
    this.capturedAt,
    this.verified = false,
    this.verifiedBy,
    this.verifiedAt,
    this.superseded = false,
    this.uploadedBy,
    this.uploadedAt,
  });

  factory NpDocument.fromJson(Map<String, dynamic> j) => NpDocument(
        id: _int(j['id']),
        stage: _str(j['stage']) ?? 'OTHER',
        docType: _str(j['docType']) ?? '',
        docTypeLabel: _str(j['docTypeLabel']) ?? _str(j['docType']) ?? '',
        parentType: _str(j['parentType']),
        parentId: _intN(j['parentId']),
        file: NpFileRef.fromJsonN(j['file']) ??
            const NpFileRef(id: 0, name: 'file', url: ''),
        documentNumber: _str(j['documentNumber']),
        caption: _str(j['caption']),
        latitude: _dblN(j['latitude']),
        longitude: _dblN(j['longitude']),
        capturedAt: _dt(j['capturedAt']),
        verified: _bool(j['verified']),
        verifiedBy: NpPerson.fromJsonN(j['verifiedBy']),
        verifiedAt: _dt(j['verifiedAt']),
        superseded: _bool(j['superseded']),
        uploadedBy: NpPerson.fromJsonN(j['uploadedBy']),
        uploadedAt: _dt(j['uploadedAt']),
      );
}

class NpInterview {
  final int id;
  final int attemptNo;
  final DateTime? interviewDate;
  final NpPerson? interviewer;
  final String result; // PASS | REJECT
  final String? remarks;
  final NpPerson? recordedBy;
  final DateTime? recordedAt;
  const NpInterview({
    required this.id,
    required this.attemptNo,
    this.interviewDate,
    this.interviewer,
    required this.result,
    this.remarks,
    this.recordedBy,
    this.recordedAt,
  });

  factory NpInterview.fromJson(Map<String, dynamic> j) => NpInterview(
        id: _int(j['id']),
        attemptNo: _int(j['attemptNo']),
        interviewDate: _dt(j['interviewDate']),
        interviewer: NpPerson.fromJsonN(j['interviewer']),
        result: _str(j['result']) ?? 'PASS',
        remarks: _str(j['remarks']),
        recordedBy: NpPerson.fromJsonN(j['recordedBy']),
        recordedAt: _dt(j['recordedAt']),
      );
}

class NpCbCheck {
  final int id;
  final int attemptNo;
  final String provider;
  final String? referenceNo;
  final String status; // PENDING | APPROVED | REJECTED | ERROR
  final String? score;
  final NpPerson? submittedBy;
  final DateTime? submittedAt;
  final NpPerson? decidedBy;
  final DateTime? decidedAt;
  final String? remarks;
  final NpFileRef? report;
  const NpCbCheck({
    required this.id,
    required this.attemptNo,
    required this.provider,
    this.referenceNo,
    required this.status,
    this.score,
    this.submittedBy,
    this.submittedAt,
    this.decidedBy,
    this.decidedAt,
    this.remarks,
    this.report,
  });

  factory NpCbCheck.fromJson(Map<String, dynamic> j) => NpCbCheck(
        id: _int(j['id']),
        attemptNo: _int(j['attemptNo']),
        provider: _str(j['provider']) ?? '',
        referenceNo: _str(j['referenceNo']),
        status: _str(j['status']) ?? 'PENDING',
        score: _str(j['score']),
        submittedBy: NpPerson.fromJsonN(j['submittedBy']),
        submittedAt: _dt(j['submittedAt']),
        decidedBy: NpPerson.fromJsonN(j['decidedBy']),
        decidedAt: _dt(j['decidedAt']),
        remarks: _str(j['remarks']),
        report: NpFileRef.fromJsonN(j['report']),
      );
}

class NpFamilyMember {
  String name;
  String relation;
  int? age;
  String? occupation;
  NpFamilyMember({this.name = '', this.relation = '', this.age, this.occupation});

  factory NpFamilyMember.fromJson(Map<String, dynamic> j) => NpFamilyMember(
        name: _str(j['name']) ?? '',
        relation: _str(j['relation']) ?? '',
        age: _intN(j['age']),
        occupation: _str(j['occupation']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'relation': relation,
        'age': age,
        'occupation': occupation,
      };
}

class NpBgvReport {
  final int id;
  final int attemptNo;
  final bool draft;
  final DateTime? visitAt;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyM;
  final bool? addressVerified;
  final String? addressAsFound;
  final String? residenceType;
  final int? yearsAtAddress;
  final List<NpFamilyMember> familyMembers;
  final Map<String, String> background;
  final Map<String, bool> checklist;
  final String? amRemarks;
  final String? recommendation; // RECOMMENDED | NOT_RECOMMENDED
  final NpPerson? submittedBy;
  final DateTime? submittedAt;
  final List<NpDocument> photos;
  const NpBgvReport({
    required this.id,
    required this.attemptNo,
    required this.draft,
    this.visitAt,
    this.latitude,
    this.longitude,
    this.locationAccuracyM,
    this.addressVerified,
    this.addressAsFound,
    this.residenceType,
    this.yearsAtAddress,
    this.familyMembers = const [],
    this.background = const {},
    this.checklist = const {},
    this.amRemarks,
    this.recommendation,
    this.submittedBy,
    this.submittedAt,
    this.photos = const [],
  });

  factory NpBgvReport.fromJson(Map<String, dynamic> j) => NpBgvReport(
        id: _int(j['id']),
        attemptNo: _int(j['attemptNo']),
        draft: _bool(j['draft']),
        visitAt: _dt(j['visitAt']),
        latitude: _dblN(j['latitude']),
        longitude: _dblN(j['longitude']),
        locationAccuracyM: _dblN(j['locationAccuracyM']),
        addressVerified: _boolN(j['addressVerified']),
        addressAsFound: _str(j['addressAsFound']),
        residenceType: _str(j['residenceType']),
        yearsAtAddress: _intN(j['yearsAtAddress']),
        familyMembers: _list(j['familyMembers']).map(NpFamilyMember.fromJson).toList(),
        background: _strMap(j['background']),
        checklist: _boolMap(j['checklist']),
        amRemarks: _str(j['amRemarks']),
        recommendation: _str(j['recommendation']),
        submittedBy: NpPerson.fromJsonN(j['submittedBy']),
        submittedAt: _dt(j['submittedAt']),
        photos: _list(j['photos']).map(NpDocument.fromJson).toList(),
      );
}

class NpApproval {
  final int id;
  final String level; // DM | OPS
  final int attemptNo;
  final String action; // APPROVE | REJECT | SEND_BACK
  final String? sendBackStage;
  final Map<String, bool>? checklist;
  final String? remarks;
  final NpPerson? actedBy;
  final DateTime? actedAt;
  final String fromStatus;
  final String toStatus;
  const NpApproval({
    required this.id,
    required this.level,
    required this.attemptNo,
    required this.action,
    this.sendBackStage,
    this.checklist,
    this.remarks,
    this.actedBy,
    this.actedAt,
    required this.fromStatus,
    required this.toStatus,
  });

  factory NpApproval.fromJson(Map<String, dynamic> j) => NpApproval(
        id: _int(j['id']),
        level: _str(j['level']) ?? 'DM',
        attemptNo: _int(j['attemptNo']),
        action: _str(j['action']) ?? '',
        sendBackStage: _str(j['sendBackStage']),
        checklist: j['checklist'] is Map ? _boolMap(j['checklist']) : null,
        remarks: _str(j['remarks']),
        actedBy: NpPerson.fromJsonN(j['actedBy']),
        actedAt: _dt(j['actedAt']),
        fromStatus: _str(j['fromStatus']) ?? '',
        toStatus: _str(j['toStatus']) ?? '',
      );
}

class NpPdc {
  final int id;
  final int seqNo;
  final String chequeNumber;
  final String? bankName;
  final String? ifsc;
  final String? accountNumber;
  final NpFileRef? file;
  const NpPdc({
    required this.id,
    required this.seqNo,
    required this.chequeNumber,
    this.bankName,
    this.ifsc,
    this.accountNumber,
    this.file,
  });

  factory NpPdc.fromJson(Map<String, dynamic> j) => NpPdc(
        id: _int(j['id']),
        seqNo: _int(j['seqNo']),
        chequeNumber: _str(j['chequeNumber']) ?? '',
        bankName: _str(j['bankName']),
        ifsc: _str(j['ifsc']),
        accountNumber: _str(j['accountNumber']),
        file: NpFileRef.fromJsonN(j['file']),
      );
}

class NpAgreement {
  final int id;
  final int attemptNo;
  final DateTime? agreementDate;
  final NpFileRef? file;
  final List<NpPdc> pdcs;
  final String? remarks;
  final NpPerson? submittedBy;
  final DateTime? submittedAt;
  const NpAgreement({
    required this.id,
    required this.attemptNo,
    this.agreementDate,
    this.file,
    this.pdcs = const [],
    this.remarks,
    this.submittedBy,
    this.submittedAt,
  });

  factory NpAgreement.fromJson(Map<String, dynamic> j) => NpAgreement(
        id: _int(j['id']),
        attemptNo: _int(j['attemptNo']),
        agreementDate: _dt(j['agreementDate']),
        file: NpFileRef.fromJsonN(j['file']),
        pdcs: _list(j['pdcs']).map(NpPdc.fromJson).toList(),
        remarks: _str(j['remarks']),
        submittedBy: NpPerson.fromJsonN(j['submittedBy']),
        submittedAt: _dt(j['submittedAt']),
      );
}

class NpActivation {
  final int id;
  final int attemptNo;
  final String mobileNumber; // masked
  final DateTime? otpSentAt;
  final DateTime? otpExpiresAt;
  final int? attemptsRemaining;
  final DateTime? verifiedAt;
  final String? deviceModel;
  final String? deviceOs;
  final String? appVersion;
  final String? exceptionReason;
  final NpPerson? performedBy;
  const NpActivation({
    required this.id,
    required this.attemptNo,
    required this.mobileNumber,
    this.otpSentAt,
    this.otpExpiresAt,
    this.attemptsRemaining,
    this.verifiedAt,
    this.deviceModel,
    this.deviceOs,
    this.appVersion,
    this.exceptionReason,
    this.performedBy,
  });

  factory NpActivation.fromJson(Map<String, dynamic> j) => NpActivation(
        id: _int(j['id']),
        attemptNo: _int(j['attemptNo']),
        mobileNumber: _str(j['mobileNumber']) ?? '',
        otpSentAt: _dt(j['otpSentAt']),
        otpExpiresAt: _dt(j['otpExpiresAt']),
        attemptsRemaining: _intN(j['attemptsRemaining']),
        verifiedAt: _dt(j['verifiedAt']),
        deviceModel: _str(j['deviceModel']),
        deviceOs: _str(j['deviceOs']),
        appVersion: _str(j['appVersion']),
        exceptionReason: _str(j['exceptionReason']),
        performedBy: NpPerson.fromJsonN(j['performedBy']),
      );
}

class NpAuditLog {
  final int id;
  final int candidateId;
  final String action;
  final String? previousStatus;
  final String? newStatus;
  final String? performedBy;
  final String? roles;
  final String? ipAddress;
  final String? deviceInfo;
  final String? remarks;
  final String? detail;
  final DateTime? createdAt;
  const NpAuditLog({
    required this.id,
    required this.candidateId,
    required this.action,
    this.previousStatus,
    this.newStatus,
    this.performedBy,
    this.roles,
    this.ipAddress,
    this.deviceInfo,
    this.remarks,
    this.detail,
    this.createdAt,
  });

  factory NpAuditLog.fromJson(Map<String, dynamic> j) => NpAuditLog(
        id: _int(j['id']),
        candidateId: _int(j['candidateId']),
        action: _str(j['action']) ?? '',
        previousStatus: _str(j['previousStatus']),
        newStatus: _str(j['newStatus']),
        performedBy: _str(j['performedBy']),
        roles: _str(j['roles']),
        ipAddress: _str(j['ipAddress']),
        deviceInfo: _str(j['deviceInfo']),
        remarks: _str(j['remarks']),
        detail: _str(j['detail']),
        createdAt: _dt(j['createdAt']),
      );
}

class NpStepView {
  final String step;
  final String label;
  final String state; // DONE | CURRENT | PENDING | REJECTED | SENT_BACK | SKIPPED
  final String? status;
  final NpPerson? completedBy;
  final DateTime? completedAt;
  final String? remarks;
  const NpStepView({
    required this.step,
    required this.label,
    required this.state,
    this.status,
    this.completedBy,
    this.completedAt,
    this.remarks,
  });

  factory NpStepView.fromJson(Map<String, dynamic> j) => NpStepView(
        step: _str(j['step']) ?? '',
        label: _str(j['label']) ?? '',
        state: _str(j['state']) ?? 'PENDING',
        status: _str(j['status']),
        completedBy: NpPerson.fromJsonN(j['completedBy']),
        completedAt: _dt(j['completedAt']),
        remarks: _str(j['remarks']),
      );
}

class NpCandidateSummary {
  final int id;
  final String candidateCode;
  final String fullName;
  final String mobileNumber;
  final String? gender;
  final String status;
  final String statusLabel;
  final String step;
  final int? branchId;
  final String? branchName;
  final String? areaName;
  final String? divisionName;
  final String? regionName;
  final String? npId;
  final String? esafId;
  final NpPerson? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? correctionStage;
  final bool rejected;

  const NpCandidateSummary({
    required this.id,
    required this.candidateCode,
    required this.fullName,
    required this.mobileNumber,
    this.gender,
    required this.status,
    required this.statusLabel,
    required this.step,
    this.branchId,
    this.branchName,
    this.areaName,
    this.divisionName,
    this.regionName,
    this.npId,
    this.esafId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.correctionStage,
    this.rejected = false,
  });

  factory NpCandidateSummary.fromJson(Map<String, dynamic> j) => NpCandidateSummary(
        id: _int(j['id']),
        candidateCode: _str(j['candidateCode']) ?? '',
        fullName: _str(j['fullName']) ?? '',
        mobileNumber: _str(j['mobileNumber']) ?? '',
        gender: _str(j['gender']),
        status: _str(j['status']) ?? 'DRAFT',
        statusLabel: _str(j['statusLabel']) ?? npStatusLabel(_str(j['status']) ?? 'DRAFT'),
        step: _str(j['step']) ?? 'CANDIDATE',
        branchId: _intN(j['branchId']),
        branchName: _str(j['branchName']),
        areaName: _str(j['areaName']),
        divisionName: _str(j['divisionName']),
        regionName: _str(j['regionName']),
        npId: _str(j['npId']),
        esafId: _str(j['esafId']),
        createdBy: NpPerson.fromJsonN(j['createdBy']),
        createdAt: _dt(j['createdAt']),
        updatedAt: _dt(j['updatedAt']),
        correctionStage: _str(j['correctionStage']),
        rejected: _bool(j['rejected']),
      );

  String get orgLine =>
      [branchName, areaName, divisionName, regionName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

class NpCandidateDetail extends NpCandidateSummary {
  final DateTime? dateOfBirth;
  final String? email;
  final String? alternateMobile;
  final String? fatherOrSpouseName;
  final String? maritalStatus;
  final String? spouseName;
  final DateTime? spouseDateOfBirth;
  final String? spouseMobile;
  final String? spouseOccupation;
  final String? addressLine;
  final String? villageOrTown;
  final String? district;
  final String? state;
  final String? pincode;
  final String? commAddressLine;
  final String? commVillageOrTown;
  final String? commDistrict;
  final String? commState;
  final String? commPincode;
  final String? education;
  final String? occupation;
  final int? experienceYears;
  final bool? hasTwoWheeler;
  final bool? hasSmartphone;
  final String? aadhaarLast4;
  final String? panNumber;
  final String? drivingLicenceNumber;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? bankName;
  final String? bankAccountHolderName;
  final Map<String, bool> eligibility;
  final String? eligibilityNotes;
  final String? remarks;
  final NpFileRef? photo;

  final NpPerson? identifiedBy;
  final DateTime? identifiedAt;

  final bool orientationCompleted;
  final DateTime? orientationDate;
  final Map<String, bool> orientationItems;
  final String? orientationRemarks;
  final NpPerson? orientationBy;
  final DateTime? orientationAt;

  final String? previousStatus;
  final String? returnToStatus;
  final String? correctionRemarks;
  final String? rejectionReason;
  final DateTime? rejectedAt;

  final DateTime? npIdGeneratedAt;
  final DateTime? esafIdCreatedAt;
  final NpPerson? esafIdBy;
  final String? activatedMobile;
  final DateTime? nava360ActivatedAt;
  final bool activationException;
  final DateTime? finalActivatedAt;
  final NpPerson? finalActivatedBy;

  final List<NpStepView> steps;
  final List<NpDocument> documents;
  final List<NpDocument> supersededDocuments;
  final List<NpInterview> interviews;
  final List<NpCbCheck> cbChecks;
  final List<NpBgvReport> bgvReports;
  final List<NpApproval> approvals;
  final List<NpAgreement> agreements;
  final List<NpActivation> activations;

  /// Computed server-side from status × caller permissions × scope.
  final Set<String> allowedActions;

  /// docType codes still missing before KYC can be submitted.
  final List<String> missingKycDocs;
  final Map<String, bool> opsChecklist;

  NpCandidateDetail({
    required super.id,
    required super.candidateCode,
    required super.fullName,
    required super.mobileNumber,
    super.gender,
    required super.status,
    required super.statusLabel,
    required super.step,
    super.branchId,
    super.branchName,
    super.areaName,
    super.divisionName,
    super.regionName,
    super.npId,
    super.esafId,
    super.createdBy,
    super.createdAt,
    super.updatedAt,
    super.correctionStage,
    super.rejected,
    this.dateOfBirth,
    this.email,
    this.alternateMobile,
    this.fatherOrSpouseName,
    this.maritalStatus,
    this.spouseName,
    this.spouseDateOfBirth,
    this.spouseMobile,
    this.spouseOccupation,
    this.addressLine,
    this.villageOrTown,
    this.district,
    this.state,
    this.pincode,
    this.commAddressLine,
    this.commVillageOrTown,
    this.commDistrict,
    this.commState,
    this.commPincode,
    this.education,
    this.occupation,
    this.experienceYears,
    this.hasTwoWheeler,
    this.hasSmartphone,
    this.aadhaarLast4,
    this.panNumber,
    this.drivingLicenceNumber,
    this.bankAccountNumber,
    this.bankIfsc,
    this.bankName,
    this.bankAccountHolderName,
    this.eligibility = const {},
    this.eligibilityNotes,
    this.remarks,
    this.photo,
    this.identifiedBy,
    this.identifiedAt,
    this.orientationCompleted = false,
    this.orientationDate,
    this.orientationItems = const {},
    this.orientationRemarks,
    this.orientationBy,
    this.orientationAt,
    this.previousStatus,
    this.returnToStatus,
    this.correctionRemarks,
    this.rejectionReason,
    this.rejectedAt,
    this.npIdGeneratedAt,
    this.esafIdCreatedAt,
    this.esafIdBy,
    this.activatedMobile,
    this.nava360ActivatedAt,
    this.activationException = false,
    this.finalActivatedAt,
    this.finalActivatedBy,
    this.steps = const [],
    this.documents = const [],
    this.supersededDocuments = const [],
    this.interviews = const [],
    this.cbChecks = const [],
    this.bgvReports = const [],
    this.approvals = const [],
    this.agreements = const [],
    this.activations = const [],
    this.allowedActions = const {},
    this.missingKycDocs = const [],
    this.opsChecklist = const {},
  });

  factory NpCandidateDetail.fromJson(Map<String, dynamic> j) {
    final s = NpCandidateSummary.fromJson(j);
    return NpCandidateDetail(
      id: s.id,
      candidateCode: s.candidateCode,
      fullName: s.fullName,
      mobileNumber: s.mobileNumber,
      gender: s.gender,
      status: s.status,
      statusLabel: s.statusLabel,
      step: s.step,
      branchId: s.branchId,
      branchName: s.branchName,
      areaName: s.areaName,
      divisionName: s.divisionName,
      regionName: s.regionName,
      npId: s.npId,
      esafId: s.esafId,
      createdBy: s.createdBy,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      correctionStage: s.correctionStage,
      rejected: s.rejected,
      dateOfBirth: _dt(j['dateOfBirth']),
      email: _str(j['email']),
      alternateMobile: _str(j['alternateMobile']),
      fatherOrSpouseName: _str(j['fatherOrSpouseName']),
      maritalStatus: _str(j['maritalStatus']),
      spouseName: _str(j['spouseName']),
      spouseDateOfBirth: _dt(j['spouseDateOfBirth']),
      spouseMobile: _str(j['spouseMobile']),
      spouseOccupation: _str(j['spouseOccupation']),
      addressLine: _str(j['addressLine']),
      villageOrTown: _str(j['villageOrTown']),
      district: _str(j['district']),
      state: _str(j['state']),
      pincode: _str(j['pincode']),
      commAddressLine: _str(j['commAddressLine']),
      commVillageOrTown: _str(j['commVillageOrTown']),
      commDistrict: _str(j['commDistrict']),
      commState: _str(j['commState']),
      commPincode: _str(j['commPincode']),
      education: _str(j['education']),
      occupation: _str(j['occupation']),
      experienceYears: _intN(j['experienceYears']),
      hasTwoWheeler: _boolN(j['hasTwoWheeler']),
      hasSmartphone: _boolN(j['hasSmartphone']),
      aadhaarLast4: _str(j['aadhaarLast4']),
      panNumber: _str(j['panNumber']),
      drivingLicenceNumber: _str(j['drivingLicenceNumber']),
      bankAccountNumber: _str(j['bankAccountNumber']),
      bankIfsc: _str(j['bankIfsc']),
      bankName: _str(j['bankName']),
      bankAccountHolderName: _str(j['bankAccountHolderName']),
      eligibility: _boolMap(j['eligibility']),
      eligibilityNotes: _str(j['eligibilityNotes']),
      remarks: _str(j['remarks']),
      photo: NpFileRef.fromJsonN(j['photo']),
      identifiedBy: NpPerson.fromJsonN(j['identifiedBy']),
      identifiedAt: _dt(j['identifiedAt']),
      orientationCompleted: _bool(j['orientationCompleted']),
      orientationDate: _dt(j['orientationDate']),
      orientationItems: _boolMap(j['orientationItems']),
      orientationRemarks: _str(j['orientationRemarks']),
      orientationBy: NpPerson.fromJsonN(j['orientationBy']),
      orientationAt: _dt(j['orientationAt']),
      previousStatus: _str(j['previousStatus']),
      returnToStatus: _str(j['returnToStatus']),
      correctionRemarks: _str(j['correctionRemarks']),
      rejectionReason: _str(j['rejectionReason']),
      rejectedAt: _dt(j['rejectedAt']),
      npIdGeneratedAt: _dt(j['npIdGeneratedAt']),
      esafIdCreatedAt: _dt(j['esafIdCreatedAt']),
      esafIdBy: NpPerson.fromJsonN(j['esafIdBy']),
      activatedMobile: _str(j['activatedMobile']),
      nava360ActivatedAt: _dt(j['nava360ActivatedAt']),
      activationException: _bool(j['activationException']),
      finalActivatedAt: _dt(j['finalActivatedAt']),
      finalActivatedBy: NpPerson.fromJsonN(j['finalActivatedBy']),
      steps: _list(j['steps']).map(NpStepView.fromJson).toList(),
      documents: _list(j['documents']).map(NpDocument.fromJson).toList(),
      supersededDocuments: _list(j['supersededDocuments']).map(NpDocument.fromJson).toList(),
      interviews: _list(j['interviews']).map(NpInterview.fromJson).toList(),
      cbChecks: _list(j['cbChecks']).map(NpCbCheck.fromJson).toList(),
      bgvReports: _list(j['bgvReports']).map(NpBgvReport.fromJson).toList(),
      approvals: _list(j['approvals']).map(NpApproval.fromJson).toList(),
      agreements: _list(j['agreements']).map(NpAgreement.fromJson).toList(),
      activations: _list(j['activations']).map(NpActivation.fromJson).toList(),
      allowedActions: _strList(j['allowedActions']).toSet(),
      missingKycDocs: _strList(j['missingKycDocs']),
      opsChecklist: _boolMap(j['opsChecklist']),
    );
  }

  bool can(String action) => allowedActions.contains(action);

  NpStepView? stepView(String step) {
    for (final s in steps) {
      if (s.step == step) return s;
    }
    return null;
  }

  NpBgvReport? get bgvDraft {
    for (final r in bgvReports) {
      if (r.draft) return r;
    }
    return null;
  }

  String get permanentAddress =>
      [addressLine, villageOrTown, district, state, pincode].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  String get communicationAddress => [commAddressLine, commVillageOrTown, commDistrict, commState, commPincode]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(', ');
}

// ── requests ──

/// Create / update payload (`NpCandidateRequest`). Null fields are sent as
/// null so an edit can clear a value.
class NpCandidateInput {
  String fullName = '';
  String? gender;
  String? dateOfBirth; // yyyy-MM-dd
  String mobileNumber = '';
  String? alternateMobile;
  String? email;
  String? fatherOrSpouseName;
  String? maritalStatus;
  String? spouseName;
  String? spouseDateOfBirth;
  String? spouseMobile;
  String? spouseOccupation;
  String? addressLine;
  String? villageOrTown;
  String? district;
  String? state;
  String? pincode;
  String? commAddressLine;
  String? commVillageOrTown;
  String? commDistrict;
  String? commState;
  String? commPincode;
  String? education;
  String? occupation;
  int? experienceYears;
  bool hasTwoWheeler = false;
  bool hasSmartphone = false;
  String? aadhaarLast4;
  String? panNumber;
  String? drivingLicenceNumber;
  String? bankAccountNumber;
  String? bankIfsc;
  String? bankName;
  String? bankAccountHolderName;
  int branchId = 0;
  Map<String, bool> eligibility = {};
  String? eligibilityNotes;
  String? remarks;
  int? photoFileId;

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'mobileNumber': mobileNumber,
        'alternateMobile': alternateMobile,
        'email': email,
        'fatherOrSpouseName': fatherOrSpouseName,
        'maritalStatus': maritalStatus,
        'spouseName': spouseName,
        'spouseDateOfBirth': spouseDateOfBirth,
        'spouseMobile': spouseMobile,
        'spouseOccupation': spouseOccupation,
        'addressLine': addressLine,
        'villageOrTown': villageOrTown,
        'district': district,
        'state': state,
        'pincode': pincode,
        'commAddressLine': commAddressLine,
        'commVillageOrTown': commVillageOrTown,
        'commDistrict': commDistrict,
        'commState': commState,
        'commPincode': commPincode,
        'education': education,
        'occupation': occupation,
        'experienceYears': experienceYears,
        'hasTwoWheeler': hasTwoWheeler,
        'hasSmartphone': hasSmartphone,
        'aadhaarLast4': aadhaarLast4,
        'panNumber': panNumber,
        'drivingLicenceNumber': drivingLicenceNumber,
        'bankAccountNumber': bankAccountNumber,
        'bankIfsc': bankIfsc,
        'bankName': bankName,
        'bankAccountHolderName': bankAccountHolderName,
        'branchId': branchId,
        'eligibility': eligibility,
        'eligibilityNotes': eligibilityNotes,
        'remarks': remarks,
        'photoFileId': photoFileId,
      };
}

class NpPdcInput {
  String chequeNumber = '';
  String? bankName;
  String? ifsc;
  String? accountNumber;

  Map<String, dynamic> toJson() => {
        'chequeNumber': chequeNumber,
        'bankName': bankName,
        'ifsc': ifsc,
        'accountNumber': accountNumber,
        'amount': null,
        'chequeDate': null,
      };
}

class NpBgvDraftInput {
  DateTime? visitAt;
  double? latitude;
  double? longitude;
  double? locationAccuracyM;
  bool addressVerified = false;
  String? addressAsFound;
  String? residenceType;
  int? yearsAtAddress;
  List<NpFamilyMember> familyMembers = [];
  Map<String, String> background = {};
  Map<String, bool> checklist = {};
  String? amRemarks;
  String? recommendation;

  Map<String, dynamic> toJson() => {
        'visitAt': visitAt == null ? null : npIsoDateTime(visitAt!),
        'latitude': latitude,
        'longitude': longitude,
        'locationAccuracyM': locationAccuracyM,
        'addressVerified': addressVerified,
        'addressAsFound': addressAsFound,
        'residenceType': residenceType,
        'yearsAtAddress': yearsAtAddress,
        'familyMembers': familyMembers.map((m) => m.toJson()).toList(),
        'background': background,
        'checklist': checklist,
        'amRemarks': amRemarks,
        'recommendation': recommendation,
      };
}

// ── responses ──

class NpOtpSent {
  final String maskedMobile;
  final int expiresInSeconds;
  final int attemptsRemaining;
  const NpOtpSent({required this.maskedMobile, required this.expiresInSeconds, required this.attemptsRemaining});
  factory NpOtpSent.fromJson(Map<String, dynamic> j) => NpOtpSent(
        maskedMobile: _str(j['maskedMobile']) ?? '',
        expiresInSeconds: _int(j['expiresInSeconds']),
        attemptsRemaining: _int(j['attemptsRemaining']),
      );
}

class NpAadhaarLink {
  final String referenceId;
  final String transactionId;
  final String link;
  const NpAadhaarLink({required this.referenceId, required this.transactionId, required this.link});
  factory NpAadhaarLink.fromJson(Map<String, dynamic> j) => NpAadhaarLink(
        referenceId: _str(j['referenceId']) ?? '',
        transactionId: _str(j['transactionId']) ?? '',
        link: _str(j['link']) ?? '',
      );
}

class NpAadhaarDetails {
  final bool verified;
  final String message;
  final String? fullName;
  final String? gender;
  final String? dateOfBirth;
  final String? fatherOrSpouseName;
  final String? addressLine;
  final String? villageOrTown;
  final String? district;
  final String? state;
  final String? pincode;
  final String? aadhaarLast4;
  final String? photoBase64;
  const NpAadhaarDetails({
    required this.verified,
    required this.message,
    this.fullName,
    this.gender,
    this.dateOfBirth,
    this.fatherOrSpouseName,
    this.addressLine,
    this.villageOrTown,
    this.district,
    this.state,
    this.pincode,
    this.aadhaarLast4,
    this.photoBase64,
  });
  factory NpAadhaarDetails.fromJson(Map<String, dynamic> j) => NpAadhaarDetails(
        verified: _bool(j['verified']),
        message: _str(j['message']) ?? '',
        fullName: _str(j['fullName']),
        gender: _str(j['gender']),
        dateOfBirth: _str(j['dateOfBirth']),
        fatherOrSpouseName: _str(j['fatherOrSpouseName']),
        addressLine: _str(j['addressLine']),
        villageOrTown: _str(j['villageOrTown']),
        district: _str(j['district']),
        state: _str(j['state']),
        pincode: _str(j['pincode']),
        aadhaarLast4: _str(j['aadhaarLast4']),
        photoBase64: _str(j['photoBase64']),
      );
}

class NpBankVerify {
  final bool verified;
  final String message;
  final String? accountHolderName;
  final String? bankName;
  final String? branchName;
  final String? ifsc;
  const NpBankVerify({
    required this.verified,
    required this.message,
    this.accountHolderName,
    this.bankName,
    this.branchName,
    this.ifsc,
  });
  factory NpBankVerify.fromJson(Map<String, dynamic> j) => NpBankVerify(
        verified: _bool(j['verified']),
        message: _str(j['message']) ?? '',
        accountHolderName: _str(j['accountHolderName']),
        bankName: _str(j['bankName']),
        branchName: _str(j['branchName']),
        ifsc: _str(j['ifsc']),
      );
}

class NpDashboard {
  final int total;
  final int draft;
  final int identificationInProgress;
  final int cbPending;
  final int bgvPending;
  final int dmPending;
  final int agreementPending;
  final int opsPending;
  final int activationPending;
  final int esafPending;
  final int activeNp;
  final int rejected;
  final int sentBack;
  const NpDashboard({
    this.total = 0,
    this.draft = 0,
    this.identificationInProgress = 0,
    this.cbPending = 0,
    this.bgvPending = 0,
    this.dmPending = 0,
    this.agreementPending = 0,
    this.opsPending = 0,
    this.activationPending = 0,
    this.esafPending = 0,
    this.activeNp = 0,
    this.rejected = 0,
    this.sentBack = 0,
  });
  factory NpDashboard.fromJson(Map<String, dynamic> j) => NpDashboard(
        total: _int(j['total']),
        draft: _int(j['draft']),
        identificationInProgress: _int(j['identificationInProgress']),
        cbPending: _int(j['cbPending']),
        bgvPending: _int(j['bgvPending']),
        dmPending: _int(j['dmPending']),
        agreementPending: _int(j['agreementPending']),
        opsPending: _int(j['opsPending']),
        activationPending: _int(j['activationPending']),
        esafPending: _int(j['esafPending']),
        activeNp: _int(j['activeNp']),
        rejected: _int(j['rejected']),
        sentBack: _int(j['sentBack']),
      );

  int valueOf(String key) {
    switch (key) {
      case 'total':
        return total;
      case 'draft':
        return draft;
      case 'identificationInProgress':
        return identificationInProgress;
      case 'cbPending':
        return cbPending;
      case 'bgvPending':
        return bgvPending;
      case 'dmPending':
        return dmPending;
      case 'agreementPending':
        return agreementPending;
      case 'opsPending':
        return opsPending;
      case 'activationPending':
        return activationPending;
      case 'esafPending':
        return esafPending;
      case 'activeNp':
        return activeNp;
      case 'rejected':
        return rejected;
      case 'sentBack':
        return sentBack;
      default:
        return 0;
    }
  }
}

class NpDocumentTypeConfig {
  final String code;
  final String label;
  final String stage;
  final bool mandatory;
  const NpDocumentTypeConfig({required this.code, required this.label, required this.stage, this.mandatory = false});
  factory NpDocumentTypeConfig.fromJson(Map<String, dynamic> j) => NpDocumentTypeConfig(
        code: _str(j['code']) ?? '',
        label: _str(j['label']) ?? _str(j['code']) ?? '',
        stage: _str(j['stage']) ?? 'OTHER',
        mandatory: _bool(j['mandatory']),
      );
}

class NpConfig {
  final List<String> eligibilityCriteria;
  final List<String> orientationItems;
  final List<NpDocumentTypeConfig> documentTypes;
  final List<String> bgvChecklist;
  final String npIdFormat;
  final int otpTtlSeconds;
  final int otpMaxAttempts;
  final bool aadhaarKycEnabled;
  final bool bankVerifyEnabled;
  const NpConfig({
    this.eligibilityCriteria = const [],
    this.orientationItems = const [],
    this.documentTypes = const [],
    this.bgvChecklist = const [],
    this.npIdFormat = '',
    this.otpTtlSeconds = 300,
    this.otpMaxAttempts = 3,
    this.aadhaarKycEnabled = false,
    this.bankVerifyEnabled = false,
  });

  static const empty = NpConfig();

  factory NpConfig.fromJson(Map<String, dynamic> j) => NpConfig(
        eligibilityCriteria: _strList(j['eligibilityCriteria']),
        orientationItems: _strList(j['orientationItems']),
        documentTypes: _list(j['documentTypes']).map(NpDocumentTypeConfig.fromJson).toList(),
        bgvChecklist: _strList(j['bgvChecklist']),
        npIdFormat: _str(j['npIdFormat']) ?? '',
        otpTtlSeconds: _int(j['otpTtlSeconds']),
        otpMaxAttempts: _int(j['otpMaxAttempts']),
        aadhaarKycEnabled: _bool(j['aadhaarKycEnabled']),
        bankVerifyEnabled: _bool(j['bankVerifyEnabled']),
      );

  List<NpDocumentTypeConfig> docTypesFor(String stage) => documentTypes.where((t) => t.stage == stage).toList();

  String docTypeLabel(String code) {
    for (final t in documentTypes) {
      if (t.code == code) return t.label;
    }
    return code.replaceAll('_', ' ');
  }
}

// ── formatting helpers ──

String npIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "yyyy-MM-ddTHH:mm:ss" — what a Java LocalDateTime parameter accepts.
String npIsoDateTime(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${npIsoDate(d)}T${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
}

String npTitle(String? s) {
  if (s == null || s.isEmpty) return '';
  final t = s.replaceAll('_', ' ').toLowerCase();
  return t[0].toUpperCase() + t.substring(1);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Display constants — same vocabulary as the web app.
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, String> kNpStatusLabels = {
  'DRAFT': 'Draft',
  'CANDIDATE_IDENTIFIED': 'Candidate identified',
  'ORIENTATION_COMPLETED': 'Orientation completed',
  'INTERVIEW_PASSED': 'Interview passed',
  'DOCUMENTS_SUBMITTED': 'Documents submitted',
  'CB_PENDING': 'CB check pending',
  'CB_APPROVED': 'CB approved',
  'BGV_PENDING': 'BGV pending',
  'BGV_COMPLETED': 'BGV completed',
  'DM_APPROVAL_PENDING': 'DM approval pending',
  'DM_APPROVED': 'DM approved',
  'AGREEMENT_PDC_PENDING': 'Agreement & PDC pending',
  'AGREEMENT_PDC_SUBMITTED': 'Agreement & PDC submitted',
  'OPS_VERIFICATION_PENDING': 'OPS verification pending',
  'OPS_APPROVED': 'OPS approved',
  'NP_ID_CREATED': 'NP ID created',
  'NAVA360_ACTIVATED': 'App activated',
  'ESAF_ID_CREATED': 'ESAF ID created',
  'ACTIVE_NP': 'Active NP',
  'INTERVIEW_REJECTED': 'Rejected at interview',
  'CB_REJECTED': 'Rejected at CB check',
  'BGV_REJECTED': 'Rejected at BGV',
  'DM_REJECTED': 'Rejected by DM',
  'OPS_REJECTED': 'Rejected by OPS',
  'SENT_BACK_FOR_CORRECTION': 'Sent back for correction',
};

String npStatusLabel(String? status) =>
    status == null ? '—' : (kNpStatusLabels[status] ?? npTitle(status));

/// Every status, in workflow order — drives the status filter.
const List<String> kNpStatuses = [
  'DRAFT',
  'CANDIDATE_IDENTIFIED',
  'ORIENTATION_COMPLETED',
  'INTERVIEW_PASSED',
  'DOCUMENTS_SUBMITTED',
  'CB_PENDING',
  'CB_APPROVED',
  'BGV_PENDING',
  'BGV_COMPLETED',
  'DM_APPROVAL_PENDING',
  'DM_APPROVED',
  'AGREEMENT_PDC_PENDING',
  'AGREEMENT_PDC_SUBMITTED',
  'OPS_VERIFICATION_PENDING',
  'OPS_APPROVED',
  'NP_ID_CREATED',
  'NAVA360_ACTIVATED',
  'ESAF_ID_CREATED',
  'ACTIVE_NP',
  'SENT_BACK_FOR_CORRECTION',
  'INTERVIEW_REJECTED',
  'CB_REJECTED',
  'BGV_REJECTED',
  'DM_REJECTED',
  'OPS_REJECTED',
];

Color npStatusColor(String status) {
  if (status == 'ACTIVE_NP') return AppColors.success;
  if (status.endsWith('_REJECTED')) return AppColors.danger;
  if (status == 'SENT_BACK_FOR_CORRECTION') return const Color(0xFFEA580C); // orange-600
  if (status == 'DRAFT') return AppColors.muted;
  if (status.endsWith('_PENDING')) return AppColors.warning;
  if (status.endsWith('_SUBMITTED')) return const Color(0xFF4F46E5); // indigo-600
  if (status.endsWith('_APPROVED') ||
      status.endsWith('_COMPLETED') ||
      status.endsWith('_CREATED') ||
      status.endsWith('_ACTIVATED') ||
      status == 'INTERVIEW_PASSED') {
    return AppColors.success;
  }
  return AppColors.info;
}

class NpStepInfo {
  final String step;
  final String label;
  final String short;
  const NpStepInfo(this.step, this.label, this.short);
}

/// The 13 workflow steps, in order.
const List<NpStepInfo> kNpSteps = [
  NpStepInfo('CANDIDATE', 'Candidate identification', 'Candidate'),
  NpStepInfo('ORIENTATION', 'Orientation', 'Orientation'),
  NpStepInfo('INTERVIEW', 'Interview', 'Interview'),
  NpStepInfo('KYC', 'KYC documents', 'KYC'),
  NpStepInfo('CB', 'CB check', 'CB'),
  NpStepInfo('BGV', 'Background verification', 'BGV'),
  NpStepInfo('DM_APPROVAL', 'DM approval', 'DM'),
  NpStepInfo('AGREEMENT_PDC', 'Agreement & PDC', 'Agreement'),
  NpStepInfo('OPS', 'OPS verification', 'OPS'),
  NpStepInfo('NP_ID', 'NP ID generation', 'NP ID'),
  NpStepInfo('NAVA360', 'App activation', 'App'),
  NpStepInfo('ESAF', 'ESAF ID', 'ESAF'),
  NpStepInfo('ACTIVATION', 'Final activation', 'Activate'),
];

const List<String> kNpOpsChecklistKeys = [
  'kyc',
  'interview',
  'cb',
  'bgv',
  'dmApproval',
  'agreement',
  'pdc1',
  'pdc2',
];

const Map<String, String> kNpOpsChecklistLabels = {
  'kyc': 'KYC documents complete',
  'interview': 'Interview passed',
  'cb': 'CB check approved',
  'bgv': 'BGV report submitted',
  'dmApproval': 'DM approval recorded',
  'agreement': 'Agreement uploaded',
  'pdc1': 'PDC 1 received',
  'pdc2': 'PDC 2 received',
};

/// Free-text background observations captured during a BGV visit.
const List<MapEntry<String, String>> kNpBgvBackgroundKeys = [
  MapEntry('neighbourFeedback', 'Neighbour feedback'),
  MapEntry('priorLoans', 'Prior MFI / loan history'),
  MapEntry('otherEmployment', 'Other employment'),
  MapEntry('politicalAffiliation', 'Political affiliation'),
  MapEntry('notes', 'Other notes'),
];

const List<String> kNpGenders = ['MALE', 'FEMALE', 'OTHER'];
const List<String> kNpMaritalStatuses = ['UNMARRIED', 'MARRIED', 'WIDOWED', 'DIVORCED', 'SEPARATED'];
const List<String> kNpResidenceTypes = ['OWN', 'RENTED', 'FAMILY', 'OTHER'];
const List<String> kNpCorrectionStages = ['KYC', 'BGV', 'AGREEMENT_PDC'];

class NpDashboardCard {
  final String key;
  final String label;
  final List<String> statuses;
  final Color color;
  final IconData icon;
  const NpDashboardCard(this.key, this.label, this.statuses, this.color, this.icon);
}

/// Dashboard KPI tiles. Tapping one puts `statuses` into the list filter.
final List<NpDashboardCard> kNpDashboardCards = [
  const NpDashboardCard('total', 'Total', [], AppColors.ink, Icons.people_alt_rounded),
  const NpDashboardCard('draft', 'Draft', ['DRAFT'], AppColors.muted, Icons.edit_note_rounded),
  const NpDashboardCard('cbPending', 'CB pending', ['CB_PENDING'], AppColors.warning, Icons.credit_score_rounded),
  const NpDashboardCard('bgvPending', 'BGV pending', ['CB_APPROVED', 'BGV_PENDING'], AppColors.warning, Icons.home_work_rounded),
  const NpDashboardCard('dmPending', 'DM approval', ['BGV_COMPLETED', 'DM_APPROVAL_PENDING'], AppColors.warning, Icons.verified_user_rounded),
  const NpDashboardCard('agreementPending', 'Agreement/PDC', ['DM_APPROVED', 'AGREEMENT_PDC_PENDING'], AppColors.warning, Icons.description_rounded),
  const NpDashboardCard('opsPending', 'OPS verification', ['AGREEMENT_PDC_SUBMITTED', 'OPS_VERIFICATION_PENDING'], AppColors.warning, Icons.fact_check_rounded),
  const NpDashboardCard('activationPending', 'App activation', ['OPS_APPROVED', 'NP_ID_CREATED'], Color(0xFF4F46E5), Icons.phonelink_setup_rounded),
  const NpDashboardCard('esafPending', 'ESAF pending', ['NAVA360_ACTIVATED'], Color(0xFF4F46E5), Icons.badge_rounded),
  const NpDashboardCard('activeNp', 'Active NP', ['ACTIVE_NP'], AppColors.success, Icons.check_circle_rounded),
  const NpDashboardCard('rejected', 'Rejected', ['INTERVIEW_REJECTED', 'CB_REJECTED', 'BGV_REJECTED', 'DM_REJECTED', 'OPS_REJECTED'], AppColors.danger, Icons.cancel_rounded),
  const NpDashboardCard('sentBack', 'Sent back', ['SENT_BACK_FOR_CORRECTION'], Color(0xFFEA580C), Icons.undo_rounded),
];
