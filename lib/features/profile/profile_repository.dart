import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/env.dart';

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
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);

/// Builds an absolute URL for a backend file path (e.g. "/api/files/12").
String? absoluteFileUrl(String? path) => Env.fileUrl(path);
