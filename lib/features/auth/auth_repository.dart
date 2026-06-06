import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/secure_storage.dart';
import 'auth_models.dart';

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<AuthUser> login(LoginRequest req) async {
    final user = await _api.post<AuthUser>(
      '/api/auth/login',
      body: req.toJson(),
      parse: (d) => AuthUser.fromJson(d as Map<String, dynamic>),
    );
    await SecureStorage.writeToken(user.token);
    await SecureStorage.writeUserJson(jsonEncode(user.toJson()));
    return user;
  }

  Future<void> forgotPassword(String username) async {
    await _api.post<void>(
      '/api/auth/forgot-password',
      body: {'username': username},
      parse: (_) {},
    );
  }

  Future<void> resetPassword({
    required String username,
    required String otp,
    required String newPassword,
  }) async {
    await _api.post<void>(
      '/api/auth/reset-password',
      body: {
        'username': username,
        'otp': otp,
        'newPassword': newPassword,
      },
      parse: (_) {},
    );
  }

  Future<void> logout() => SecureStorage.clear();

  /// Restore session from secure storage (called on app start).
  Future<AuthUser?> restore() async {
    final json = await SecureStorage.readUserJson();
    if (json == null || json.isEmpty) return null;
    try {
      return AuthUser.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      await SecureStorage.clear();
      return null;
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
