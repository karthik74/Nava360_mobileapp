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

  /// Changes the signed-in user's password after verifying the current one.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.post<void>(
      '/api/users/me/change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      parse: (_) {},
    );
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

  // ── First-time login (account activation) ─────────────────────────────────

  /// Step 1 — locate the account by employee code and send an OTP to the
  /// registered mobile. Returns the masked mobile and any server message.
  Future<({bool requiresOtp, String? maskedMobile, String? message})>
      firstLoginStart(String employeeCode) {
    return _api.post(
      '/api/auth/first-login/start',
      body: {'employeeCode': employeeCode},
      parse: (d) {
        final m = (d as Map<String, dynamic>?) ?? const {};
        return (
          requiresOtp: m['requiresOtp'] != false,
          maskedMobile: m['maskedMobile'] as String?,
          message: m['message'] as String?,
        );
      },
    );
  }

  /// Step 1b — resend the OTP (server enforces cooldown / max-resend limits).
  Future<void> firstLoginResendOtp(String employeeCode) {
    return _api.post<void>(
      '/api/auth/first-login/resend-otp',
      body: {'employeeCode': employeeCode},
      parse: (_) {},
    );
  }

  /// Step 2 — verify the 6-digit OTP; returns a short-lived setup token.
  Future<({String setupToken, int expiresInSeconds})> firstLoginVerifyOtp(
    String employeeCode,
    String otp,
  ) {
    return _api.post(
      '/api/auth/first-login/verify-otp',
      body: {'employeeCode': employeeCode, 'otp': otp},
      parse: (d) {
        final m = d as Map<String, dynamic>;
        return (
          setupToken: m['setupToken'] as String? ?? '',
          expiresInSeconds: (m['expiresInSeconds'] as num?)?.toInt() ?? 0,
        );
      },
    );
  }

  /// Step 3 — set the permanent password using the setup token.
  Future<void> firstLoginSetPassword({
    required String employeeCode,
    required String setupToken,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _api.post<void>(
      '/api/auth/first-login/set-password',
      body: {
        'employeeCode': employeeCode,
        'setupToken': setupToken,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
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
