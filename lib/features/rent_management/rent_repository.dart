import 'dart:typed_data';

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
    int? orgBranchId,
    DateTime? gstLockedUntil,
    double? gstRatePercent,
    double? tdsRatePercent,
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
        orgBranchId: orgBranchId,
        gstLockedUntil: gstLockedUntil,
        gstRatePercent: gstRatePercent,
        tdsRatePercent: tdsRatePercent,
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
    int? orgBranchId,
    DateTime? gstLockedUntil,
    double? gstRatePercent,
    double? tdsRatePercent,
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
        orgBranchId: orgBranchId,
        gstLockedUntil: gstLockedUntil,
        gstRatePercent: gstRatePercent,
        tdsRatePercent: tdsRatePercent,
      ),
      parse: (d) => RentBranch.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Re-saves [b] unchanged except for the GST preference + lock (the "Apply GST?" prompt).
  Future<RentBranch> saveGstPreference(RentBranch b, {required bool apply, required DateTime lockedUntil}) =>
      updateBranch(
        b.id,
        branchName: b.branchName,
        branchCode: b.branchCode,
        ownerName: b.ownerName,
        address: b.address,
        rent: b.rent,
        rentAdvance: b.rentAdvance,
        startDate: b.startDate,
        gstApplicable: apply,
        active: b.active,
        orgBranchId: b.orgBranchId,
        gstLockedUntil: lockedUntil,
        gstRatePercent: b.gstRatePercent,
        tdsRatePercent: b.tdsRatePercent,
      );

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
    int? orgBranchId,
    DateTime? gstLockedUntil,
    double? gstRatePercent,
    double? tdsRatePercent,
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
        'orgBranchId': orgBranchId,
        'gstLockedUntil': gstLockedUntil == null ? null : _isoDate(gstLockedUntil),
        'gstRatePercent': gstRatePercent,
        'tdsRatePercent': tdsRatePercent,
      };

  // ── GST / TDS rate options ───────────────────────────────────────────────

  RentRateOptions _rates(dynamic d) => RentRateOptions.fromJson(d as Map<String, dynamic>);

  Future<RentRateOptions> getRateOptions() =>
      _api.get<RentRateOptions>('$_base/branches/rate-options', parse: _rates);

  Future<RentRateOptions> addRateOption(String type, double value) => _api.post<RentRateOptions>(
      '$_base/branches/rate-options',
      body: {'type': type, 'value': value},
      parse: _rates);

  Future<RentRateOptions> editRateOption(String type, double oldValue, double newValue) =>
      _api.put<RentRateOptions>('$_base/branches/rate-options',
          body: {'type': type, 'oldValue': oldValue, 'newValue': newValue}, parse: _rates);

  Future<RentRateOptions> deleteRateOption(String type, double value) async {
    final res = await _api.raw.delete('$_base/branches/rate-options', queryParameters: {'type': type, 'value': value});
    final data = res.data;
    return _rates(data is Map ? data['data'] : data);
  }

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

  /// Styled Excel of utility bills for a date range — the server limits it to what the caller may see.
  Future<Uint8List> downloadUtilityReport(String from, String to) =>
      _api.getBytes('$_base/utility-bills/export', query: {'from': from, 'to': to});

  /// Styled Excel of rent payable for a month (`yyyy-MM-01`).
  Future<Uint8List> downloadPayableReport(String period) =>
      _api.getBytes('$_base/payable/export', query: {'period': period});

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
    DateTime? periodEnd,
    int? documentAssetId,
  }) {
    return _api.post<RentUtilityBill>(
      '$_base/utility-bills',
      body: {
        'branchId': branchId,
        'period': period,
        'periodEnd': periodEnd == null ? null : _isoDate(periodEnd),
        'documentAssetId': documentAssetId,
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

  Future<RentUtilityBill> approveUtilityBill(int id) => _api.post<RentUtilityBill>(
        '$_base/utility-bills/$id/approve',
        parse: (d) => RentUtilityBill.fromJson(d as Map<String, dynamic>),
      );

  Future<RentUtilityBill> rejectUtilityBill(int id, String reason) => _api.post<RentUtilityBill>(
        '$_base/utility-bills/$id/reject',
        body: {'reason': reason},
        parse: (d) => RentUtilityBill.fromJson(d as Map<String, dynamic>),
      );

  Future<RentUtilityBill> markUtilityBillUnpaid(int id) => _api.post<RentUtilityBill>(
        '$_base/utility-bills/$id/mark-unpaid',
        parse: (d) => RentUtilityBill.fromJson(d as Map<String, dynamic>),
      );

  Future<void> deleteUtilityBill(int id) => _api.raw.delete('$_base/utility-bills/$id');

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
