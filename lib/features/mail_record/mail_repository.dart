import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'mail_models.dart';

final mailRepositoryProvider =
    Provider((ref) => MailRepository(ref.watch(apiClientProvider)));

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `period`/`month` string ("yyyy-MM-01") for the first of the given month.
String isoMonth(DateTime d) => _isoDate(DateTime(d.year, d.month, 1));

List<Map<String, dynamic>> _asList(dynamic d) =>
    ((d as List?) ?? const []).cast<Map<String, dynamic>>();

/// Pulls the `content` list out of a paged `ApiResponse<PageResponse<T>>`
/// `data` payload, tolerating a bare list for forward-compatibility.
List<Map<String, dynamic>> _pageContent(dynamic d) {
  if (d is List) return d.cast<Map<String, dynamic>>();
  final content = (d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
  return content.cast<Map<String, dynamic>>();
}

/// Admin Tools · Mail Record API client — typed wrappers over
/// `/api/admin/mail/**`. All requests carry the JWT + `X-Device-Type: MOBILE`
/// via the shared [ApiClient] interceptor; server-side RBAC
/// (`ADMIN_MAIL_*`) gates every call. The biggest of the four Admin Tools
/// features: mail register, branch-month audits, stock & shipments,
/// complaint departments, complaints, and a shared audit trail.
class MailRepository {
  MailRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/admin/mail';

  // ── Branches (for pickers) ─────────────────────────────────────────────

  Future<List<MailBranchOption>> listBranches() {
    return _api.get<List<MailBranchOption>>(
      '/api/org/branches',
      parse: (d) => _asList(d).map(MailBranchOption.fromJson).toList(),
    );
  }

  // ── Mail register ────────────────────────────────────────────────────────

  Future<List<MailRecord>> listRecords({
    int? branchId,
    String? mailType,
    String? from,
    String? to,
    int page = 0,
    int size = 100,
  }) {
    return _api.get<List<MailRecord>>(
      '$_base/records',
      query: {
        if (branchId != null) 'branchId': branchId,
        if (mailType != null) 'mailType': mailType,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(MailRecord.fromJson).toList(),
    );
  }

  Future<MailRecord> createRecord(Map<String, dynamic> body) {
    return _api.post<MailRecord>(
      '$_base/records',
      body: body,
      parse: (d) => MailRecord.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<MailRecord> updateRecord(int id, Map<String, dynamic> body) {
    return _api.put<MailRecord>(
      '$_base/records/$id',
      body: body,
      parse: (d) => MailRecord.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> deleteRecord(int id) {
    return _api.raw.delete('$_base/records/$id');
  }

  Future<List<MailEditLog>> recordEditHistory(int id) {
    return _api.get<List<MailEditLog>>(
      '$_base/records/$id/edit-history',
      parse: (d) => _asList(d).map(MailEditLog.fromJson).toList(),
    );
  }

  /// Builds the create/update body for a mail record.
  Map<String, dynamic> recordBody({
    required String mailType,
    required DateTime date,
    required int branchId,
    int? employeeId,
    String? department,
    String? documents,
    String? docketNumber,
    String? courierStatus,
    String? particular,
    String? details,
    String? customersJson,
  }) =>
      {
        'mailType': mailType,
        'date': _isoDate(date),
        'branchId': branchId,
        'employeeId': employeeId,
        'department': department,
        'documents': documents,
        'docketNumber': docketNumber,
        'courierStatus': courierStatus,
        'particular': particular,
        'details': details,
        'customersJson': customersJson,
      };

  // ── Branch-month audits ──────────────────────────────────────────────────

  Future<List<MailAuditBranchMonth>> listAuditMonths(String month) {
    return _api.get<List<MailAuditBranchMonth>>(
      '$_base/audit-branch-months',
      query: {'month': month},
      parse: (d) => _asList(d).map(MailAuditBranchMonth.fromJson).toList(),
    );
  }

  Future<MailAuditBranchMonth> startAuditMonth(String month, int branchId) {
    return _api.post<MailAuditBranchMonth>(
      '$_base/audit-branch-months/start',
      query: {'month': month, 'branchId': branchId},
      parse: (d) => MailAuditBranchMonth.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<MailAuditBranchMonth> completeAuditMonth(int id) {
    return _api.post<MailAuditBranchMonth>(
      '$_base/audit-branch-months/$id/complete',
      parse: (d) => MailAuditBranchMonth.fromJson(d as Map<String, dynamic>),
    );
  }

  // ── Stock & shipments ────────────────────────────────────────────────────

  Future<MailStockEntry> setStock({
    required int branchId,
    required String itemName,
    required num quantity,
    String? unit,
  }) {
    return _api.post<MailStockEntry>(
      '$_base/stock/entries',
      body: {'branchId': branchId, 'itemName': itemName, 'quantity': quantity, 'unit': unit},
      parse: (d) => MailStockEntry.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<MailStockEntry>> listStockForBranch(int branchId) {
    return _api.get<List<MailStockEntry>>(
      '$_base/stock/entries/branch/$branchId',
      parse: (d) => _asList(d).map(MailStockEntry.fromJson).toList(),
    );
  }

  Future<MailShipment> dispatchShipment({
    required int fromBranchId,
    required int toBranchId,
    required String itemName,
    required num quantity,
  }) {
    return _api.post<MailShipment>(
      '$_base/stock/shipments',
      body: {
        'fromBranchId': fromBranchId,
        'toBranchId': toBranchId,
        'itemName': itemName,
        'quantity': quantity,
      },
      parse: (d) => MailShipment.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<MailShipment> receiveShipment(int id, num receivedQuantity) {
    return _api.post<MailShipment>(
      '$_base/stock/shipments/$id/receive',
      body: {'receivedQuantity': receivedQuantity},
      parse: (d) => MailShipment.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<MailShipment>> listShipments() {
    return _api.get<List<MailShipment>>(
      '$_base/stock/shipments',
      parse: (d) => _asList(d).map(MailShipment.fromJson).toList(),
    );
  }

  Future<List<MailShipment>> listPendingShipmentsForBranch(int branchId) {
    return _api.get<List<MailShipment>>(
      '$_base/stock/shipments/branch/$branchId/pending',
      parse: (d) => _asList(d).map(MailShipment.fromJson).toList(),
    );
  }

  // ── Complaint departments ────────────────────────────────────────────────

  Future<List<MailComplaintDept>> listComplaintDepartments({bool activeOnly = false}) {
    return _api.get<List<MailComplaintDept>>(
      '$_base/complaint-departments',
      query: {'activeOnly': activeOnly},
      parse: (d) => _asList(d).map(MailComplaintDept.fromJson).toList(),
    );
  }

  Future<MailComplaintDept> createComplaintDepartment({
    required String deptKey,
    required String name,
    String? icon,
    String? problemsJson,
    String? deptCode,
    int? sortOrder,
    bool? active,
  }) {
    return _api.post<MailComplaintDept>(
      '$_base/complaint-departments',
      body: _deptBody(
        deptKey: deptKey,
        name: name,
        icon: icon,
        problemsJson: problemsJson,
        deptCode: deptCode,
        sortOrder: sortOrder,
        active: active,
      ),
      parse: (d) => MailComplaintDept.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<MailComplaintDept> updateComplaintDepartment(
    int id, {
    required String deptKey,
    required String name,
    String? icon,
    String? problemsJson,
    String? deptCode,
    int? sortOrder,
    bool? active,
  }) {
    return _api.put<MailComplaintDept>(
      '$_base/complaint-departments/$id',
      body: _deptBody(
        deptKey: deptKey,
        name: name,
        icon: icon,
        problemsJson: problemsJson,
        deptCode: deptCode,
        sortOrder: sortOrder,
        active: active,
      ),
      parse: (d) => MailComplaintDept.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> deleteComplaintDepartment(int id) {
    return _api.raw.delete('$_base/complaint-departments/$id');
  }

  Map<String, dynamic> _deptBody({
    required String deptKey,
    required String name,
    String? icon,
    String? problemsJson,
    String? deptCode,
    int? sortOrder,
    bool? active,
  }) =>
      {
        'deptKey': deptKey,
        'name': name,
        'icon': icon,
        'problemsJson': problemsJson,
        'deptCode': deptCode,
        'sortOrder': sortOrder,
        'active': active,
      };

  // ── Complaints ───────────────────────────────────────────────────────────

  Future<List<MailComplaint>> listComplaints({
    int? branchId,
    String? status,
    int page = 0,
    int size = 100,
  }) {
    return _api.get<List<MailComplaint>>(
      '$_base/complaints',
      query: {
        if (branchId != null) 'branchId': branchId,
        if (status != null) 'status': status,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(MailComplaint.fromJson).toList(),
    );
  }

  Future<MailComplaint> raiseComplaint({
    required int branchId,
    required DateTime date,
    int? deptId,
    required String subject,
    String? content,
    int? raisedByEmployeeId,
    String? raisedByName,
    String? phone,
  }) {
    return _api.post<MailComplaint>(
      '$_base/complaints',
      body: {
        'branchId': branchId,
        'date': _isoDate(date),
        'deptId': deptId,
        'subject': subject,
        'content': content,
        'raisedByEmployeeId': raisedByEmployeeId,
        'raisedByName': raisedByName,
        'phone': phone,
      },
      parse: (d) => MailComplaint.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<MailComplaint> changeComplaintStatus(int id, String status, {String? note}) {
    return _api.post<MailComplaint>(
      '$_base/complaints/$id/status',
      body: {'status': status, 'note': note},
      parse: (d) => MailComplaint.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<MailComplaintLog>> complaintHistory(int id) {
    return _api.get<List<MailComplaintLog>>(
      '$_base/complaints/$id/history',
      parse: (d) => _asList(d).map(MailComplaintLog.fromJson).toList(),
    );
  }

  // ── Audit trail ──────────────────────────────────────────────────────────

  Future<List<MailAuditLog>> auditTrail() {
    return _api.get<List<MailAuditLog>>(
      '$_base/audit',
      parse: (d) => _asList(d).map(MailAuditLog.fromJson).toList(),
    );
  }
}
