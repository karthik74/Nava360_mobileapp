import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Repository for notification endpoints.
class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  /// Registers (or updates) this device's FCM token with the backend so the
  /// server can push to it. The endpoint accepts `{token, platform}` where
  /// platform is "ANDROID" or "IOS".
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    try {
      await _api.raw.post<dynamic>(
        '/api/notifications/device-tokens',
        data: {
          'token': token,
          'platform': platform,
        },
      );
    } on DioException catch (e) {
      debugPrint(
        'Device-token registration failed: '
        '${e.response?.statusCode} ${e.message}',
      );
      // Don't rethrow — push registration must never block the UI.
    } catch (e) {
      debugPrint('Device-token registration error: $e');
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);
