import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import 'mis_storage.dart';

/// Thrown for any non-2xx MIS response. Carries the server's `error`/`message`.
class MisApiException implements Exception {
  final int? statusCode;
  final String message;
  MisApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Dedicated Dio for the MIS (Grow With Me) backend.
///
/// Separate from the app's [ApiClient] on purpose — MIS is a different origin
/// ([Env.misApiBaseUrl]), authenticates with `Authorization: Token <token>`
/// (Django-REST style, NOT `Bearer`), and returns RAW JSON (no `ApiResponse`
/// envelope to unwrap). Mirrors the web module's single `apiRequest` wrapper
/// (src/mis/gwm/api/config.ts): base URL + token header + 401 → auto-logout.
class MisApiClient {
  MisApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: Env.misApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
      responseType: ResponseType.json,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Skip the token on the auth endpoints (opt out via extra['auth']=false).
        if (options.extra['auth'] != false) {
          final token = await MisStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Token $token';
          }
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401) {
          await MisStorage.clear();
          onUnauthorized?.call();
        }
        handler.next(e);
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        request: false,
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
        logPrint: (obj) => debugPrint(obj.toString(), wrapWidth: 1024),
      ));
    }
  }

  static final MisApiClient instance = MisApiClient._();
  late final Dio _dio;

  /// Invoked when a MIS request returns 401 — wired at the app root to clear the
  /// MIS session so the gate re-authenticates.
  void Function()? onUnauthorized;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
    required T Function(dynamic) parse,
  }) async {
    try {
      final res = await _dio.get(
        path,
        queryParameters: _clean(query),
        options: Options(extra: {'auth': auth}),
      );
      return parse(res.data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    bool auth = true,
    required T Function(dynamic) parse,
  }) async {
    try {
      final res = await _dio.post(
        path,
        data: body,
        options: Options(extra: {'auth': auth}),
      );
      return parse(res.data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> patch<T>(
    String path, {
    Object? body,
    bool auth = true,
    required T Function(dynamic) parse,
  }) async {
    try {
      final res = await _dio.patch(
        path,
        data: body,
        options: Options(extra: {'auth': auth}),
      );
      return parse(res.data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Drop null / empty query params (mirrors the web `qs()` helper) so a filter
  /// the user left on "All" is never sent.
  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v != null && v != '') out[k] = v;
    });
    return out;
  }

  MisApiException _mapError(DioException e) {
    String? msg;
    final data = e.response?.data;
    if (data is Map) {
      if (data['error'] is String) {
        msg = data['error'] as String;
      } else if (data['message'] is String) {
        msg = data['message'] as String;
      }
    }
    if (e.response != null) {
      return MisApiException(
        msg ?? 'Request failed (HTTP ${e.response!.statusCode})',
        statusCode: e.response!.statusCode,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return MisApiException('Network timeout. Check your connection.');
    }
    return MisApiException(msg ?? e.message ?? 'Cannot reach the MIS server.');
  }
}

/// Riverpod accessor — inject into MIS repositories.
final misApiClientProvider = Provider<MisApiClient>((_) => MisApiClient.instance);
