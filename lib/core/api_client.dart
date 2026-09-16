import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';
import 'secure_storage.dart';

/// Wraps the backend's `ApiResponse<T>` envelope.
class ApiEnvelope<T> {
  final bool success;
  final String? message;
  final T data;
  ApiEnvelope({required this.success, required this.data, this.message});

  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) parseData,
  ) {
    return ApiEnvelope<T>(
      success: json['success'] == true,
      message: json['message'] as String?,
      data: parseData(json['data']),
    );
  }
}

/// Thrown for any non-2xx response. Carries the backend's `message` when present.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Singleton-ish Dio with a JWT interceptor and friendly error mapping.
class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
      responseType: ResponseType.json,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await SecureStorage.readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['X-Device-Type'] = 'MOBILE';
        handler.next(options);
      },
      onError: (e, handler) {
        if (e.response?.statusCode == 401) {
          onUnauthorized?.call();
        }
        handler.next(e);
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
        logPrint: (obj) => debugPrint(obj.toString(), wrapWidth: 1024),
      ));
    }
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;

  Dio get raw => _dio;

  /// Invoked whenever an authenticated request comes back 401. Wired at the app
  /// root to clear stored credentials and bounce the user to the login screen.
  /// This is how a device that was signed out remotely (because the same user
  /// logged in elsewhere, displacing this session) cleanly recovers instead of
  /// looping on 401s.
  void Function()? onUnauthorized;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic) parse,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return ApiEnvelope.fromJson(res.data!, parse).data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Fetches a raw binary body (e.g. a PDF). Unlike [get], this does NOT unwrap
  /// the JSON `ApiResponse` envelope — the endpoint returns the bytes directly.
  Future<Uint8List> getBytes(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// POSTs JSON and receives a raw binary body (e.g. synthesized TTS audio).
  /// Like [getBytes], this does NOT unwrap the JSON `ApiResponse` envelope.
  /// [receiveTimeout] overrides the client default for latency-sensitive
  /// callers (e.g. TTS, which would rather fail fast and stay silent).
  Future<Uint8List> postBytes(
    String path, {
    Object? body,
    Duration? receiveTimeout,
  }) async {
    try {
      final res = await _dio.post<List<int>>(
        path,
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: receiveTimeout,
          sendTimeout: receiveTimeout,
        ),
      );
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required T Function(dynamic) parse,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        queryParameters: query,
      );
      return ApiEnvelope.fromJson(res.data!, parse).data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> put<T>(
    String path, {
    Object? body,
    required T Function(dynamic) parse,
  }) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(path, data: body);
      return ApiEnvelope.fromJson(res.data!, parse).data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> patch<T>(
    String path, {
    Object? body,
    required T Function(dynamic) parse,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(path, data: body);
      return ApiEnvelope.fromJson(res.data!, parse).data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    if (e.response != null) {
      final data = e.response!.data;
      String? msg;
      if (data is Map && data['message'] is String) {
        msg = data['message'] as String;
      } else if (data is Map && data['error'] is String) {
        msg = data['error'] as String;
      }
      return ApiException(
        msg ?? 'Request failed (HTTP ${e.response!.statusCode})',
        statusCode: e.response!.statusCode,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException('Network timeout. Check your connection.');
    }
    return ApiException(e.message ?? 'Network error');
  }
}

/// Riverpod accessor — inject into repositories.
final apiClientProvider = Provider<ApiClient>((_) => ApiClient.instance);
