// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — repository + Riverpod providers.
//
//  All calls go through the shared ApiClient (relative paths only; the base URL
//  comes from Env.apiBaseUrl). ApiClient.get/post/put already unwrap the
//  ApiResponse envelope and return `.data`, so `parse` receives the inner
//  payload directly. The photo-proof upload uses the raw Dio + FormData pattern
//  copied from ProfileRepository.uploadPhoto. DELETE has no typed helper on
//  ApiClient, so we go through raw Dio and map errors to ApiException.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'audit_models.dart';

/// Filter for the audit-plans listing. `auditorId` set ⇒ "My Audits".
class AuditPlansQuery {
  final String? status;
  final int? branchId;
  final int? auditorId;
  final String? from;
  final String? to;
  final String? q;
  final int page;
  final int size;

  const AuditPlansQuery({
    this.status,
    this.branchId,
    this.auditorId,
    this.from,
    this.to,
    this.q,
    this.page = 0,
    this.size = 20,
  });

  Map<String, dynamic> get query => {
        if (status != null && status!.isNotEmpty) 'status': status,
        if (branchId != null) 'branchId': branchId,
        if (auditorId != null) 'auditorId': auditorId,
        if (from != null && from!.isNotEmpty) 'from': from,
        if (to != null && to!.isNotEmpty) 'to': to,
        if (q != null && q!.trim().isNotEmpty) 'q': q!.trim(),
        'page': page,
        'size': size,
      };

  AuditPlansQuery copyWith({String? status, int? page, String? q}) =>
      AuditPlansQuery(
        status: status ?? this.status,
        branchId: branchId,
        auditorId: auditorId,
        from: from,
        to: to,
        q: q ?? this.q,
        page: page ?? this.page,
        size: size,
      );

  @override
  bool operator ==(Object other) =>
      other is AuditPlansQuery &&
      other.status == status &&
      other.branchId == branchId &&
      other.auditorId == auditorId &&
      other.from == from &&
      other.to == to &&
      other.q == q &&
      other.page == page &&
      other.size == size;

  @override
  int get hashCode =>
      Object.hash(status, branchId, auditorId, from, to, q, page, size);
}

/// Filter for the findings listing.
class AuditFindingsQuery {
  final String? status;
  final String? severity;
  final int? branchId;
  final bool? overdue;
  final int page;
  final int size;

  const AuditFindingsQuery({
    this.status,
    this.severity,
    this.branchId,
    this.overdue,
    this.page = 0,
    this.size = 20,
  });

  Map<String, dynamic> get query => {
        if (status != null && status!.isNotEmpty) 'status': status,
        if (severity != null && severity!.isNotEmpty) 'severity': severity,
        if (branchId != null) 'branchId': branchId,
        if (overdue != null) 'overdue': overdue,
        'page': page,
        'size': size,
      };

  @override
  bool operator ==(Object other) =>
      other is AuditFindingsQuery &&
      other.status == status &&
      other.severity == severity &&
      other.branchId == branchId &&
      other.overdue == overdue &&
      other.page == page &&
      other.size == size;

  @override
  int get hashCode =>
      Object.hash(status, severity, branchId, overdue, page, size);
}

class AuditRepository {
  AuditRepository(this._api);
  final ApiClient _api;

  // ── Plans ──────────────────────────────────────────────────────────────────

  Future<AuditPage<AuditPlan>> plans(AuditPlansQuery q) {
    return _api.get<AuditPage<AuditPlan>>(
      '/api/audit/plans',
      query: q.query,
      parse: (d) => AuditPage.fromJson(
          d as Map<String, dynamic>, AuditPlan.fromJson),
    );
  }

  Future<AuditPlan> plan(int id) {
    return _api.get<AuditPlan>(
      '/api/audit/plans/$id',
      parse: (d) => AuditPlan.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<AuditPlan> _planAction(String path, {Map<String, dynamic>? query}) {
    return _api.post<AuditPlan>(
      path,
      query: query,
      parse: (d) => AuditPlan.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<AuditPlan> startPlan(int id) =>
      _planAction('/api/audit/plans/$id/start');

  Future<AuditPlan> sendToBm(int id) =>
      _planAction('/api/audit/plans/$id/send-to-bm');

  Future<AuditPlan> bmSubmit(int id) =>
      _planAction('/api/audit/plans/$id/bm-submit');

  Future<AuditPlan> closePlan(int id) =>
      _planAction('/api/audit/plans/$id/close');

  Future<AuditPlan> reopenPlan(int id, String reason) =>
      _planAction('/api/audit/plans/$id/reopen', query: {'reason': reason});

  Future<AuditPlan> cancelPlan(int id, String reason) =>
      _planAction('/api/audit/plans/$id/cancel', query: {'reason': reason});

  // ── Execution ────────────────────────────────────────────────────────────────

  Future<AuditExecutionDetail> execution(int execId) {
    return _api.get<AuditExecutionDetail>(
      '/api/audit/executions/$execId',
      parse: (d) => AuditExecutionDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Saves question responses; returns the recomputed execution detail.
  Future<AuditExecutionDetail> saveResponses(
    int execId,
    List<Map<String, dynamic>> responses,
  ) {
    return _api.put<AuditExecutionDetail>(
      '/api/audit/executions/$execId/responses',
      body: {'responses': responses},
      parse: (d) => AuditExecutionDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> saveRating(int execId, Map<String, dynamic> body) async {
    await _api.put<dynamic>(
      '/api/audit/executions/$execId/rating',
      body: body,
      parse: (d) => d,
    );
  }

  Future<void> saveExecutiveSummary(int execId, Map<String, dynamic> body) async {
    await _api.post<dynamic>(
      '/api/audit/executions/$execId/executive-summary',
      body: body,
      parse: (d) => d,
    );
  }

  /// Pre-submit validation (pending mandatory questions / observations / attachments + completion).
  Future<AuditValidation> validate(int execId) {
    return _api.get<AuditValidation>(
      '/api/audit/executions/$execId/validate',
      parse: (d) => AuditValidation.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<AuditExecutionDetail> submitAudit(int execId) {
    return _api.post<AuditExecutionDetail>(
      '/api/audit/executions/$execId/submit',
      parse: (d) => AuditExecutionDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  // ── Annexures ────────────────────────────────────────────────────────────────

  Future<List<AuditCenterVisit>> centerVisits(int execId) =>
      _annexureList(execId, 'center', AuditCenterVisit.fromJson);

  Future<List<AuditClientVisit>> clientVisits(int execId) =>
      _annexureList(execId, 'client', AuditClientVisit.fromJson);

  Future<List<AuditOdVisit>> odVisits(int execId) =>
      _annexureList(execId, 'od', AuditOdVisit.fromJson);

  Future<List<AuditBranchAnnexure>> branchAnnexures(int execId) =>
      _annexureList(execId, 'branch', AuditBranchAnnexure.fromJson);

  Future<List<T>> _annexureList<T>(
    int execId,
    String type,
    T Function(Map<String, dynamic>) item,
  ) {
    return _api.get<List<T>>(
      '/api/audit/executions/$execId/annexures/$type',
      parse: (d) => (d is List ? d : const [])
          .whereType<Map<String, dynamic>>()
          .map(item)
          .toList(),
    );
  }

  Future<void> addAnnexure(
    int execId,
    String type,
    Map<String, dynamic> body,
  ) async {
    await _api.post<dynamic>(
      '/api/audit/executions/$execId/annexures/$type',
      body: body,
      parse: (d) => d,
    );
  }

  Future<void> deleteAnnexure(int execId, String type, int id) async {
    try {
      await _api.raw.delete<dynamic>(
        '/api/audit/executions/$execId/annexures/$type/$id',
      );
    } on DioException catch (e) {
      throw _mapDeleteError(e);
    }
  }

  // ── Findings ─────────────────────────────────────────────────────────────────

  Future<AuditPage<AuditFinding>> findings(AuditFindingsQuery q) {
    return _api.get<AuditPage<AuditFinding>>(
      '/api/audit/findings',
      query: q.query,
      parse: (d) =>
          AuditPage.fromJson(d as Map<String, dynamic>, AuditFinding.fromJson),
    );
  }

  Future<List<AuditFinding>> findingsForExecution(int execId) {
    return _api.get<List<AuditFinding>>(
      '/api/audit/findings/execution/$execId',
      parse: (d) => (d is List ? d : const [])
          .whereType<Map<String, dynamic>>()
          .map(AuditFinding.fromJson)
          .toList(),
    );
  }

  Future<AuditFindingDetail> findingDetail(int id) {
    return _api.get<AuditFindingDetail>(
      '/api/audit/findings/$id',
      parse: (d) => AuditFindingDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> submitCapa(int id, Map<String, dynamic> body) async {
    await _api.post<dynamic>(
      '/api/audit/findings/$id/capa',
      body: body,
      parse: (d) => d,
    );
  }

  Future<void> verifyFinding(int id, Map<String, dynamic> body) async {
    await _api.post<dynamic>(
      '/api/audit/findings/$id/verify',
      body: body,
      parse: (d) => d,
    );
  }

  // ── Attachments (photo proof) ────────────────────────────────────────────────

  /// Uploads a photo proof. Mirrors ProfileRepository.uploadPhoto: posts the
  /// FormData via raw Dio and reads the `data` payload out of the envelope.
  Future<AuditAttachment?> uploadProof(FormData form) async {
    final res = await _api.raw.post<Map<String, dynamic>>(
      '/api/audit/attachments',
      data: form,
    );
    final data = res.data?['data'];
    return data is Map<String, dynamic>
        ? AuditAttachment.fromJson(data)
        : null;
  }

  Future<List<AuditAttachment>> attachments(String parentType, int parentId) {
    return _api.get<List<AuditAttachment>>(
      '/api/audit/attachments',
      query: {'parentType': parentType, 'parentId': parentId},
      parse: (d) => (d is List ? d : const [])
          .whereType<Map<String, dynamic>>()
          .map(AuditAttachment.fromJson)
          .toList(),
    );
  }

  ApiException _mapDeleteError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return ApiException(data['message'] as String,
          statusCode: e.response?.statusCode);
    }
    return ApiException(
      'Could not delete (HTTP ${e.response?.statusCode ?? '?'})',
      statusCode: e.response?.statusCode,
    );
  }
}

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => AuditRepository(ref.watch(apiClientProvider)),
);

/// A page of audit plans for the given filter (drives "My Audits").
final myAuditsProvider =
    FutureProvider.autoDispose.family<AuditPage<AuditPlan>, AuditPlansQuery>(
  (ref, q) => ref.watch(auditRepositoryProvider).plans(q),
);

/// A single audit plan.
final auditPlanProvider =
    FutureProvider.autoDispose.family<AuditPlan, int>(
  (ref, id) => ref.watch(auditRepositoryProvider).plan(id),
);

/// An execution's full detail (categories + score summary).
final auditExecutionProvider =
    FutureProvider.autoDispose.family<AuditExecutionDetail, int>(
  (ref, execId) => ref.watch(auditRepositoryProvider).execution(execId),
);

/// Pre-submit validation for an execution (drives submit gating + pending list).
final auditValidationProvider =
    FutureProvider.autoDispose.family<AuditValidation, int>(
  (ref, execId) => ref.watch(auditRepositoryProvider).validate(execId),
);

/// Findings raised for a specific execution.
final findingsForExecutionProvider =
    FutureProvider.autoDispose.family<List<AuditFinding>, int>(
  (ref, execId) =>
      ref.watch(auditRepositoryProvider).findingsForExecution(execId),
);

/// A page of findings for the given filter (assigned / branch view).
final findingsProvider =
    FutureProvider.autoDispose.family<AuditPage<AuditFinding>, AuditFindingsQuery>(
  (ref, q) => ref.watch(auditRepositoryProvider).findings(q),
);

/// A single finding's detail (+ CAPA history + verifications).
final findingDetailProvider =
    FutureProvider.autoDispose.family<AuditFindingDetail, int>(
  (ref, id) => ref.watch(auditRepositoryProvider).findingDetail(id),
);
