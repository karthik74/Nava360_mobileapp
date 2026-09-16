import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Full profile of a single employee (mirror of the backend EmployeeResponse).
/// Used by the manager-facing Employee Detail screen.
class EmployeeDetail {
  EmployeeDetail({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.active,
    this.employeeCode,
    this.email,
    this.phone,
    this.gender,
    this.designation,
    this.department,
    this.businessVertical,
    this.joiningDate,
    this.dateOfBirth,
    this.address,
    this.profileImageUrl,
    this.branchLabel,
    this.reportingManagerName,
    this.employeeType,
    this.bankAccountNumber,
    this.bankIfsc,
    this.bankName,
    this.pfAccountNumber,
    this.uanNumber,
    this.esiNumber,
  });

  final int id;
  final String firstName;
  final String lastName;
  final bool active;
  final String? employeeCode;
  final String? email;
  final String? phone;
  final String? gender;
  final String? designation;
  final String? department;
  final String? businessVertical;
  final String? joiningDate; // yyyy-MM-dd
  final String? dateOfBirth; // yyyy-MM-dd
  final String? address;
  final String? profileImageUrl;
  final String? branchLabel;
  final String? reportingManagerName;
  final String? employeeType;

  // Sensitive — shown only to authorised managers/admins.
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? bankName;
  final String? pfAccountNumber;
  final String? uanNumber;
  final String? esiNumber;

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? (employeeCode ?? 'Employee') : n;
  }

  factory EmployeeDetail.fromJson(Map<String, dynamic> j) => EmployeeDetail(
        id: (j['id'] as num).toInt(),
        firstName: (j['firstName'] as String?) ?? '',
        lastName: (j['lastName'] as String?) ?? '',
        active: j['active'] != false,
        employeeCode: j['employeeCode'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        gender: j['gender'] as String?,
        designation: j['designation'] as String?,
        department: j['department'] as String?,
        businessVertical: j['businessVertical'] as String?,
        joiningDate: j['joiningDate'] as String?,
        dateOfBirth: j['dateOfBirth'] as String?,
        address: j['address'] as String?,
        profileImageUrl: j['profileImageUrl'] as String?,
        branchLabel: j['branchLabel'] as String?,
        reportingManagerName: j['reportingManagerName'] as String?,
        employeeType: j['employeeType'] as String?,
        bankAccountNumber: j['bankAccountNumber'] as String?,
        bankIfsc: j['bankIfsc'] as String?,
        bankName: j['bankName'] as String?,
        pfAccountNumber: j['pfAccountNumber'] as String?,
        uanNumber: j['uanNumber'] as String?,
        esiNumber: j['esiNumber'] as String?,
      );
}

/// A document uploaded against an employee (Aadhaar, PAN, bank proof, …).
class EmployeeDocument {
  EmployeeDocument({
    required this.id,
    required this.docType,
    this.docTypeLabel,
    this.label,
    this.fileName,
    this.url,
    this.uploadedBy,
    this.createdAt,
  });

  final int id;
  final String docType; // e.g. AADHAAR, PAN, BANK_PROOF, APPOINTMENT_LETTER, ID_PROOF
  final String? docTypeLabel;
  final String? label;
  final String? fileName;
  final String? url; // relative file URL (/api/files/{id})
  final String? uploadedBy;
  final String? createdAt; // ISO datetime

  factory EmployeeDocument.fromJson(Map<String, dynamic> j) => EmployeeDocument(
        id: (j['id'] as num).toInt(),
        docType: (j['docType'] as String?) ?? '',
        docTypeLabel: j['docTypeLabel'] as String?,
        label: j['label'] as String?,
        fileName: j['fileName'] as String?,
        url: j['url'] as String?,
        uploadedBy: j['uploadedBy'] as String?,
        createdAt: j['createdAt'] as String?,
      );
}

/// One field change inside a timeline entry (old → new).
class EmployeeChangeItem {
  EmployeeChangeItem({
    required this.field,
    required this.label,
    this.oldValue,
    this.newValue,
  });
  final String field;
  final String label;
  final String? oldValue;
  final String? newValue;

  factory EmployeeChangeItem.fromJson(Map<String, dynamic> j) => EmployeeChangeItem(
        field: (j['field'] as String?) ?? '',
        label: (j['label'] as String?) ?? '',
        oldValue: j['oldValue'] as String?,
        newValue: j['newValue'] as String?,
      );
}

/// Employee-details timeline entry: who changed what on the record, and when.
/// Mirror of the backend EmployeeChangeLogResponse.
class EmployeeChangeLog {
  EmployeeChangeLog({
    required this.id,
    required this.action,
    required this.actorName,
    required this.changes,
    this.actorUsername,
    this.createdAt,
  });
  final int id;

  /// CREATED | UPDATED
  final String action;
  final String actorName;
  final String? actorUsername;
  final DateTime? createdAt;
  final List<EmployeeChangeItem> changes;

  bool get isCreated => action == 'CREATED';

  factory EmployeeChangeLog.fromJson(Map<String, dynamic> j) => EmployeeChangeLog(
        id: (j['id'] as num).toInt(),
        action: (j['action'] as String?) ?? 'UPDATED',
        actorName: (j['actorName'] as String?) ?? 'System',
        actorUsername: j['actorUsername'] as String?,
        createdAt: j['createdAt'] == null
            ? null
            : DateTime.tryParse(j['createdAt'] as String)?.toLocal(),
        changes: ((j['changes'] as List?) ?? const [])
            .map((e) => EmployeeChangeItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class EmployeeDetailRepository {
  EmployeeDetailRepository(this._api);
  final ApiClient _api;

  /// Full profile of [id]. Backend: GET /api/employees/{id} (any authenticated
  /// user; sensitive fields are gated client-side by role).
  Future<EmployeeDetail> getById(int id) {
    return _api.get<EmployeeDetail>(
      '/api/employees/$id',
      parse: (d) => EmployeeDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Change history of [id], newest first: what changed on the record, by
  /// whom and when. Backend: GET /api/employees/{id}/timeline (EMPLOYEE_VIEW,
  /// scoped like the profile). Paged — one large page is enough for the app.
  Future<List<EmployeeChangeLog>> timeline(int id, {int size = 100}) {
    return _api.get<List<EmployeeChangeLog>>(
      '/api/employees/$id/timeline',
      query: {'size': '$size'},
      parse: (d) {
        final content = d is List
            ? d
            : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const []);
        return content
            .map((e) => EmployeeChangeLog.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Documents on file for [id]. Backend requires EMPLOYEE_VIEW, so callers
  /// should only invoke this for authorised managers/admins.
  Future<List<EmployeeDocument>> documents(int id) {
    return _api.get<List<EmployeeDocument>>(
      '/api/employees/$id/documents',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => EmployeeDocument.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

final employeeDetailRepositoryProvider = Provider<EmployeeDetailRepository>(
  (ref) => EmployeeDetailRepository(ref.watch(apiClientProvider)),
);
