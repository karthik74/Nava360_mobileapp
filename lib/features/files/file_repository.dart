import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// A file stored on the backend via `POST /api/files`. The [url] is a relative
/// path (`/api/files/{id}`) that resolves against the API base URL.
class UploadedFile {
  UploadedFile({
    required this.id,
    required this.url,
    required this.name,
    this.contentType,
    this.sizeBytes,
  });

  final int id;
  final String url;
  final String name;
  final String? contentType;
  final int? sizeBytes;

  bool get isImage => (contentType ?? '').startsWith('image/');

  factory UploadedFile.fromJson(Map<String, dynamic> j) => UploadedFile(
        id: (j['id'] as num).toInt(),
        url: j['url'] as String? ?? '/api/files/${j['id']}',
        name: j['originalName'] as String? ?? j['name'] as String? ?? 'file',
        contentType: j['contentType'] as String?,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt(),
      );

  /// Compact representation persisted inside a task's form response so the value
  /// stays self-describing (id for re-fetch, url for rendering, name for display).
  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        if (contentType != null) 'contentType': contentType,
      };
}

class FileRepository {
  FileRepository(this._api);
  final ApiClient _api;

  /// Uploads a local file and returns its stored descriptor.
  Future<UploadedFile> upload(String filePath, {String? filename}) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });
      final res = await _api.raw.post<Map<String, dynamic>>('/api/files', data: form);
      final data = res.data?['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw ApiException('Upload failed: empty response');
      }
      return UploadedFile.fromJson(data);
    } on DioException catch (e) {
      final msg = e.response?.data is Map && (e.response!.data as Map)['message'] is String
          ? (e.response!.data as Map)['message'] as String
          : (e.message ?? 'Upload failed');
      throw ApiException(msg, statusCode: e.response?.statusCode);
    }
  }
}

final fileRepositoryProvider = Provider<FileRepository>(
  (ref) => FileRepository(ref.watch(apiClientProvider)),
);
