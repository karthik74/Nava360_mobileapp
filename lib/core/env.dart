/// Build-time configuration.
///
/// Override via `--dart-define`:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8080
class Env {
  /// Default targets the Android emulator's host loopback. iOS simulator uses
  /// `http://localhost:8080`; a physical device needs your LAN IP.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    //defaultValue: 'https://hrms.navachetanalivelihoods.com/',
    defaultValue: 'http://192.168.0.50:8443/',
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
