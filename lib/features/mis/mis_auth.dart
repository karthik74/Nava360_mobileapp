import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mis_api_client.dart';
import 'mis_models.dart';
import 'mis_storage.dart';

/// Derive the Grow With Me password from an employee ID: insert "@" after the
/// 2-letter prefix. e.g. "XY12345" → "XY@12345". Mirrors `deriveMisPassword`
/// in the web MisModule.tsx, so the mobile auto-login uses the same credential.
String deriveMisPassword(String empId) {
  final id = empId.trim();
  return id.length > 2 ? '${id.substring(0, 2)}@${id.substring(2)}' : id;
}

/// Resolve the MIS emp id from the nava360 login response.
///
/// `username` is the canonical source, but it is NOT always the clean employee
/// code the GWM backend expects: the nava360 login also accepts an email (the
/// response then carries it verbatim), and some accounts store the code
/// lowercased ("xy12345"). Both silently broke the auto-login for those users —
/// "xy@12345" is not the derived password the GWM API knows.
///
/// Rules, in order:
///   1. an email-shaped value is reduced to its local part (xy12345@a.b → xy12345);
///   2. a code-shaped value (2-4 letters + digits, optional -/_/space between)
///      is normalised to UPPERCASE prefix + digits (xy-12345 → XY12345);
///   3. `username` is tried first, then `email`;
///   4. if nothing matches the code shape, the trimmed username passes through
///      unchanged (never silently drop an identity the backend might accept).
String misEmpIdFromIdentity({String? username, String? email}) {
  String norm(String? raw) {
    var id = (raw ?? '').trim();
    if (id.isEmpty) return '';
    if (id.contains('@')) id = id.split('@').first.trim();
    final m = RegExp(r'^([A-Za-z]{2,4})[-_ ]?(\d{3,})$').firstMatch(id);
    return m != null ? '${m.group(1)!.toUpperCase()}${m.group(2)!}' : '';
  }

  final fromUsername = norm(username);
  if (fromUsername.isNotEmpty) return fromUsername;
  final fromEmail = norm(email);
  if (fromEmail.isNotEmpty) return fromEmail;
  return (username ?? '').trim();
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
    _restored = _restore();
  }

  final MisApiClient _api;

  /// Completes when the cached-session restore has finished — auto-login MUST
  /// await this instead of bailing out, or the startup attempt races the
  /// secure-storage read and silently does nothing (the old "MIS sometimes
  /// doesn't open" bug).
  late final Future<void> _restored;

  /// The auto-login currently in flight, so concurrent triggers (app root,
  /// route gate, auth listener) coalesce into one request instead of stacking.
  Future<void>? _inflight;

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

  /// Silent auto-login using the nava360 identity — emp id from the app login
  /// (normalised via [misEmpIdFromIdentity]), password derived the same way as
  /// the web. No-op if already signed in as the same employee. Awaitable: when
  /// this future completes, the state is either a signed-in session or a final
  /// error — never still racing the restore or a concurrent attempt.
  Future<void> ensureAutoLogin(String empId) async {
    final resolved = misEmpIdFromIdentity(username: empId);
    final id = resolved.isNotEmpty ? resolved : empId.trim();
    if (id.isEmpty) return;

    // Never race the cached-session restore or another sign-in — wait for both.
    await _restored;
    while (_inflight != null) {
      await _inflight;
    }

    final u = state.asData?.value?.user;
    // Treat a cached session that carries neither designation nor role as
    // incomplete (e.g. persisted by an older build) and re-authenticate to
    // refresh the profile — otherwise the dashboard falls back to the scope
    // tier label ("CEO / Director") forever for that user.
    final hasProfile = (u?.designation?.trim().isNotEmpty ?? false) ||
        (u?.role?.trim().isNotEmpty ?? false);
    if (u != null && u.empId.toUpperCase() == id.toUpperCase() && hasProfile) {
      return; // already signed in as the right user with a full profile
    }

    final attempt = _autoSignIn(id);
    _inflight = attempt;
    try {
      await attempt;
    } finally {
      _inflight = null;
    }
  }

  /// One auto-login: up to three tries with a short backoff, so a flaky mobile
  /// network or a server hiccup doesn't bounce the user out of MIS. A 4xx
  /// (bad credentials) is final — retrying the same password can't heal it.
  Future<void> _autoSignIn(String id) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await signIn(id, deriveMisPassword(id));
        return; // signIn persisted token + user and set the session state
      } catch (e) {
        final sc = e is MisApiException ? e.statusCode : null;
        final retryable = sc == null || sc >= 500;
        if (!retryable || attempt >= 3) {
          return; // state is AsyncValue.error → the MIS gate decides
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
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
