import 'package:flutter/services.dart' show appFlavor;

/// Build-time configuration.
///
/// The backend URL resolves per COMPANY FLAVOR (white-label builds; see
/// android/app/build.gradle.kts productFlavors). An explicit `--dart-define`
/// always wins, so local development against a LAN backend still works:
///   flutter run --flavor livelihoods --dart-define=API_BASE_URL=http://192.168.1.5:8443
class Env {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// One backend deployment per company; the flavor picks it at build time.
  static const Map<String, String> _flavorBaseUrls = {
    'livelihoods': 'https://hrms.navachetanalivelihoods.com/',
    'souhardha': 'https://hrms.navachetanasouhardha.com/',
    'laxmi': 'https://hrms.laxmimultistate.com/',
  };

  static final String apiBaseUrl = _overrideBaseUrl.isNotEmpty
      ? _overrideBaseUrl
      // Unflavored builds (plain `flutter run`/tests) behave like the
      // original single-company app.
      : _flavorBaseUrls[appFlavor] ?? _flavorBaseUrls['livelihoods']!;

  /// MIS (Grow With Me) backend base URL — a SEPARATE origin from [apiBaseUrl],
  /// with its own `Token` auth. Endpoints are relative to this (e.g. `/overview`,
  /// `/auth/login`). Override via `--dart-define=MIS_API_BASE_URL=...`.
  static const String misApiBaseUrl = String.fromEnvironment(
    'MIS_API_BASE_URL',
    defaultValue: 'https://growwithme.navachetanalivelihoods.com/gwm-api/api',
  );

  /// Builds an absolute URL for a backend file path (e.g. "/api/files/12").
  /// Returns null for empty input; passes absolute URLs through unchanged.
  static String? fileUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base =
        apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
    return base + (path.startsWith('/') ? path : '/$path');
  }

  /// Public privacy policy URL (hosted by the web app).
  static String get privacyPolicyUrl => fileUrl('/privacy-policy.html')!;
}
