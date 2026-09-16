import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'rent_models.dart';

final rentRepositoryProvider =
    Provider((ref) => RentRepository(ref.watch(apiClientProvider)));

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `period` string ("yyyy-MM-01") for the first of the given month.
String isoPeriod(DateTime d) => _isoDate(DateTime(d.year, d.month, 1));

List<Map<String, dynamic>> _asList(dynamic d) =>
    ((d as List?) ?? const []).cast<Map<String, dynamic>>();

/// Admin Tools · Rent Management API client — typed wrappers over
/// `/api/admin/rent/**`. All requests carry the JWT + `X-Device-Type: MOBILE`
/// via the shared [ApiClient] interceptor; server-side RBAC
/// (`ADMIN_RENT_*`) gates every call.
class RentRepository {
  RentRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/admin/rent';

  // ── Branches ─────────────────────────────────────────────────────────────

  Future<List<RentBranch>> listBranches({bool activeOnly = false}) {
    return _api.get<List<RentBranch>>(
      '$_base/branches',
      query: {'activeOnly': activeOnly},
      parse: (d) => _asList(d).map(RentBranch.fromJson).toList(),
    );
  }

  Future<RentBranch> createBranch({
    required String branchName,
    String? branchCode,
    String? ownerName,
    String? address,
    double? rent,
    double? rentAdvance,
    DateTime? startDate,
    bool? gstApplicable,
    bool active = true,
  }) {
    return _api.post<RentBranch>(
      '$_base/branches',
      body: _branchBody(
        branchName: branchName,
        branchCode: branchCode,
        ownerName: ownerName,
        address: address,
        rent: rent,
        rentAdvance: rentAdvance,
        startDate: startDate,
        gstApplicable: gstApplicable,
        active: active,
      ),
      parse: (d) => RentBranch.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<RentBranch> updateBranch(
    int id, {
    required String branchName,
    String? branchCode,
    String? ownerName,
    String? address,
    double? rent,
    double? rentAdvance,
    DateTime? startDate,
    bool? gstApplicable,
    bool active = true,
  }) {
    return _api.put<RentBranch>(
      '$_base/branches/$id',
      body: _branchBody(
        branchName: branchName,
        branchCode: branchCode,
        ownerName: ownerName,
        address: address,
        rent: rent,
        rentAdvance: rentAdvance,
        startDate: startDate,
        gstApplicable: gstApplicable,
        active: active,
      ),
      parse: (d) => RentBranch.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> deleteBranch(int id) {
    return _api.raw.delete('$_base/branches/$id');
  }

  Map<String, dynamic> _branchBody({
    required String branchName,
    String? branchCode,
    String? ownerName,
    String? address,
    double? rent,
    double? rentAdvance,
    DateTime? startDate,
    bool? gstApplicable,
    bool active = true,
  }) =>
      {
        'branchName': branchName,
        'branchCode': branchCode,
        'ownerName': ownerName,
        'address': address,
        'rent': rent,
        'rentAdvance': rentAdvance,
        'startDate': startDate == null ? null : _isoDate(startDate),
        'gstApplicable': gstApplicable,
        'active': active,
      };

  // ── Rent payable ─────────────────────────────────────────────────────────

  Future<List<RentPayable>> listPayableForPeriod(String period) {
    return _api.get<List<RentPayable>>(
      '$_base/payable',
      query: {'period': period},
      parse: (d) => _asList(d).map(RentPayable.fromJson).toList(),
    );
  }

  Future<List<RentPayable>> generatePayable(String period) {
    return _api.post<List<RentPayable>>(
      '$_base/payable/generate',
      query: {'period': period},
      parse: (d) => _asList(d).map(RentPayable.fromJson).toList(),
    );
  }

  Future<RentPayable> submitPayable(int id) {
    return _api.post<RentPayable>(
      '$_base/payable/$id/submit',
      parse: (d) => RentPayable.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<RentPayable> approvePayable(int id) {
    return _api.post<RentPayable>(
      '$_base/payable/$id/approve',
      parse: (d) => RentPayable.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<RentPayable> markPayablePaid(int id, {String? paidUtr}) {
    return _api.post<RentPayable>(
      '$_base/payable/$id/mark-paid',
      body: {'paidUtr': paidUtr},
      parse: (d) => RentPayable.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<RentPayable> holdPayable(int id, {String? holdReason}) {
    return _api.post<RentPayable>(
      '$_base/payable/$id/hold',
      body: {'holdReason': holdReason},
      parse: (d) => RentPayable.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<RentPayable> releasePayableHold(int id) {
    return _api.post<RentPayable>(
      '$_base/payable/$id/release-hold',
      parse: (d) => RentPayable.fromJson(d as Map<String, dynamic>),
    );
  }

  // ── Notices ──────────────────────────────────────────────────────────────

  Future<List<RentNotice>> listNotices() {
    return _api.get<List<RentNotice>>(
      '$_base/notices',
      parse: (d) => _asList(d).map(RentNotice.fromJson).toList(),
    );
  }

  Future<RentNotice> issueNotice({
    required int branchId,
    required String subject,
    String? body,
    required DateTime issuedOn,
    bool holdRent = false,
  }) {
    return _api.post<RentNotice>(
      '$_base/notices',
      body: {
        'branchId': branchId,
        'subject': subject,
        'body': body,
        'issuedOn': _isoDate(issuedOn),
        'holdRent': holdRent,
      },
      parse: (d) => RentNotice.fromJson(d as Map<String, dynamic>),
    );
  }

  // ── Utility bills ────────────────────────────────────────────────────────

  Future<List<RentUtilityBill>> listUtilityBillsForPeriod(String period) {
    return _api.get<List<RentUtilityBill>>(
      '$_base/utility-bills',
      query: {'period': period},
      parse: (d) => _asList(d).map(RentUtilityBill.fromJson).toList(),
    );
  }

  /// Upserts a bill — saving again for the same branch/kind/period updates
  /// the existing record (server-side).
  Future<RentUtilityBill> upsertUtilityBill({
    required int branchId,
    required String period,
    required String kind,
    double? amount,
    String? billNumber,
    DateTime? billDate,
    DateTime? dueDate,
    String? notes,
  }) {
    return _api.post<RentUtilityBill>(
      '$_base/utility-bills',
      body: {
        'branchId': branchId,
        'period': period,
        'kind': kind,
        'amount': amount,
        'billNumber': billNumber,
        'billDate': billDate == null ? null : _isoDate(billDate),
        'dueDate': dueDate == null ? null : _isoDate(dueDate),
        'notes': notes,
      },
      parse: (d) => RentUtilityBill.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<RentUtilityBill> markUtilityBillPaid(int id, String paidUtr) {
    return _api.post<RentUtilityBill>(
      '$_base/utility-bills/$id/mark-paid',
      body: {'paidUtr': paidUtr},
      parse: (d) => RentUtilityBill.fromJson(d as Map<String, dynamic>),
    );
  }

  // ── Audit trail ──────────────────────────────────────────────────────────

  Future<List<RentAuditLog>> auditTrail() {
    return _api.get<List<RentAuditLog>>(
      '$_base/audit',
      parse: (d) => _asList(d).map(RentAuditLog.fromJson).toList(),
    );
  }
}
