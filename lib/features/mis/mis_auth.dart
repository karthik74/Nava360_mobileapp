import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mis_api_client.dart';
import 'mis_models.dart';
import 'mis_storage.dart';

/// Derive the Grow With Me password from an employee ID: insert "@" after the
/// 2-letter prefix. e.g. "NL13465" → "NL@13465". Mirrors `deriveMisPassword`
/// in the web MisModule.tsx, so the mobile auto-login uses the same credential.
String deriveMisPassword(String empId) {
  final id = empId.trim();
  return id.length > 2 ? '${id.substring(0, 2)}@${id.substring(2)}' : id;
}

/// The current MIS session (null user ⇒ signed out).
class MisSession {
  final MisUser? user;
  final MisScope? scope;
  final bool mustChangePassword;
  const MisSession({this.user, this.scope, this.mustChangePassword = false});
}

/// Holds the MIS (Grow With Me) session. Separate from the app's AuthController
/// because MIS authenticates against a different backend with its own token.
class MisAuthController extends StateNotifier<AsyncValue<MisSession?>> {
  MisAuthController(this._api) : super(const AsyncValue.loading()) {
    _restore();
  }

  final MisApiClient _api;

  /// Rehydrate a cached session on startup (token + user persisted on login).
  Future<void> _restore() async {
    try {
      final token = await MisStorage.readToken();
      if (token == null || token.isEmpty) {
        state = const AsyncValue.data(null);
        return;
      }
      final rawUser = await MisStorage.readUserJson();
      MisUser? user;
      MisScope? scope;
      if (rawUser != null) {
        final m = jsonDecode(rawUser) as Map<String, dynamic>;
        if (m['user'] is Map) {
          user = MisUser.fromJson((m['user'] as Map).cast<String, dynamic>());
        }
        if (m['scope'] is Map) {
          scope = MisScope.fromJson((m['scope'] as Map).cast<String, dynamic>());
        }
      }
      state = AsyncValue.data(MisSession(user: user, scope: scope));
    } catch (_) {
      state = const AsyncValue.data(null);
    }
  }

  /// Sign in with an explicit emp id + password (manual MIS login).
  Future<void> signIn(String empId, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.post<MisLoginResult>(
        '/auth/login',
        auth: false,
        body: {'emp_id': empId.trim(), 'password': password},
        parse: (d) => MisLoginResult.fromJson((d as Map).cast<String, dynamic>()),
      );
      if (res.token != null) await MisStorage.writeToken(res.token!);
      await MisStorage.writeUserJson(jsonEncode({
        'user': res.user?.toJson(),
        'scope': {'tier': res.scope?.tier, 'full_access': res.scope?.fullAccess},
      }));
      state = AsyncValue.data(MisSession(
        user: res.user,
        scope: res.scope,
        mustChangePassword: res.mustChangePassword,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Silent auto-login using the nava360 identity — emp id from the app login,
  /// password derived the same way as the web. No-op if already signed in as the
  /// same employee. On failure the gate falls back to a manual MIS login.
  Future<void> ensureAutoLogin(String empId) async {
    final id = empId.trim();
    if (id.isEmpty) return;
    if (state.isLoading) return; // a sign-in is already in flight
    final cur = state.asData?.value;
    final u = cur?.user;
    // Treat a cached session that carries neither designation nor role as
    // incomplete (e.g. persisted by an older build) and re-authenticate to
    // refresh the profile — otherwise the dashboard falls back to the scope
    // tier label ("CEO / Director") forever for that user.
    final hasProfile = (u?.designation?.trim().isNotEmpty ?? false) ||
        (u?.role?.trim().isNotEmpty ?? false);
    if (u != null &&
        u.empId.toUpperCase() == id.toUpperCase() &&
        hasProfile) {
      return; // already signed in as the right user with a full profile
    }
    try {
      await signIn(id, deriveMisPassword(id));
    } catch (_) {
      // state is already AsyncValue.error → the MIS gate navigates back.
    }
  }

  Future<void> signOut() async {
    try {
      await _api.post('/auth/logout', parse: (_) => null);
    } catch (_) {
      // best-effort; clear locally regardless
    }
    await MisStorage.clear();
    state = const AsyncValue.data(null);
  }

  /// Called when a MIS request returns 401 (token rejected) — drop the session.
  void sessionExpired() {
    MisStorage.clear();
    state = const AsyncValue.data(null);
  }
}

final misAuthControllerProvider =
    StateNotifierProvider<MisAuthController, AsyncValue<MisSession?>>(
  (ref) => MisAuthController(ref.watch(misApiClientProvider)),
);

/// Convenience: the current MIS session without the AsyncValue wrapper.
final misSessionProvider = Provider<MisSession?>(
  (ref) => ref.watch(misAuthControllerProvider).asData?.value,
);
