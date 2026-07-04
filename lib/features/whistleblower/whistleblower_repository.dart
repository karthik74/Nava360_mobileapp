import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'whistleblower_models.dart';

final whistleblowerRepositoryProvider =
    Provider((ref) => WhistleblowerRepository(ref.watch(apiClientProvider)));

typedef ProgressCb = void Function(int sent, int total);

class WhistleblowerRepository {
  WhistleblowerRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/mobile/whistleblower';

  Future<List<WbCategoryOption>> categories() {
    return _api.get<List<WbCategoryOption>>(
      '$_base/categories',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => WbCategoryOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<WbCase>> myCases() {
    return _api.get<List<WbCase>>(
      '$_base/my-cases',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => WbCase.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<WbCase> myCaseDetail(int id) {
    return _api.get<WbCase>(
      '$_base/my-cases/$id',
      parse: (d) => WbCase.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<WbComment> addComment(int id, String text) {
    return _api.post<WbComment>(
      '$_base/my-cases/$id/comments',
      body: {'commentText': text},
      parse: (d) => WbComment.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Submit a new concern with optional evidence. Uses the raw dio so we can
  /// report upload progress; the auth header is still attached by the interceptor.
  Future<WbCreated> createCase({
    required String category,
    required String subject,
    required String description,
    DateTime? incidentDate,
    String? department,
    String? personsInvolved,
    required bool anonymous,
    List<EvidenceFile> evidence = const [],
    ProgressCb? onProgress,
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('category', category));
    form.fields.add(MapEntry('subject', subject));
    form.fields.add(MapEntry('description', description));
    if (incidentDate != null) {
      form.fields.add(MapEntry('incidentDate', _isoDate(incidentDate)));
    }
    if (department != null && department.trim().isNotEmpty) {
      form.fields.add(MapEntry('department', department.trim()));
    }
    if (personsInvolved != null && personsInvolved.trim().isNotEmpty) {
      form.fields.add(MapEntry('personsInvolved', personsInvolved.trim()));
    }
    form.fields.add(MapEntry('anonymous', anonymous.toString()));
    for (final f in evidence) {
      form.files.add(MapEntry(f.category, await _multipart(f)));
    }

    final res = await _api.raw.post<Map<String, dynamic>>(
      '$_base/cases',
      data: form,
      onSendProgress: (sent, total) => onProgress?.call(sent, total),
    );
    return WbCreated.fromJson((res.data!['data']) as Map<String, dynamic>);
  }

  /// Add one more piece of evidence to an existing (open) case.
  Future<WbAttachment> addAttachment(int id, EvidenceFile f, {ProgressCb? onProgress}) async {
    final form = FormData();
    form.files.add(MapEntry('file', await _multipart(f)));
    form.fields.add(MapEntry('category', f.category.toUpperCase()));
    if (f.durationSeconds != null) {
      form.fields.add(MapEntry('durationSeconds', f.durationSeconds.toString()));
    }
    final res = await _api.raw.post<Map<String, dynamic>>(
      '$_base/my-cases/$id/attachments',
      data: form,
      onSendProgress: (sent, total) => onProgress?.call(sent, total),
    );
    return WbAttachment.fromJson((res.data!['data']) as Map<String, dynamic>);
  }

  /// Evidence bytes, fetched through the authed view endpoint (permission-checked).
  Future<Uint8List> fetchAttachment(int attachmentId) {
    return _api.getBytes('$_base/attachments/$attachmentId/view');
  }

  Future<MultipartFile> _multipart(EvidenceFile f) {
    return MultipartFile.fromFile(
      f.path,
      filename: f.fileName,
      contentType: DioMediaType.parse(f.mime),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
