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
        handler.next(options);
      },
      onError: (e, handler) {
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
