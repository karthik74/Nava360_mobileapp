import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api_client.dart';
import 'app_version_models.dart';

class AppVersionRepository {
  AppVersionRepository(this._api);
  final ApiClient _api;

  /// Public update check — reachable before login (`/api/public/**`).
  Future<AppVersionCheck> check({
    required String platform,
    required int versionCode,
  }) {
    return _api.get<AppVersionCheck>(
      '/api/public/app-version',
      query: {'platform': platform, 'versionCode': versionCode},
      parse: (d) => AppVersionCheck.fromJson(d as Map<String, dynamic>),
    );
  }
}

final appVersionRepositoryProvider = Provider<AppVersionRepository>(
  (ref) => AppVersionRepository(ref.watch(apiClientProvider)),
);

/// Runs the update check for the running build + platform. Returns null on any
/// failure so a flaky network never blocks the app from opening.
final appVersionCheckProvider = FutureProvider<AppVersionCheck?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final code = int.tryParse(info.buildNumber) ?? 0;
    final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
    return await ref
        .watch(appVersionRepositoryProvider)
        .check(platform: platform, versionCode: code);
  } catch (_) {
    return null;
  }
});
