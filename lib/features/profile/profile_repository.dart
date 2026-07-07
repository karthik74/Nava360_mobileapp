import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/env.dart';

/// A document attached to the signed-in employee's record.
class EmployeeDocument {
  EmployeeDocument({
    required this.id,
    required this.docType,
    required this.docTypeLabel,
    this.label,
    required this.fileName,
    this.contentType,
    required this.sizeBytes,
    required this.url,
    this.uploadedBy,
    this.createdAt,
  });

  final int id;
  final String docType;
  final String docTypeLabel;
  final String? label;
  final String fileName;
  final String? contentType;
  final int sizeBytes;

  /// Relative signed download path (e.g. "/api/files/12?sig=…").
  final String url;
  final String? uploadedBy;
  final DateTime? createdAt;

  bool get isImage => (contentType ?? '').startsWith('image/');
  bool get isPdf => (contentType ?? '').contains('pdf');

  factory EmployeeDocument.fromJson(Map<String, dynamic> j) => EmployeeDocument(
        id: (j['id'] as num).toInt(),
        docType: j['docType'] as String? ?? '',
        docTypeLabel: j['docTypeLabel'] as String? ?? j['docType'] as String? ?? 'Document',
        label: j['label'] as String?,
        fileName: j['fileName'] as String? ?? 'file',
        contentType: j['contentType'] as String?,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        url: j['url'] as String? ?? '',
        uploadedBy: j['uploadedBy'] as String?,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
      );
}

/// A configured document type (code + label) for the upload dropdown.
class DocTypeOption {
  DocTypeOption({required this.code, required this.label});
  final String code;
  final String label;

  factory DocTypeOption.fromJson(Map<String, dynamic> j) => DocTypeOption(
        code: j['code'] as String,
        label: j['label'] as String? ?? j['code'] as String,
      );
}

class ProfileRepository {
  ProfileRepository(this._api);
  final ApiClient _api;

  /// Uploads a new profile photo for the signed-in user and returns the stored
  /// image URL (e.g. "/api/files/123").
  Future<String?> uploadPhoto(String filePath, {String? filename}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final res = await _api.raw.post<Map<String, dynamic>>(
      '/api/employees/me/photo',
      data: form,
    );
    final data = res.data?['data'] as Map<String, dynamic>?;
    return data?['profileImageUrl'] as String?;
  }

  /// The signed-in employee's own documents, newest first.
  Future<List<EmployeeDocument>> myDocuments() async {
    final res = await _api.raw
        .get<Map<String, dynamic>>('/api/employees/me/documents');
    final list = res.data?['data'] as List? ?? const [];
    return list
        .map((e) => EmployeeDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Active document types for the upload dropdown.
  Future<List<DocTypeOption>> documentTypes() async {
    final res = await _api.raw.get<Map<String, dynamic>>(
      '/api/lookups/document-types',
      queryParameters: {'activeOnly': true},
    );
    final list = res.data?['data'] as List? ?? const [];
    return list
        .map((e) => DocTypeOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Uploads a document onto the signed-in employee's own record.
  Future<EmployeeDocument> uploadMyDocument({
    required String filePath,
    required String docType,
    String? label,
    String? filename,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
      'docType': docType,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
    });
    final res = await _api.raw.post<Map<String, dynamic>>(
      '/api/employees/me/documents',
      data: form,
    );
    final data = res.data?['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Upload failed: empty response');
    }
    return EmployeeDocument.fromJson(data);
  }

  /// Downloads a stored file (relative signed path) as bytes, authenticated.
  Future<List<int>> downloadFile(String relativeUrl) async {
    final res = await _api.raw.get<List<int>>(
      relativeUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);

/// Builds an absolute URL for a backend file path (e.g. "/api/files/12").
String? absoluteFileUrl(String? path) => Env.fileUrl(path);
