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
  /// platform is "ANDROID" or "IOS". Returns whether the backend took it.
  Future<bool> registerDeviceToken({
    required String token,
    required String platform,
    String? appVersionName,
    int? appVersionCode,
  }) async {
    try {
      await _api.raw.post<dynamic>(
        '/api/notifications/device-tokens',
        data: {
          'token': token,
          'platform': platform,
          if (appVersionName != null) 'appVersionName': appVersionName,
          if (appVersionCode != null) 'appVersionCode': appVersionCode,
        },
      );
      return true;
    } on DioException catch (e) {
      debugPrint(
        'Device-token registration failed: '
        '${e.response?.statusCode} ${e.message}',
      );
      // Don't rethrow — push registration must never block the UI.
      return false;
    } catch (e) {
      debugPrint('Device-token registration error: $e');
      return false;
    }
  }

  /// Removes this device's FCM token from the backend so it stops receiving
  /// pushes. Called when the user disables notifications (and on logout).
  Future<void> unregisterDeviceToken(String token) async {
    try {
      await _api.raw.delete<dynamic>(
        '/api/notifications/device-tokens',
        queryParameters: {'token': token},
      );
    } on DioException catch (e) {
      debugPrint(
        'Device-token unregister failed: '
        '${e.response?.statusCode} ${e.message}',
      );
    } catch (e) {
      debugPrint('Device-token unregister error: $e');
    }
  }

  /// Newest first. A user without TASK_VIEW_NOTIFICATIONS gets 403 — that is
  /// "no in-app alerts for this role", not an error worth showing.
  Future<List<InAppNotification>> inApp({int page = 0, int size = 50}) async {
    try {
      return await _api.get<List<InAppNotification>>(
        '/api/task-notifications',
        query: {'page': page, 'size': size},
        parse: (d) => ((d as Map)['content'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => InAppNotification.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 403) return const [];
      rethrow;
    }
  }

  Future<void> markRead(int id) =>
      _api.put<void>('/api/task-notifications/$id/read', parse: (_) {});

  Future<void> markAllRead() =>
      _api.put<void>('/api/task-notifications/read-all', parse: (_) {});
}

/// One in-app notification row from `/api/task-notifications` (task alerts,
/// PTP alerts, FTOD day digests). [route] is where a tap should land; null on
/// older rows, which fall back to their task (or the task list).
class InAppNotification {
  final int id;
  final int? taskId;
  final String title;
  final String message;
  final String? route;
  final bool read;
  final DateTime? createdAt;

  const InAppNotification({
    required this.id,
    required this.title,
    required this.message,
    this.taskId,
    this.route,
    this.read = false,
    this.createdAt,
  });

  factory InAppNotification.fromJson(Map<String, dynamic> j) {
    final route = j['route']?.toString().trim();
    return InAppNotification(
      id: (j['id'] as num).toInt(),
      taskId: (j['taskId'] as num?)?.toInt(),
      title: (j['title'] ?? '').toString(),
      message: (j['message'] ?? '').toString(),
      // Only in-app paths are honoured — never an external URL.
      route: route != null && route.startsWith('/') ? route : null,
      read: j['read'] == true,
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
    );
  }

  InAppNotification markedRead() => InAppNotification(
        id: id,
        taskId: taskId,
        title: title,
        message: message,
        route: route,
        read: true,
        createdAt: createdAt,
      );
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);
