// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — typed API client for `/api/np` (mirrors web `src/api/np.ts`).
//
//  Every mutating call returns the refreshed [NpCandidateDetail] so the detail
//  screen can swap state in one hop. Server-side RBAC + NpScopeService gate
//  every call; the UI only renders actions listed in `allowedActions`.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'np_models.dart';

final npRepositoryProvider = Provider<NpRepository>((ref) => NpRepository(ref.watch(apiClientProvider)));

/// Server configuration (eligibility criteria, orientation items, document
/// types, BGV checklist, feature toggles). Never throws — falls back to empty.
final npConfigProvider = FutureProvider<NpConfig>((ref) async {
  try {
    return await ref.watch(npRepositoryProvider).config();
  } catch (_) {
    return NpConfig.empty;
  }
});

class NpListFilter {
  final String q;
  final List<String> statuses;
  final int? branchId;
  const NpListFilter({this.q = '', this.statuses = const [], this.branchId});

  NpListFilter copyWith({String? q, List<String>? statuses, int? branchId, bool clearBranch = false}) => NpListFilter(
        q: q ?? this.q,
        statuses: statuses ?? this.statuses,
        branchId: clearBranch ? null : (branchId ?? this.branchId),
      );

  Map<String, dynamic> toQuery() => {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (statuses.isNotEmpty) 'status': statuses.join(','),
        if (branchId != null) 'branchId': branchId,
      };

  @override
  bool operator ==(Object other) =>
      other is NpListFilter && other.q == q && other.branchId == branchId && other.statuses.join(',') == statuses.join(',');
  @override
  int get hashCode => Object.hash(q, branchId, statuses.join(','));
}

class NpPage {
  final List<NpCandidateSummary> content;
  final int page;
  final int totalPages;
  final int totalElements;
  const NpPage({required this.content, required this.page, required this.totalPages, required this.totalElements});
  bool get hasMore => page + 1 < totalPages;
}

final npDashboardProvider = FutureProvider.autoDispose.family<NpDashboard, NpListFilter>(
    (ref, f) => ref.watch(npRepositoryProvider).dashboard(f));

final npCandidateDetailProvider = FutureProvider.autoDispose.family<NpCandidateDetail, int>(
    (ref, id) => ref.watch(npRepositoryProvider).candidate(id));

class NpRepository {
  NpRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/np';

  NpCandidateDetail _detail(dynamic d) => NpCandidateDetail.fromJson(d as Map<String, dynamic>);

  // ── config / dashboard ──

  Future<NpConfig> config() =>
      _api.get<NpConfig>('$_base/config', parse: (d) => NpConfig.fromJson(d as Map<String, dynamic>));

  Future<NpDashboard> dashboard(NpListFilter f) => _api.get<NpDashboard>(
        '$_base/dashboard',
        query: f.toQuery()..remove('status'),
        parse: (d) => NpDashboard.fromJson(d as Map<String, dynamic>),
      );

  // ── candidates ──

  Future<NpPage> list(NpListFilter f, {int page = 0, int size = 20}) => _api.get<NpPage>(
        '$_base/candidates',
        query: {...f.toQuery(), 'page': page, 'size': size, 'sort': 'updatedAt,desc'},
        parse: (d) {
          final m = d as Map<String, dynamic>;
          final content = (m['content'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(NpCandidateSummary.fromJson)
              .toList();
          return NpPage(
            content: content,
            page: (m['number'] as num?)?.toInt() ?? page,
            totalPages: (m['totalPages'] as num?)?.toInt() ?? 1,
            totalElements: (m['totalElements'] as num?)?.toInt() ?? content.length,
          );
        },
      );

  Future<NpCandidateDetail> candidate(int id) => _api.get('$_base/candidates/$id', parse: _detail);

  Future<NpCandidateDetail> create(NpCandidateInput input) =>
      _api.post('$_base/candidates', body: input.toJson(), parse: _detail);

  Future<NpCandidateDetail> update(int id, NpCandidateInput input) =>
      _api.put('$_base/candidates/$id', body: input.toJson(), parse: _detail);

  Future<void> delete(int id) async {
    try {
      await _api.raw.delete('$_base/candidates/$id');
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Aadhaar pre-fill (DigiLocker e-KYC) + bank verify ──

  Future<NpAadhaarLink> startAadhaarLink(String aadhaarNumber) => _api.post(
        '$_base/aadhaar/link',
        body: {'aadhaarNumber': aadhaarNumber},
        parse: (d) => NpAadhaarLink.fromJson(d as Map<String, dynamic>),
      );

  Future<NpAadhaarDetails> fetchAadhaarDetails(String referenceId, String transactionId) => _api.post(
        '$_base/aadhaar/details',
        body: {'referenceId': referenceId, 'transactionId': transactionId},
        parse: (d) => NpAadhaarDetails.fromJson(d as Map<String, dynamic>),
      );

  Future<NpBankVerify> verifyBank(String accountNumber, String ifsc) => _api.post(
        '$_base/aadhaar/bank-verify',
        body: {'accountNumber': accountNumber, 'ifsc': ifsc},
        parse: (d) => NpBankVerify.fromJson(d as Map<String, dynamic>),
      );

  // ── workflow: identification → orientation → interview ──

  Future<NpCandidateDetail> identify(int id, {String? remarks}) =>
      _api.post('$_base/candidates/$id/identify', body: {'remarks': remarks}, parse: _detail);

  Future<NpCandidateDetail> orientation(int id,
          {required String orientationDate, required Map<String, bool> items, String? remarks}) =>
      _api.post(
        '$_base/candidates/$id/orientation',
        body: {'orientationDate': orientationDate, 'items': items, 'remarks': remarks},
        parse: _detail,
      );

  Future<NpCandidateDetail> interview(int id,
          {required String interviewDate, int? interviewerId, required String result, String? remarks}) =>
      _api.post(
        '$_base/candidates/$id/interview',
        body: {
          'interviewDate': interviewDate,
          'interviewerId': interviewerId,
          'scores': <String, int>{},
          'result': result,
          'remarks': remarks,
        },
        parse: _detail,
      );

  // ── documents ──

  Future<NpDocument> uploadDocument(
    int candidateId, {
    required String filePath,
    String? fileName,
    required String docType,
    String? documentNumber,
    String? caption,
    double? latitude,
    double? longitude,
    DateTime? capturedAt,
    String? parentType,
    int? parentId,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'docType': docType,
      if (documentNumber != null && documentNumber.trim().isNotEmpty) 'documentNumber': documentNumber.trim(),
      if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (capturedAt != null) 'capturedAt': npIsoDateTime(capturedAt),
      if (parentType != null) 'parentType': parentType,
      if (parentId != null) 'parentId': parentId,
    });
    try {
      final res = await _api.raw.post<Map<String, dynamic>>('$_base/candidates/$candidateId/documents', data: form);
      return NpDocument.fromJson(res.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> deleteDocument(int candidateId, int docId) async {
    try {
      await _api.raw.delete('$_base/candidates/$candidateId/documents/$docId');
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<NpCandidateDetail> submitDocuments(int id) =>
      _api.post('$_base/candidates/$id/documents/submit', body: const {}, parse: _detail);

  Future<NpDocument> verifyDocument(int candidateId, int docId) => _api.post(
        '$_base/candidates/$candidateId/documents/$docId/verify',
        body: const {},
        parse: (d) => NpDocument.fromJson(d as Map<String, dynamic>),
      );

  // ── CB check ──

  Future<NpCandidateDetail> submitCbCheck(int id) =>
      _api.post('$_base/candidates/$id/cb-check', body: const {}, parse: _detail);

  Future<NpCandidateDetail> recordCbResult(int id,
          {required String status, String? referenceNo, String? score, String? remarks}) =>
      _api.post(
        '$_base/candidates/$id/cb-check/result',
        body: {'status': status, 'referenceNo': referenceNo, 'score': score, 'remarks': remarks},
        parse: _detail,
      );

  // ── BGV ──

  /// Creates the draft on first call, updates it when [reportId] is supplied.
  Future<NpBgvReport> saveBgvDraft(int id, NpBgvDraftInput input, {int? reportId}) => _api.post(
        '$_base/candidates/$id/bgv/draft',
        body: input.toJson(),
        query: reportId == null ? null : {'reportId': reportId},
        parse: (d) => NpBgvReport.fromJson(d as Map<String, dynamic>),
      );

  Future<NpCandidateDetail> submitBgv(int id, int reportId) =>
      _api.post('$_base/candidates/$id/bgv/$reportId/submit', body: const {}, parse: _detail);

  Future<NpCandidateDetail> rejectBgv(int id, String remarks) =>
      _api.post('$_base/candidates/$id/bgv/reject', body: {'remarks': remarks}, parse: _detail);

  // ── approvals ──

  Future<NpCandidateDetail> dmDecision(int id,
          {required String action, String? sendBackStage, String? remarks}) =>
      _api.post(
        '$_base/candidates/$id/dm-decision',
        body: {'action': action, 'sendBackStage': sendBackStage, 'remarks': remarks},
        parse: _detail,
      );

  Future<NpCandidateDetail> opsDecision(int id,
          {required String action, String? sendBackStage, Map<String, bool>? checklist, String? remarks}) =>
      _api.post(
        '$_base/candidates/$id/ops-decision',
        body: {'action': action, 'sendBackStage': sendBackStage, 'checklist': checklist, 'remarks': remarks},
        parse: _detail,
      );

  // ── agreement + PDCs ──

  Future<NpCandidateDetail> submitAgreement(
    int id, {
    required String agreementPath,
    required String pdc1Path,
    required String pdc2Path,
    required String agreementDate,
    required NpPdcInput pdc1,
    required NpPdcInput pdc2,
    String? remarks,
  }) async {
    final form = FormData.fromMap({
      'agreementFile': await MultipartFile.fromFile(agreementPath),
      'pdc1File': await MultipartFile.fromFile(pdc1Path),
      'pdc2File': await MultipartFile.fromFile(pdc2Path),
      'agreementDate': agreementDate,
      'details': jsonEncode({'pdc1': pdc1.toJson(), 'pdc2': pdc2.toJson()}),
      if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
    });
    try {
      final res = await _api.raw.post<Map<String, dynamic>>(
        '$_base/candidates/$id/agreement',
        data: form,
        options: Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 3)),
      );
      return _detail(res.data!['data']);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── correction ──

  Future<NpCandidateDetail> resubmit(int id, {String? remarks}) =>
      _api.post('$_base/candidates/$id/resubmit', body: {'remarks': remarks}, parse: _detail);

  // ── app activation ──

  Future<NpOtpSent> sendActivationOtp(int id, String mobileNumber) => _api.post(
        '$_base/candidates/$id/activation/send-otp',
        body: {'mobileNumber': mobileNumber},
        parse: (d) => NpOtpSent.fromJson(d as Map<String, dynamic>),
      );

  Future<NpCandidateDetail> verifyActivationOtp(int id,
          {required String otp, String? deviceModel, String? deviceOs, String? deviceId, String? appVersion}) =>
      _api.post(
        '$_base/candidates/$id/activation/verify',
        body: {
          'otp': otp,
          'deviceModel': deviceModel,
          'deviceOs': deviceOs,
          'deviceId': deviceId,
          'appVersion': appVersion,
        },
        parse: _detail,
      );

  Future<NpCandidateDetail> activationException(int id, String reason) =>
      _api.post('$_base/candidates/$id/activation/exception', body: {'reason': reason}, parse: _detail);

  // ── ESAF + final activation ──

  Future<NpCandidateDetail> createEsafId(int id, String esafId) =>
      _api.post('$_base/candidates/$id/esaf-id', body: {'esafId': esafId}, parse: _detail);

  Future<NpCandidateDetail> finalActivate(int id) =>
      _api.post('$_base/candidates/$id/final-activate', body: const {}, parse: _detail);

  // ── audit ──

  Future<List<NpAuditLog>> audit(int candidateId) => _api.get(
        '$_base/candidates/$candidateId/audit',
        parse: (d) => (d as List? ?? const []).whereType<Map<String, dynamic>>().map(NpAuditLog.fromJson).toList(),
      );

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    String? msg;
    if (data is Map && data['message'] is String) msg = data['message'] as String;
    if (e.response != null) {
      return ApiException(msg ?? 'Request failed (HTTP ${e.response!.statusCode})', statusCode: e.response!.statusCode);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException('Network timeout. Check your connection.');
    }
    return ApiException(e.message ?? 'Network error');
  }
}
