import 'dart:typed_data';

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

  /// Register report (Summary + Outward/Inward sheets); the server limits it to what the caller may see.
  Future<Uint8List> exportRecords({String? mailType}) =>
      _api.getBytes('$_base/records/export', query: {if (mailType != null) 'mailType': mailType});

  /// Stock report (Summary + Inventory + Transactions) for one branch.
  Future<Uint8List> exportStock({int? branchId}) =>
      _api.getBytes('$_base/stock/export', query: {if (branchId != null) 'branchId': branchId});

  Future<List<MailBranchOption>> listBranches() {
    return _api.get<List<MailBranchOption>>(
      '/api/org/branches',
      parse: (d) => _asList(d).map(MailBranchOption.fromJson).toList(),
    );
  }

  // ── Mail register ────────────────────────────────────────────────────────

  /// Dashboard KPIs + recent records for one branch.
  Future<MailDashboard> dashboardForBranch(int branchId) => _api.get<MailDashboard>(
        '$_base/records/dashboard/branch/$branchId',
        parse: (d) => MailDashboard.fromJson(d as Map<String, dynamic>),
      );

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
    /// Null when the counterparty is "Others" — then [otherParty] is required.
    int? branchId,
    String? otherParty,
    /// Outward entries only; ignored for inward.
    double? amount,
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
        'otherParty': otherParty,
        'amount': amount,
        'employeeId': employeeId,
        'department': department,
        'documents': documents,
        'docketNumber': docketNumber,
        'courierStatus': courierStatus,
        'particular': particular,
        'details': details,
        'customersJson': customersJson,
      };

  // ── Stock & shipments ────────────────────────────────────────────────────

  /// Adds an item to the shared list every branch sees — full-access admins only. It carries no branch and
  /// no quantity: each branch starts at 0 and changes its own quantity only through [adjustStock].
  Future<void> addItem({
    required String itemName,
    String? invoice,
    int? lowStockThreshold,
  }) {
    return _api.post<void>(
      '$_base/stock/items',
      body: {'itemName': itemName, 'invoice': invoice, 'lowStockThreshold': lowStockThreshold},
      parse: (_) {},
    );
  }

  /// Which branches are low on which items — full-access admins only.
  Future<List<MailLowStockRow>> lowStock() {
    return _api.get<List<MailLowStockRow>>(
      '$_base/stock/low-stock',
      parse: (d) => _asList((d as Map<String, dynamic>)['rows']).map(MailLowStockRow.fromJson).toList(),
    );
  }

  /// Stock in / out ([type] is `IN` or `OUT`) against an existing item.
  Future<MailStockEntry> adjustStock({
    required int branchId,
    required String itemName,
    required String type,
    required int quantity,
  }) {
    return _api.post<MailStockEntry>(
      '$_base/stock/entries/adjust',
      body: {'branchId': branchId, 'itemName': itemName, 'type': type, 'quantity': quantity},
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

  // ── Complaints ───────────────────────────────────────────────────────────

  /// The raise form's pre-filled values: the caller's own name/branch/phone/department and the HR department list.
  Future<MailComplaintFormDefaults> complaintFormDefaults() {
    return _api.get<MailComplaintFormDefaults>(
      '$_base/complaints/form-defaults',
      parse: (d) => MailComplaintFormDefaults.fromJson(d as Map<String, dynamic>),
    );
  }

  /// A full-access admin gets every complaint; anyone else only the ones they raised (the server decides).
  Future<List<MailComplaint>> listComplaints({
    int? branchId,
    String? status,
    /// Inclusive dates filtering on the day the complaint was raised.
    DateTime? from,
    DateTime? to,
    int page = 0,
    int size = 100,
  }) {
    return _api.get<List<MailComplaint>>(
      '$_base/complaints',
      query: {
        if (branchId != null) 'branchId': branchId,
        if (status != null) 'status': status,
        if (from != null) 'from': _isoDate(from),
        if (to != null) 'to': _isoDate(to),
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(MailComplaint.fromJson).toList(),
    );
  }

  /// The days that have complaints (in the caller's own view) and how many on each.
  Future<List<MailComplaintDate>> complaintDates() {
    return _api.get<List<MailComplaintDate>>(
      '$_base/complaints/dates',
      parse: (d) => _asList(d).map(MailComplaintDate.fromJson).toList(),
    );
  }

  /// Name, branch, phone and department come from the raiser's own record — these only override them.
  Future<MailComplaint> raiseComplaint({
    int? branchId,
    String? department,
    required String subject,
    String? content,
    String? phone,
  }) {
    return _api.post<MailComplaint>(
      '$_base/complaints',
      body: {
        'branchId': branchId,
        'department': department,
        'subject': subject,
        'content': content,
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
}
