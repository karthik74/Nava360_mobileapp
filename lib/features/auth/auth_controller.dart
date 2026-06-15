import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';
import 'auth_repository.dart';

/// Holds the current authenticated user (null = signed out).
class AuthController extends StateNotifier<AsyncValue<AuthUser?>> {
  AuthController(this._repo) : super(const AsyncValue.loading()) {
    _bootstrap();
  }

  final AuthRepository _repo;

  Future<void> _bootstrap() async {
    final user = await _repo.restore();
    state = AsyncValue.data(user);
  }

  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    try {
      final u = await _repo.login(
        LoginRequest(username: username.trim(), password: password),
      );
      state = AsyncValue.data(u);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncValue.data(null);
  }

  /// Called when the backend rejects our token (HTTP 401) — typically because
  /// this session was displaced by a login on another device. Clears the stored
  /// credentials and flips to signed-out so the router redirects to /login.
  Future<void> sessionExpired() async {
    // Already signed out — nothing to do (avoids redundant redirects/loops).
    if (state.asData?.value == null) return;
    await _repo.logout();
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthUser?>>(
  (ref) => AuthController(ref.watch(authRepositoryProvider)),
);

/// Convenience: returns the AuthUser or null without the AsyncValue wrapper.
final authUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(authControllerProvider).asData?.value,
);
