// Visual-preview (golden screenshot) harness for the Nava360 app.
//
// Renders real screens with a signed-in fake user, fake branding and a fake
// HTTP backend (see fixtures.dart) so redesigned screens can be LOOKED at
// without a server or a login. Regenerate the PNGs with:
//
//   flutter test test/pro_preview --update-goldens
//
// Everything here is test-only: nothing under lib/ is modified. The harness
// deliberately imports no feature screens (each *_test.dart imports only the
// screens it renders) so a half-finished edit in one feature folder only
// breaks that one test file.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Transitive dependency of `geocoding`; used only to fake reverse-geocoding.
// ignore: depend_on_referenced_packages
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:go_router/go_router.dart';
import 'package:nava360/core/pro_ui.dart';
import 'package:nava360/core/api_client.dart';
import 'package:nava360/core/branding.dart';
import 'package:nava360/core/theme.dart';
import 'package:nava360/features/auth/auth_controller.dart';
import 'package:nava360/features/auth/auth_models.dart';
import 'package:nava360/features/auth/auth_repository.dart';

import 'fake_api.dart';
import 'fixtures.dart';

export 'fake_api.dart' show FakeApi, Raw, page;

// ─────────────────────────────────────────────────────────────────────────────
//  Frames
// ─────────────────────────────────────────────────────────────────────────────

/// Phone frame (logical px) and the tall variant for long scrolling screens.
/// Override for a specific phone, e.g. --dart-define=PREVIEW_W=360
/// --dart-define=PREVIEW_H=800 (a 720×1600 @2x Android phone).
const double _kW = 0.0 + int.fromEnvironment('PREVIEW_W', defaultValue: 390);
const double _kH = 0.0 + int.fromEnvironment('PREVIEW_H', defaultValue: 844);
const Size kPhone = Size(_kW, _kH);
const Size kPhoneTall = Size(_kW, 1500);
const double kDpr = 2;

/// Status-bar inset simulated at the top of every frame (logical px).
const double kStatusBar = 24;

// ─────────────────────────────────────────────────────────────────────────────
//  Fake identity + branding
// ─────────────────────────────────────────────────────────────────────────────

/// A branch manager with team visibility and broad self-service permissions,
/// so menus, Team, approvals and travel/helpdesk entries all show.
const AuthUser kPreviewUser = AuthUser(
  token: 'preview-token',
  tokenType: 'Bearer',
  userId: 7,
  username: 'kavya.r',
  email: 'kavya@nlpl.in',
  role: 'MANAGER',
  employeeId: 42,
  firstName: 'Kavya',
  lastName: 'Rao',
  roles: {'MANAGER', 'HR'},
  permissions: {
    'EMPLOYEE_VIEW',
    'ATTENDANCE_VIEW',
    'LEAVE_APPROVE',
    'LEAVE_VIEW',
    'TASK_VIEW',
    'TASK_ASSIGN',
    'TASK_REVIEW',
    'TASK_REVIEW_BRANCH',
    'TRAVEL_CLAIM_CREATE',
    'TRAVEL_CLAIM_VIEW',
    'TRAVEL_CLAIM_APPROVE',
    'TRAVEL_PLAN_CREATE',
    'TRAVEL_PLAN_VIEW',
    'HELPDESK_CREATE_TICKET',
    'CUSTOMER_NEARBY_VIEW',
    'CUSTOMER_VIEW',
    'CHAT_GROUP_CREATE',
    'VIEW_SELF_PERFORMANCE',
    'PERFORMANCE_SCORE_REVIEW',
    'ITR_DOCUMENT_VIEW_MY',
    'ANNOUNCEMENT_VIEW',
    'POLICY_VIEW',
  },
  branchIds: {3},
);

/// NLPL-style branding: teal brand colour, every optional feature switched on
/// (except the opening-insights intro, which would hijack navigation).
const Branding kPreviewBranding = Branding(
  productName: 'Nava360',
  companyName: 'Navachetana Livelihoods Pvt Ltd',
  companyShortName: 'NLPL',
  website: 'https://nlpl.in',
  supportEmail: 'support@nlpl.in',
  supportPhone: '+91 836 222 4455',
  primaryColor: '#00748C',
  features: {
    'FEATURE_CHAT': true,
    'FEATURE_AI_ASSISTANT': true,
    'FEATURE_BIOMETRIC_LOGIN': true,
    'FEATURE_CRM_PTP': true,
    'FEATURE_FTOD': true,
    'FEATURE_NEARBY_CUSTOMERS': true,
    'FEATURE_NP_ONBOARDING': true,
    'FEATURE_WHISTLEBLOWER': true,
    'FEATURE_OPENING_INSIGHTS': false,
  },
);

class _PreviewBranding extends BrandingNotifier {
  @override
  Branding build() {
    Branding.current = kPreviewBranding;
    AppColors.applyBrand(kPreviewBranding.brandColor);
    return kPreviewBranding;
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> refresh() async {}
}

class _PreviewAuthRepo extends AuthRepository {
  _PreviewAuthRepo(this.user) : super(ApiClient.instance);
  final AuthUser? user;
  @override
  Future<AuthUser?> restore() async => user;
  @override
  Future<void> logout() async {}
}

/// Starts already resolved (no loading frame) — signed in as [user], or
/// signed out when [user] is null.
class _PreviewAuthController extends AuthController {
  _PreviewAuthController(AuthUser? user) : super(_PreviewAuthRepo(user)) {
    state = AsyncValue.data(user);
  }
}

/// Overrides every test gets: identity, branding, branding-cache flag.
List<Override> baseOverrides({AuthUser? user = kPreviewUser}) => [
      authRepositoryProvider.overrideWithValue(_PreviewAuthRepo(user)),
      authControllerProvider
          .overrideWith((ref) => _PreviewAuthController(user)),
      brandingProvider.overrideWith(_PreviewBranding.new),
      brandingCacheReadProvider.overrideWith((_) => true),
    ];

// ─────────────────────────────────────────────────────────────────────────────
//  Fonts
// ─────────────────────────────────────────────────────────────────────────────

bool _fontsLoaded = false;

String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // flutter_tester lives at <root>/bin/cache/artifacts/engine/<plat>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return r'C:\Users\kkart\develop\flutter';
}

Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final p in paths) {
    final f = File(p);
    if (!f.existsSync()) {
      debugPrint('[pro_preview] font missing: $p');
      continue;
    }
    final bytes = f.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    any = true;
  }
  if (any) await loader.load();
}

/// Loads real fonts (Geist, Roboto, Material Icons, Playfair) so goldens show
/// text and icons instead of Ahem boxes. Call from setUpAll.
Future<void> loadPreviewFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final mf = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
  const geist = 'assets/fonts';
  await _loadFamily('Geist', [
    '$geist/Geist-Regular.ttf',
    '$geist/Geist-Medium.ttf',
    '$geist/Geist-SemiBold.ttf',
    '$geist/Geist-Bold.ttf',
  ]);
  await _loadFamily('PlayfairDisplay', ['$geist/PlayfairDisplay.ttf']);
  await _loadFamily('MaterialIcons', ['$mf/materialicons-regular.otf']);
  final roboto = [
    '$mf/roboto-regular.ttf',
    '$mf/roboto-medium.ttf',
    '$mf/roboto-bold.ttf',
    '$mf/roboto-light.ttf',
  ];
  await _loadFamily('Roboto', roboto);
  // Glyph fallbacks for characters the bundled fonts lack (→, emoji, …).
  // On a phone the OS supplies these; here we borrow the dev machine's.
  final win = '${Platform.environment['WINDIR'] ?? r'C:\Windows'}/Fonts';
  await _loadFamily('PreviewSymbols', ['$win/seguisym.ttf']);
  await _loadFamily('PreviewEmoji', ['$win/seguiemj.ttf']);
}

const List<String> _glyphFallback = ['Roboto', 'PreviewSymbols', 'PreviewEmoji'];

/// Family used for text whose style names NO fontFamily. On an Android phone
/// such text renders in the platform default (Roboto); the test engine would
/// draw box glyphs instead, so the preview theme fills those gaps with this
/// family. Override with --dart-define=PREVIEW_FALLBACK_FONT=Geist to see the
/// intended all-Geist look.
const String kFallbackFont =
    String.fromEnvironment('PREVIEW_FALLBACK_FONT', defaultValue: 'Roboto');

TextStyle? _fill(TextStyle? s) => s?.copyWith(
      fontFamily: s.fontFamily ?? kFallbackFont,
      fontFamilyFallback: s.fontFamilyFallback ?? _glyphFallback,
    );

TextTheme _fillTheme(TextTheme t) => TextTheme(
      displayLarge: _fill(t.displayLarge),
      displayMedium: _fill(t.displayMedium),
      displaySmall: _fill(t.displaySmall),
      headlineLarge: _fill(t.headlineLarge),
      headlineMedium: _fill(t.headlineMedium),
      headlineSmall: _fill(t.headlineSmall),
      titleLarge: _fill(t.titleLarge),
      titleMedium: _fill(t.titleMedium),
      titleSmall: _fill(t.titleSmall),
      bodyLarge: _fill(t.bodyLarge),
      bodyMedium: _fill(t.bodyMedium),
      bodySmall: _fill(t.bodySmall),
      labelLarge: _fill(t.labelLarge),
      labelMedium: _fill(t.labelMedium),
      labelSmall: _fill(t.labelSmall),
    );

/// The app's real theme (buildAppTheme, as app.dart uses), with only the
/// text styles that lack a fontFamily pointed at [kFallbackFont].
ThemeData previewTheme() {
  final t = buildAppTheme();
  return t.copyWith(
    textTheme: _fillTheme(t.textTheme),
    primaryTextTheme: _fillTheme(t.primaryTextTheme),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Platform plugins
// ─────────────────────────────────────────────────────────────────────────────

/// In-memory flutter_secure_storage. Empty by default: no token, so the chat
/// WebSocket never connects and Dio sends no Authorization header.
final Map<String, String> fakeSecureStorage = {};

Map<String, Object?> _position() => {
      'latitude': 15.4589,
      'longitude': 75.0078,
      'timestamp': DateTime(2026, 10, 6, 9, 41).millisecondsSinceEpoch,
      'accuracy': 6.0,
      'altitude': 750.0,
      'altitude_accuracy': 3.0,
      'heading': 0.0,
      'heading_accuracy': 0.0,
      'speed': 0.0,
      'speed_accuracy': 0.0,
      'floor': null,
      'is_mocked': false,
    };

Future<Object?> _pluginAnswer(String channel, MethodCall call) async {
  final args = call.arguments;
  switch (channel) {
    case 'plugins.it_nomads.com/flutter_secure_storage':
      final key = args is Map ? args['key'] as String? : null;
      switch (call.method) {
        case 'read':
          return key == null ? null : fakeSecureStorage[key];
        case 'readAll':
          return Map<String, String>.from(fakeSecureStorage);
        case 'containsKey':
          return key != null && fakeSecureStorage.containsKey(key);
        case 'write':
          if (key != null) fakeSecureStorage[key] = args['value'] as String;
          return null;
        case 'delete':
          fakeSecureStorage.remove(key);
          return null;
        case 'deleteAll':
          fakeSecureStorage.clear();
          return null;
      }
      return null;
    case 'flutter.baseflow.com/geolocator':
      switch (call.method) {
        case 'checkPermission':
        case 'requestPermission':
          return 3; // LocationPermission.always
        case 'isLocationServiceEnabled':
          return true;
        case 'getLocationAccuracy':
          return 1; // precise
        case 'getCurrentPosition':
        case 'getLastKnownPosition':
          return _position();
      }
      return null;
    case 'flutter.baseflow.com/permissions/methods':
      switch (call.method) {
        case 'checkPermissionStatus':
          return 1; // granted
        case 'checkServiceStatus':
          return 1; // enabled
        case 'requestPermissions':
          final list = (args as List?) ?? const [];
          return {for (final p in list) p: 1};
        case 'shouldShowRequestPermissionRationale':
          return false;
      }
      return null;
    case 'dev.fluttercommunity.plus/package_info':
      return {
        'appName': 'Nava360',
        'packageName': 'in.nlpl.nava360',
        'version': '0.1.39',
        'buildNumber': '39',
        'buildSignature': '',
        'installerStore': null,
      };
    case 'plugins.flutter.io/local_auth':
      switch (call.method) {
        case 'getAvailableBiometrics':
          return <String>[];
        case 'isDeviceSupported':
        case 'deviceSupportsBiometrics':
          return false;
      }
      return false;
    case 'plugins.flutter.io/path_provider':
      return Directory.systemTemp.path;
    case 'flutter.baseflow.com/geocoding':
      if (call.method == 'placemarkFromCoordinates') {
        return [
          {
            'name': 'Vidyagiri',
            'street': 'PB Road',
            'isoCountryCode': 'IN',
            'country': 'India',
            'postalCode': '580004',
            'administrativeArea': 'Karnataka',
            'subAdministrativeArea': 'Dharwad',
            'locality': 'Dharwad',
            'subLocality': 'Vidyagiri',
            'thoroughfare': 'PB Road',
            'subThoroughfare': '',
          }
        ];
      }
      return null;
    case 'app/secure_screen':
    case 'app/battery':
      return true;
  }
  return null;
}

const List<String> _mockedChannels = [
  'plugins.it_nomads.com/flutter_secure_storage',
  'flutter.baseflow.com/geolocator',
  'flutter.baseflow.com/geolocator_updates',
  'flutter.baseflow.com/geolocator_service_updates',
  'flutter.baseflow.com/permissions/methods',
  'flutter.baseflow.com/geocoding',
  'dev.fluttercommunity.plus/package_info',
  'dev.fluttercommunity.plus/device_info',
  'dev.fluttercommunity.plus/share',
  'plugins.flutter.io/local_auth',
  'plugins.flutter.io/firebase_messaging',
  'plugins.flutter.io/firebase_core',
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/path_provider',
  'plugins.flutter.io/image_picker',
  'dexterous.com/flutter/local_notifications',
  'flutter_foreground_task/methods',
  'de.ffuf.in_app_update/methods',
  'fman.smart_auth',
  'plugin.csdcorp.com/speech_to_text',
  'flutter_tts',
  'xyz.luan/audioplayers',
  'xyz.luan/audioplayers.global',
  'com.llfbandit.record/messages',
  'miguelruivo.flutter.plugins.filepicker',
  'open_file',
  'net.nfet.printing',
  'app/downloads',
  'app/secure_screen',
  'app/device_identity',
  'app/battery',
];

/// Reverse geocoder: check-in coordinates read as "Vidyagiri, Dharwad".
class _FakeGeocoding extends GeocodingPlatform {
  @override
  Future<List<Placemark>> placemarkFromCoordinates(
          double latitude, double longitude) async =>
      const [
        Placemark(
          name: 'Vidyagiri',
          street: 'PB Road',
          isoCountryCode: 'IN',
          country: 'India',
          postalCode: '580004',
          administrativeArea: 'Karnataka',
          subAdministrativeArea: 'Dharwad',
          locality: 'Dharwad',
          subLocality: 'Vidyagiri',
          thoroughfare: 'PB Road',
          subThoroughfare: '',
        )
      ];
}

/// Answers the method channels screens touch on first render so nothing
/// throws MissingPluginException.
void installPluginMocks() {
  GeocodingPlatform.instance = _FakeGeocoding();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final ch in _mockedChannels) {
    messenger.setMockMethodCallHandler(
      MethodChannel(ch),
      (call) => _pluginAnswer(ch, call),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fake backend
// ─────────────────────────────────────────────────────────────────────────────

/// Replaces the shared Dio's adapter with a fixture router (fixtures.dart)
/// and drops the debug LogInterceptor. Returns the router so a test can add
/// or override routes (later registrations win).
FakeApi installFakeApi() {
  final api = FakeApi();
  registerDefaultFixtures(api);
  final dio = ApiClient.instance.raw;
  dio.httpClientAdapter = api;
  // Never decode on a background isolate (that would hang under FakeAsync).
  dio.transformer = FusedTransformer(contentLengthIsolateThreshold: -1);
  dio.interceptors.removeWhere((i) => i is LogInterceptor);
  return api;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Router
// ─────────────────────────────────────────────────────────────────────────────

typedef PageBuilder = Widget Function(BuildContext context, GoRouterState s);

/// Shell paths registered under the ShellRoute (as app.dart does). Paths a
/// test doesn't provide render a small stub so the shell still works.
const List<String> kShellPaths = [
  '/home',
  '/attendance',
  '/leaves',
  '/tasks',
  '/chats',
  '/team',
  '/performance',
  '/hrms',
  '/payroll',
  '/more',
];

class PreviewStub extends StatelessWidget {
  const PreviewStub(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Text('stub: $label')),
      );
}

/// Builds a GoRouter mirroring app.dart's layout: [shell] (e.g.
/// `(child) => HomeShell(child: child)`) wraps [shellPages] for every
/// [kShellPaths] entry; [pages] are top-level (full-screen) routes.
GoRouter previewRouter({
  required String initialLocation,
  Widget Function(Widget child)? shell,
  Map<String, PageBuilder> shellPages = const {},
  Map<String, PageBuilder> pages = const {},
}) {
  final top = <RouteBase>[
    for (final e in pages.entries)
      GoRoute(path: e.key, builder: e.value),
  ];
  final shellRoutes = <RouteBase>[
    for (final p in kShellPaths)
      GoRoute(
        path: p,
        builder: shellPages[p] ?? (_, __) => PreviewStub(p),
      ),
  ];
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ...top,
      if (shell != null)
        ShellRoute(
          builder: (_, __, child) => shell(child),
          routes: shellRoutes,
        )
      else
        ...shellRoutes,
    ],
    errorBuilder: (_, s) => PreviewStub('no route ${s.uri}'),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pump + snapshot
// ─────────────────────────────────────────────────────────────────────────────

/// Sets the phone frame, mounts the app (ProviderScope + MaterialApp.router
/// with the real theme) and lets the fake network settle.
Future<void> pumpPreview(
  WidgetTester tester, {
  required GoRouter router,
  List<Override> overrides = const [],
  AuthUser? user = kPreviewUser,
  Size size = kPhone,
}) async {
  setFrame(tester, size);
  _captureErrors();
  // Real (soft) shadows — the test binding disables them by default; restored
  // in [finishPreview] because the binding asserts it at the end of a test.
  debugDisableShadows = false;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...baseOverrides(user: user), ...overrides],
      child: MaterialApp.router(
        title: 'Nava360',
        debugShowCheckedModeBanner: false,
        theme: previewTheme(),
        routerConfig: router,
        // Same root wrapper as app.dart (narrow-phone text density).
        builder: (context, child) =>
            ProTextDensity(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await settle(tester);
}

void setFrame(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * kDpr;
  tester.view.devicePixelRatio = kDpr;
  tester.view.padding = const FakeViewPadding(top: kStatusBar * kDpr);
  tester.view.viewPadding = const FakeViewPadding(top: kStatusBar * kDpr);
}

/// Pumps bounded frames (never pumpAndSettle — Pro widgets pulse forever) so
/// fake requests resolve, futures complete and entrance animations finish.
Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
  for (var r = 0; r < rounds; r++) {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(seconds: 1));
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _precacheImages(tester);
}

/// Asset/memory images decode on real async I/O, which FakeAsync never runs:
/// decode every on-screen Image under runAsync so logos aren't blank.
Future<void> _precacheImages(WidgetTester tester) async {
  final elements = find.byType(Image).evaluate().toList();
  final pending = <(ImageProvider, Element)>[];
  for (final e in elements) {
    final img = (e.widget as Image).image;
    if (img is NetworkImage) continue; // tests answer HTTP with 400
    pending.add((img, e));
  }
  if (pending.isEmpty) return;
  await tester.runAsync(() async {
    for (final (img, e) in pending) {
      try {
        await precacheImage(img, e)
            .timeout(const Duration(seconds: 3), onTimeout: () {});
      } catch (_) {}
    }
  });
  // Let image-load fades / relayouts finish.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

/// Compares/writes test/pro_preview/goldens/<name>.png.
Future<void> snap(WidgetTester tester, String name) async {
  // Hand error reporting back to the test binding while matching, so a
  // golden mismatch (when run without --update-goldens) fails normally.
  _releaseErrors();
  await expectLater(
    find.byType(MaterialApp).first,
    matchesGoldenFile('goldens/$name.png'),
  );
  _captureErrors(clear: false);
}

/// testWidgets wrapper: whatever happens in [body], framework state the
/// harness changed (error handler, shadows, view size) is restored before
/// the binding verifies its invariants.
void previewTest(String description, Future<void> Function(WidgetTester) body,
    {bool skip = false}) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      _releaseErrors();
      debugDisableShadows = true;
    }
  }, skip: skip || !_previewsEnabled);
}

/// Previews show live clocks and dates, so they never match pixel-for-pixel
/// on a later run. Keep them out of a plain `flutter test`: they run only when
/// regenerating (--update-goldens) or when asked for explicitly
/// (--dart-define=PRO_PREVIEW=true, a visual-regression check).
bool get _previewsEnabled =>
    autoUpdateGoldenFiles || const bool.fromEnvironment('PRO_PREVIEW');

/// Re-lays out the current tree in the tall frame and snaps `<name>_tall`.
Future<void> snapTall(WidgetTester tester, String name) async {
  setFrame(tester, kPhoneTall);
  await settle(tester, rounds: 1);
  await snap(tester, '${name}_tall');
  setFrame(tester, kPhone);
  await settle(tester, rounds: 1);
}

/// Unmounts the app and runs out pending timers so the test ends clean.
Future<void> finishPreview(WidgetTester tester) async {
  await _primeSlideToConfirm(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(minutes: 1));
  }
  debugDisableShadows = true;
  _releaseErrors();
  tester.view.reset();
}

// Framework errors (RenderFlex overflow, failed network images, …) are logged
// as one line each instead of failing the test — the preview still renders
// (overflow stripes included), which is exactly what a reviewer wants to see.
FlutterExceptionHandler? _prevOnError;
final List<String> previewErrors = [];

/// Print the app-frame stack lines of non-overflow errors.
bool verboseErrors = true;

void _captureErrors({bool clear = true}) {
  if (clear) previewErrors.clear();
  _prevOnError ??= FlutterError.onError;
  FlutterError.onError = (details) {
    final first = details.exceptionAsString().split('\n').first;
    previewErrors.add(first);
    debugPrint('[pro_preview] FlutterError: $first'
        '${details.context != null ? ' (${details.context})' : ''}');
    if (first.contains('overflowed')) {
      // Name the widget (file:line) that overflowed.
      final lines = details.toString().split('\n');
      final i = lines.indexWhere((l) => l.contains('error-causing widget'));
      if (i >= 0 && i + 1 < lines.length) {
        debugPrint('  at ${lines.skip(i + 1).take(2).map((l) => l.trim()).join(' ')}');
      }
    } else if (verboseErrors) {
      final stack = details.stack?.toString().split('\n') ?? const [];
      debugPrint('  ${stack.where((l) => l.contains('package:nava360') || l.contains('pro_preview')).take(12).join('\n  ')}');
    }
  };
}

void _releaseErrors() {
  if (_prevOnError != null) {
    FlutterError.onError = _prevOnError;
    _prevOnError = null;
  }
}

/// Workaround for lib/core/widgets.dart `_SlideToConfirmState`: its
/// `late final _back` AnimationController is first created inside dispose()
/// when the slider was never dragged, which throws ("deactivated widget's
/// ancestor") and aborts the unmount — leaving e.g. the dashboard's 1 s clock
/// timer running. A short drag (past touch slop, well under the 90% confirm threshold) creates
/// the controller up front so the tree unmounts cleanly.
Future<void> _primeSlideToConfirm(WidgetTester tester) async {
  // Close drawers / pop sheets first so the slider can receive the drag.
  for (final s in tester.stateList<ScaffoldState>(find.byType(Scaffold))) {
    if (s.isDrawerOpen) s.closeDrawer();
    if (s.isEndDrawerOpen) s.closeEndDrawer();
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final slides = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_SlideToConfirm');
  final n = slides.evaluate().length;
  for (var i = 0; i < n; i++) {
    final knob = find.descendant(
      of: slides.at(i),
      matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onHorizontalDragEnd != null),
    );
    if (knob.evaluate().isEmpty) continue;
    await tester.drag(knob.first, const Offset(40, 0), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
  }
}

/// The current test's fake backend (set up fresh before every test by
/// [previewSetUpAll]); tests may add or override routes on it before pumping.
late FakeApi currentApi;

/// One-time setup for a preview test file: fonts, plugin mocks, fake API.
void previewSetUpAll() {
  setUpAll(() async {
    await loadPreviewFonts();
  });
  setUp(() {
    installPluginMocks();
    fakeSecureStorage.clear();
    currentApi = installFakeApi();
  });
  tearDown(() {
    final misses = currentApi.unmatched;
    if (misses.isNotEmpty) {
      debugPrint('[pro_preview] UNMATCHED requests (defaults served):\n  '
          '${misses.join('\n  ')}');
    }
  });
}

/// Taps the first visible match of any of [finders] (tried in order) and
/// lets the UI settle. Returns false (and logs) when nothing matched.
Future<bool> tapAny(WidgetTester tester, List<Finder> finders,
    {int rounds = 2}) async {
  for (final f in finders) {
    if (f.evaluate().isNotEmpty) {
      await tester.tap(f.first, warnIfMissed: false);
      await settle(tester, rounds: rounds);
      return true;
    }
  }
  debugPrint('[pro_preview] tapAny: nothing matched $finders');
  return false;
}

/// Mounts [location] inside [shell] (e.g. `(c) => HomeShell(child: c)`)
/// with [shellPages] as the shell's tab pages, like app.dart's ShellRoute.
Future<void> pumpShellTab(
  WidgetTester tester, {
  required String location,
  required Widget Function(Widget child) shell,
  required Map<String, PageBuilder> shellPages,
  Map<String, PageBuilder> pages = const {},
}) =>
    pumpPreview(tester,
        router: previewRouter(
          initialLocation: location,
          shell: shell,
          shellPages: shellPages,
          pages: pages,
        ));
