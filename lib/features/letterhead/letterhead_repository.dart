import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'letterhead_models.dart';

final letterheadRepositoryProvider =
    Provider((ref) => LetterheadRepository(ref.watch(apiClientProvider)));

/// Admin Tools · Letter Head API client — typed wrappers over
/// `/api/admin/letterhead`, gated server-side by `ADMIN_LETTERHEAD_VIEW`.
/// Only a single guide file per user is stored (no per-document alignment —
/// see `letterhead_models.dart` for why).
class LetterheadRepository {
  LetterheadRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/admin/letterhead';

  /// The caller's saved letterhead guide, or `null` if none uploaded yet.
  Future<AdminLetterhead?> mine() async {
    try {
      return await _api.get<AdminLetterhead?>(
        '$_base/mine',
        parse: (d) =>
            d == null ? null : AdminLetterhead.fromJson(d as Map<String, dynamic>),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Uploads (or replaces) the caller's letterhead guide file.
  Future<AdminLetterhead> upload(String filePath, {String? filename}) async {
    final name = filename ?? filePath.split(RegExp(r'[\\/]+')).last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: name),
    });
    final res = await _api.raw.post<Map<String, dynamic>>(_base, data: form);
    final data = (res.data?['data'] as Map<String, dynamic>?) ?? const {};
    return AdminLetterhead.fromJson(data);
  }

  Future<void> delete() {
    return _api.raw.delete(_base);
  }
}
