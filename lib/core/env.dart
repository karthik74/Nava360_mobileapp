/// Build-time configuration.
///
/// Override via `--dart-define`:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8080
class Env {
  /// Default targets the Android emulator's host loopback. iOS simulator uses
  /// `http://localhost:8080`; a physical device needs your LAN IP.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://navachetanalivelihoods.com/backend/',
  );
}
