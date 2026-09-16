import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import 'mis_storage.dart';

/// Thrown for any non-2xx MIS response. Carries the server's `error`/`message`,
/// the HTTP status, and the decoded body — some endpoints answer a non-2xx with
/// actionable detail rather than a failure (e.g. `/clients/list` 409 names the
/// months that DO have client-level rows).
class MisApiException implements Exception {
  final int? statusCode;
  final String message;
  final Map<String, dynamic> payload;
  MisApiException(this.message, {this.statusCode, this.payload = const {}});

  /// A string list off the payload (e.g. `detail_months`), never null.
  List<String> payloadList(String key) {
    final v = payload[key];
    return v is List ? v.map((e) => e.toString()).toList() : const [];
  }

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

  /// Fetches a binary (.xlsx) endpoint — the server-rendered report exports
  /// (Daily Reports, Branches Pending) that build the file on the backend, same
  /// as the web module's `apiDownload` (src/mis/gwm/api/config.ts). Returns the
  /// raw bytes plus the filename the server suggested via Content-Disposition,
  /// for the caller to hand to `misSaveBytes`.
  Future<(Uint8List, String?)> getBytes(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        options: Options(responseType: ResponseType.bytes),
      );
      final disposition = res.headers.value('content-disposition');
      final match = disposition == null
          ? null
          : RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
      return (Uint8List.fromList(res.data ?? const []), match?.group(1));
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
    var payload = const <String, dynamic>{};
    if (data is Map) {
      payload = data.cast<String, dynamic>();
      if (data['error'] is String) {
        msg = data['error'] as String;
      } else if (data['message'] is String) {
        msg = data['message'] as String;
      }
    }
    if (e.response != null) {
      final status = e.response!.statusCode;
      // 5xx bodies are usually a gateway page, not something to show a user —
      // mirror the web wrapper and give a clean "server unavailable" message.
      if (status != null && status >= 500) {
        return MisApiException(
          'The server is temporarily unavailable. Please try again in a moment.',
          statusCode: status,
          payload: payload,
        );
      }
      return MisApiException(
        msg ?? 'Request failed (HTTP $status)',
        statusCode: status,
        payload: payload,
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
