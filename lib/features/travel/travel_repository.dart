import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'travel_models.dart';

final travelRepositoryProvider =
    Provider((ref) => TravelRepository(ref.watch(apiClientProvider)));

/// Server-driven expense-category options for claim forms (never errors —
/// falls back to the built-in category list).
final travelExpenseCategoriesProvider =
    FutureProvider.autoDispose<List<TravelCategoryOption>>(
        (ref) => ref.watch(travelRepositoryProvider).expenseCategories());

typedef TravelProgressCb = void Function(int sent, int total);

/// Pulls the `content` list out of a paged `ApiResponse<PageResponse<T>>` `data`
/// payload, tolerating a bare list for forward-compatibility.
List<Map<String, dynamic>> _pageContent(dynamic d) {
  if (d is List) return d.cast<Map<String, dynamic>>();
  final content = (d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
  return content.cast<Map<String, dynamic>>();
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Travel Management API client — typed wrappers over `/api/travel/**`
/// (plans, claims + the approval state-machine, policies, and reports). All
/// requests carry the JWT + `X-Device-Type: MOBILE` via the shared [ApiClient]
/// interceptor; server-side RBAC + owner/scope checks gate every call.
class TravelRepository {
  TravelRepository(this._api);
  final ApiClient _api;

  static const _plans = '/api/travel/plans';
  static const _claims = '/api/travel/claims';
  static const _policies = '/api/travel/policies';
  static const _reports = '/api/travel/reports';

  // ════════════════════════════════════════════════════════════════════════
  //  TRAVEL PLANS
  // ════════════════════════════════════════════════════════════════════════

  /// Create a self travel plan (no approval). [travelMode] is a `TravelMode`
  /// constant (see [TravelEnums.travelModes]).
  Future<TravelPlan> createPlan({
    required String title,
    required String destination,
    String? fromLocation,
    String? purpose,
    String? travelMode,
    DateTime? startDate,
    DateTime? endDate,
    double? estimatedCost,
  }) {
    return _api.post<TravelPlan>(
      _plans,
      body: _planBody(
        title: title,
        destination: destination,
        fromLocation: fromLocation,
        purpose: purpose,
        travelMode: travelMode,
        startDate: startDate,
        endDate: endDate,
        estimatedCost: estimatedCost,
      ),
      parse: (d) => TravelPlan.fromJson(d as Map<String, dynamic>),
    );
  }

  /// The caller's own plans, optionally filtered by `TravelPlanStatus`.
  Future<List<TravelPlan>> myPlans({String? status, int page = 0, int size = 20}) {
    return _api.get<List<TravelPlan>>(
      '$_plans/my',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(TravelPlan.fromJson).toList(),
    );
  }

  /// Scoped listing (branch + reportee-hierarchy for managers, full for admin).
  Future<List<TravelPlan>> listPlans({
    String? q,
    String? status,
    int page = 0,
    int size = 20,
  }) {
    return _api.get<List<TravelPlan>>(
      _plans,
      query: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(TravelPlan.fromJson).toList(),
    );
  }

  Future<TravelPlan> getPlan(int id) {
    return _api.get<TravelPlan>(
      '$_plans/$id',
      parse: (d) => TravelPlan.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Active travel-plan title options (Settings → Lookups → Travel plan titles).
  Future<List<String>> planTitles() {
    return _api.get<List<String>>(
      '/api/lookups/travel-plan-titles',
      query: {'activeOnly': true},
      parse: (d) => (d as List)
          .map((e) => (e as Map<String, dynamic>)['label'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  /// Active expense-category options (Settings → Lookups → Travel expense
  /// categories). The backend dropped the `TravelExpenseCategory` enum — the
  /// list is DB-driven and companies can add their own codes. Falls back to
  /// the legacy built-in list when offline / the lookup is empty.
  Future<List<TravelCategoryOption>> expenseCategories() async {
    try {
      final list = await _api.get<List<TravelCategoryOption>>(
        '/api/lookups/travel-expense-categories',
        query: {'activeOnly': true},
        parse: (d) => (d as List)
            .map((e) => TravelCategoryOption.fromJson(e as Map<String, dynamic>))
            .where((o) => o.code.isNotEmpty)
            .toList(),
      );
      if (list.isNotEmpty) return list;
    } catch (_) {
      // Fall through to the static defaults below.
    }
    return TravelEnums.expenseCategories
        .map((c) => TravelCategoryOption(code: c, label: TravelEnums.label(c)))
        .toList();
  }

  Future<TravelPlan> updatePlan(
    int id, {
    required String title,
    required String destination,
    String? fromLocation,
    String? purpose,
    String? travelMode,
    DateTime? startDate,
    DateTime? endDate,
    double? estimatedCost,
  }) {
    return _api.put<TravelPlan>(
      '$_plans/$id',
      body: _planBody(
        title: title,
        destination: destination,
        fromLocation: fromLocation,
        purpose: purpose,
        travelMode: travelMode,
        startDate: startDate,
        endDate: endDate,
        estimatedCost: estimatedCost,
      ),
      parse: (d) => TravelPlan.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Cancel/delete own plan.
  Future<void> deletePlan(int id) {
    return _api.raw.delete('$_plans/$id');
  }

  /// Upload one or more bills/evidence files to the caller's own plan.
  Future<List<TravelAttachment>> uploadPlanAttachments(
    int id,
    List<TravelUploadFile> files, {
    String? caption,
    TravelProgressCb? onProgress,
  }) =>
      _uploadAttachments('$_plans/$id/attachments', files, caption, onProgress);

  Future<List<TravelAttachment>> listPlanAttachments(int id) {
    return _api.get<List<TravelAttachment>>(
      '$_plans/$id/attachments',
      parse: _attachmentList,
    );
  }

  Future<void> deletePlanAttachment(int id, int attachmentId) {
    return _api.raw.delete('$_plans/$id/attachments/$attachmentId');
  }

  // ════════════════════════════════════════════════════════════════════════
  //  TRAVEL CLAIMS — header & expense CRUD
  // ════════════════════════════════════════════════════════════════════════

  /// Create a DRAFT claim, optionally with expense lines. Build each entry with
  /// [expenseRequest].
  Future<TravelClaim> createClaim({
    required String title,
    String? purpose,
    DateTime? fromDate,
    DateTime? toDate,
    int? travelPlanId,
    List<Map<String, dynamic>> expenses = const [],
  }) {
    return _api.post<TravelClaim>(
      _claims,
      body: _claimBody(
        title: title,
        purpose: purpose,
        fromDate: fromDate,
        toDate: toDate,
        travelPlanId: travelPlanId,
        expenses: expenses,
      ),
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  /// The caller's own claims, optionally filtered by `TravelClaimStatus`.
  Future<List<TravelClaimSummary>> myClaims({
    String? status,
    int page = 0,
    int size = 20,
  }) {
    return _api.get<List<TravelClaimSummary>>(
      '$_claims/my',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(TravelClaimSummary.fromJson).toList(),
    );
  }

  /// Scoped team listing (reportee-hierarchy / branch for managers, full for admin).
  Future<List<TravelClaimSummary>> listClaims({
    String? q,
    String? status,
    int page = 0,
    int size = 20,
  }) {
    return _api.get<List<TravelClaimSummary>>(
      _claims,
      query: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(TravelClaimSummary.fromJson).toList(),
    );
  }

  /// Approval inbox: claims whose current PENDING step is assigned to the caller.
  Future<List<TravelClaimSummary>> inbox({int page = 0, int size = 20}) {
    return _api.get<List<TravelClaimSummary>>(
      '$_claims/inbox',
      query: {'page': page, 'size': size},
      parse: (d) => _pageContent(d).map(TravelClaimSummary.fromJson).toList(),
    );
  }

  /// Settlement queue: fully APPROVED claims awaiting settlement.
  Future<List<TravelClaimSummary>> settlementQueue({int page = 0, int size = 20}) {
    return _api.get<List<TravelClaimSummary>>(
      '$_claims/settlement-queue',
      query: {'page': page, 'size': size},
      parse: (d) => _pageContent(d).map(TravelClaimSummary.fromJson).toList(),
    );
  }

  Future<TravelClaim> getClaim(int id) {
    return _api.get<TravelClaim>(
      '$_claims/$id',
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Edit own claim header (DRAFT/SENT_BACK only).
  Future<TravelClaim> updateClaim(
    int id, {
    required String title,
    String? purpose,
    DateTime? fromDate,
    DateTime? toDate,
    int? travelPlanId,
    List<Map<String, dynamic>> expenses = const [],
  }) {
    return _api.put<TravelClaim>(
      '$_claims/$id',
      body: _claimBody(
        title: title,
        purpose: purpose,
        fromDate: fromDate,
        toDate: toDate,
        travelPlanId: travelPlanId,
        expenses: expenses,
      ),
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Delete own DRAFT claim.
  Future<void> deleteClaim(int id) {
    return _api.raw.delete('$_claims/$id');
  }

  /// Add one expense line (owner; DRAFT/SENT_BACK). Returns the refreshed claim.
  Future<TravelClaim> addExpense(
    int id, {
    required String category,
    required double amount,
    DateTime? expenseDate,
    String? description,
  }) {
    return _api.post<TravelClaim>(
      '$_claims/$id/expenses',
      body: expenseRequest(
        category: category,
        amount: amount,
        expenseDate: expenseDate,
        description: description,
      ),
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<TravelClaim> updateExpense(
    int id,
    int expenseId, {
    required String category,
    required double amount,
    DateTime? expenseDate,
    String? description,
  }) {
    return _api.put<TravelClaim>(
      '$_claims/$id/expenses/$expenseId',
      body: expenseRequest(
        category: category,
        amount: amount,
        expenseDate: expenseDate,
        description: description,
      ),
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<TravelClaim> deleteExpense(int id, int expenseId) {
    return _api.raw
        .delete<Map<String, dynamic>>('$_claims/$id/expenses/$expenseId')
        .then((res) => TravelClaim.fromJson(res.data!['data'] as Map<String, dynamic>));
  }

  // ── Claim / expense attachments (bills) ─────────────────────────────────

  /// Upload one or more bills for a specific expense line.
  Future<List<TravelAttachment>> uploadExpenseAttachments(
    int id,
    int expenseId,
    List<TravelUploadFile> files, {
    String? caption,
    TravelProgressCb? onProgress,
  }) =>
      _uploadAttachments(
          '$_claims/$id/expenses/$expenseId/attachments', files, caption, onProgress);

  Future<List<TravelAttachment>> listExpenseAttachments(int id, int expenseId) {
    return _api.get<List<TravelAttachment>>(
      '$_claims/$id/expenses/$expenseId/attachments',
      parse: _attachmentList,
    );
  }

  /// Upload one or more claim-level bills.
  Future<List<TravelAttachment>> uploadClaimAttachments(
    int id,
    List<TravelUploadFile> files, {
    String? caption,
    TravelProgressCb? onProgress,
  }) =>
      _uploadAttachments('$_claims/$id/attachments', files, caption, onProgress);

  Future<List<TravelAttachment>> listClaimAttachments(int id) {
    return _api.get<List<TravelAttachment>>(
      '$_claims/$id/attachments',
      parse: _attachmentList,
    );
  }

  Future<void> deleteClaimAttachment(int id, int attachmentId) {
    return _api.raw.delete('$_claims/$id/attachments/$attachmentId');
  }

  /// Download a bill's bytes (access-checked server-side). Dio transparently
  /// follows the 302 redirect to a presigned URL when S3 storage is used.
  Future<Uint8List> downloadClaimAttachment(int id, int attachmentId) {
    return _api.getBytes('$_claims/$id/attachments/$attachmentId/download');
  }

  // ── Policy-violation evaluation ─────────────────────────────────────────

  /// Limit-vs-claimed evaluation for the owner/approver.
  Future<TravelPolicyEvaluation> evaluation(int id) {
    return _api.get<TravelPolicyEvaluation>(
      '$_claims/$id/evaluation',
      parse: (d) => TravelPolicyEvaluation.fromJson(d as Map<String, dynamic>),
    );
  }

  // ── Approval state machine ──────────────────────────────────────────────

  /// Submit (or resubmit after send-back). [remarks] is mandatory when a policy
  /// violation is present.
  Future<TravelClaim> submit(int id, {String? remarks}) {
    return _api.post<TravelClaim>(
      '$_claims/$id/submit',
      body: {if (remarks != null && remarks.isNotEmpty) 'remarks': remarks},
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Approve the current pending level. [approvedAmounts] optionally overrides
  /// per-expense approved amounts, keyed by expense id.
  Future<TravelClaim> approve(
    int id, {
    String? remarks,
    Map<int, double>? approvedAmounts,
  }) {
    return _api.post<TravelClaim>(
      '$_claims/$id/approve',
      body: {
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        if (approvedAmounts != null && approvedAmounts.isNotEmpty)
          'approvedAmounts':
              approvedAmounts.map((k, v) => MapEntry(k.toString(), v)),
      },
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Reject at the current level (remarks mandatory).
  Future<TravelClaim> reject(int id, {required String remarks}) {
    return _api.post<TravelClaim>(
      '$_claims/$id/reject',
      body: {'remarks': remarks},
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Send back to the employee (remarks mandatory).
  Future<TravelClaim> sendBack(int id, {required String remarks}) {
    return _api.post<TravelClaim>(
      '$_claims/$id/send-back',
      body: {'remarks': remarks},
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Finance/Admin settlement of a fully APPROVED claim. [paymentMode] is a
  /// `TravelPaymentMode` constant (see [TravelEnums.paymentModes]).
  Future<TravelClaim> settle(
    int id, {
    required double settledAmount,
    String? paymentMode,
    String? paymentReference,
    String? remarks,
  }) {
    return _api.post<TravelClaim>(
      '$_claims/$id/settle',
      body: {
        'settledAmount': settledAmount,
        if (paymentMode != null && paymentMode.isNotEmpty) 'paymentMode': paymentMode,
        if (paymentReference != null && paymentReference.isNotEmpty)
          'paymentReference': paymentReference,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      },
      parse: (d) => TravelClaim.fromJson(d as Map<String, dynamic>),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  TRAVEL CLAIM POLICIES
  // ════════════════════════════════════════════════════════════════════════

  Future<List<TravelPolicy>> listPolicies({
    String? q,
    bool? active,
    int page = 0,
    int size = 20,
  }) {
    return _api.get<List<TravelPolicy>>(
      _policies,
      query: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (active != null) 'active': active,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(TravelPolicy.fromJson).toList(),
    );
  }

  Future<TravelPolicy> getPolicy(int id) {
    return _api.get<TravelPolicy>(
      '$_policies/$id',
      parse: (d) => TravelPolicy.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<TravelPolicy> createPolicy({
    required String policyName,
    required int approvalLevels,
    String? description,
    DateTime? effectiveDate,
    bool? active,
    bool? blockOnViolation,
    bool? billMandatory,
    double? billMandatoryThreshold,
    double? maxClaimAmount,
    List<TravelPolicyScope> scopes = const [],
    List<TravelPolicyLimit> limits = const [],
  }) {
    return _api.post<TravelPolicy>(
      _policies,
      body: _policyBody(
        policyName: policyName,
        approvalLevels: approvalLevels,
        description: description,
        effectiveDate: effectiveDate,
        active: active,
        blockOnViolation: blockOnViolation,
        billMandatory: billMandatory,
        billMandatoryThreshold: billMandatoryThreshold,
        maxClaimAmount: maxClaimAmount,
        scopes: scopes,
        limits: limits,
      ),
      parse: (d) => TravelPolicy.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<TravelPolicy> updatePolicy(
    int id, {
    required String policyName,
    required int approvalLevels,
    String? description,
    DateTime? effectiveDate,
    bool? active,
    bool? blockOnViolation,
    bool? billMandatory,
    double? billMandatoryThreshold,
    double? maxClaimAmount,
    List<TravelPolicyScope> scopes = const [],
    List<TravelPolicyLimit> limits = const [],
  }) {
    return _api.put<TravelPolicy>(
      '$_policies/$id',
      body: _policyBody(
        policyName: policyName,
        approvalLevels: approvalLevels,
        description: description,
        effectiveDate: effectiveDate,
        active: active,
        blockOnViolation: blockOnViolation,
        billMandatory: billMandatory,
        billMandatoryThreshold: billMandatoryThreshold,
        maxClaimAmount: maxClaimAmount,
        scopes: scopes,
        limits: limits,
      ),
      parse: (d) => TravelPolicy.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> deletePolicy(int id) {
    return _api.raw.delete('$_policies/$id');
  }

  /// Resolve the single most-specific applicable policy for the current employee
  /// (UI preview before raising a claim).
  Future<TravelPolicy> resolvePolicy({DateTime? asOfDate}) {
    return _api.get<TravelPolicy>(
      '$_policies/resolve',
      query: {if (asOfDate != null) 'asOfDate': _isoDate(asOfDate)},
      parse: (d) => TravelPolicy.fromJson(d as Map<String, dynamic>),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  TRAVEL REPORTS
  // ════════════════════════════════════════════════════════════════════════

  /// Tabular claim status report (JSON). All filters optional.
  Future<TravelReportTable> claimReport({
    DateTime? from,
    DateTime? to,
    String? status,
    int? branchId,
    int? areaId,
    int? divisionId,
    int? departmentId,
    String? department,
    int? employeeId,
  }) {
    return _api.get<TravelReportTable>(
      '$_reports/claims',
      query: _reportQuery(
        from: from,
        to: to,
        status: status,
        branchId: branchId,
        areaId: areaId,
        divisionId: divisionId,
        departmentId: departmentId,
        department: department,
        employeeId: employeeId,
      ),
      parse: (d) => TravelReportTable.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Excel (.xlsx) bytes: claim status report.
  Future<Uint8List> exportClaimReport({
    DateTime? from,
    DateTime? to,
    String? status,
    int? branchId,
    int? areaId,
    int? divisionId,
    int? departmentId,
    String? department,
    int? employeeId,
  }) =>
      _api.getBytes('$_reports/claims/export',
          query: _reportQuery(
            from: from,
            to: to,
            status: status,
            branchId: branchId,
            areaId: areaId,
            divisionId: divisionId,
            departmentId: departmentId,
            department: department,
            employeeId: employeeId,
          ));

  /// Excel (.xlsx) bytes: employee-wise expense report.
  Future<Uint8List> exportEmployeeWise({
    DateTime? from,
    DateTime? to,
    String? status,
    int? branchId,
    int? areaId,
    int? divisionId,
    int? departmentId,
    String? department,
    int? employeeId,
  }) =>
      _api.getBytes('$_reports/employee-wise/export',
          query: _reportQuery(
            from: from,
            to: to,
            status: status,
            branchId: branchId,
            areaId: areaId,
            divisionId: divisionId,
            departmentId: departmentId,
            department: department,
            employeeId: employeeId,
          ));

  /// Excel (.xlsx) bytes: department-wise expense report.
  Future<Uint8List> exportDepartmentWise({
    DateTime? from,
    DateTime? to,
    String? status,
    int? branchId,
    int? areaId,
    int? divisionId,
    int? departmentId,
    String? department,
    int? employeeId,
  }) =>
      _api.getBytes('$_reports/department-wise/export',
          query: _reportQuery(
            from: from,
            to: to,
            status: status,
            branchId: branchId,
            areaId: areaId,
            divisionId: divisionId,
            departmentId: departmentId,
            department: department,
            employeeId: employeeId,
          ));

  /// Excel (.xlsx) bytes: branch-wise expense report.
  Future<Uint8List> exportBranchWise({
    DateTime? from,
    DateTime? to,
    String? status,
    int? branchId,
    int? areaId,
    int? divisionId,
    int? departmentId,
    String? department,
    int? employeeId,
  }) =>
      _api.getBytes('$_reports/branch-wise/export',
          query: _reportQuery(
            from: from,
            to: to,
            status: status,
            branchId: branchId,
            areaId: areaId,
            divisionId: divisionId,
            departmentId: departmentId,
            department: department,
            employeeId: employeeId,
          ));

  /// Excel (.xlsx) bytes: policy-violation report.
  Future<Uint8List> exportPolicyViolations({
    DateTime? from,
    DateTime? to,
    String? status,
    int? branchId,
    int? areaId,
    int? divisionId,
    int? departmentId,
    String? department,
    int? employeeId,
  }) =>
      _api.getBytes('$_reports/policy-violations/export',
          query: _reportQuery(
            from: from,
            to: to,
            status: status,
            branchId: branchId,
            areaId: areaId,
            divisionId: divisionId,
            departmentId: departmentId,
            department: department,
            employeeId: employeeId,
          ));

  // ════════════════════════════════════════════════════════════════════════
  //  Request-body / payload builders
  // ════════════════════════════════════════════════════════════════════════

  /// Build one `TravelClaimExpenseRequest` entry for [createClaim]/[updateClaim].
  static Map<String, dynamic> expenseRequest({
    required String category,
    required double amount,
    DateTime? expenseDate,
    String? description,
  }) =>
      {
        'category': category,
        'amount': amount,
        if (expenseDate != null) 'expenseDate': _isoDate(expenseDate),
        if (description != null && description.isNotEmpty) 'description': description,
      };

  Map<String, dynamic> _planBody({
    required String title,
    required String destination,
    String? fromLocation,
    String? purpose,
    String? travelMode,
    DateTime? startDate,
    DateTime? endDate,
    double? estimatedCost,
  }) =>
      {
        'title': title,
        'destination': destination,
        if (fromLocation != null && fromLocation.isNotEmpty) 'fromLocation': fromLocation,
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
        if (travelMode != null && travelMode.isNotEmpty) 'travelMode': travelMode,
        if (startDate != null) 'startDate': _isoDate(startDate),
        if (endDate != null) 'endDate': _isoDate(endDate),
        if (estimatedCost != null) 'estimatedCost': estimatedCost,
      };

  Map<String, dynamic> _claimBody({
    required String title,
    String? purpose,
    DateTime? fromDate,
    DateTime? toDate,
    int? travelPlanId,
    List<Map<String, dynamic>> expenses = const [],
  }) =>
      {
        'title': title,
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
        if (fromDate != null) 'fromDate': _isoDate(fromDate),
        if (toDate != null) 'toDate': _isoDate(toDate),
        if (travelPlanId != null) 'travelPlanId': travelPlanId,
        if (expenses.isNotEmpty) 'expenses': expenses,
      };

  Map<String, dynamic> _policyBody({
    required String policyName,
    required int approvalLevels,
    String? description,
    DateTime? effectiveDate,
    bool? active,
    bool? blockOnViolation,
    bool? billMandatory,
    double? billMandatoryThreshold,
    double? maxClaimAmount,
    List<TravelPolicyScope> scopes = const [],
    List<TravelPolicyLimit> limits = const [],
  }) =>
      {
        'policyName': policyName,
        'approvalLevels': approvalLevels,
        if (description != null) 'description': description,
        if (effectiveDate != null) 'effectiveDate': _isoDate(effectiveDate),
        if (active != null) 'active': active,
        if (blockOnViolation != null) 'blockOnViolation': blockOnViolation,
        if (billMandatory != null) 'billMandatory': billMandatory,
        if (billMandatoryThreshold != null)
          'billMandatoryThreshold': billMandatoryThreshold,
        if (maxClaimAmount != null) 'maxClaimAmount': maxClaimAmount,
        'scopes': scopes.map((s) => s.toJson()).toList(),
        'limits': limits.map((l) => l.toJson()).toList(),
      };

  Map<String, dynamic> _reportQuery({
    DateTime? from,
    DateTime? to,
    String? status,
    int? branchId,
    int? areaId,
    int? divisionId,
    int? departmentId,
    String? department,
    int? employeeId,
  }) =>
      {
        if (from != null) 'from': _isoDate(from),
        if (to != null) 'to': _isoDate(to),
        if (status != null && status.isNotEmpty) 'status': status,
        if (branchId != null) 'branchId': branchId,
        if (areaId != null) 'areaId': areaId,
        if (divisionId != null) 'divisionId': divisionId,
        if (departmentId != null) 'departmentId': departmentId,
        if (department != null && department.isNotEmpty) 'department': department,
        if (employeeId != null) 'employeeId': employeeId,
      };

  // ── Shared multipart upload (param name `files`, optional `caption`) ─────

  Future<List<TravelAttachment>> _uploadAttachments(
    String path,
    List<TravelUploadFile> files,
    String? caption,
    TravelProgressCb? onProgress,
  ) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(
          f.path,
          filename: f.fileName,
          contentType: DioMediaType.parse(f.mime),
        ),
      ));
    }
    if (caption != null && caption.trim().isNotEmpty) {
      form.fields.add(MapEntry('caption', caption.trim()));
    }
    final res = await _api.raw.post<Map<String, dynamic>>(
      path,
      data: form,
      onSendProgress: (sent, total) => onProgress?.call(sent, total),
    );
    return ((res.data!['data'] as List?) ?? const [])
        .map((e) => TravelAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<TravelAttachment> _attachmentList(dynamic d) =>
      ((d as List?) ?? const [])
          .map((e) => TravelAttachment.fromJson(e as Map<String, dynamic>))
          .toList();
}
