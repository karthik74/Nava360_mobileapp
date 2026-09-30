import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding.dart';
import '../auth/auth_controller.dart';

/// Route of the "opening insights" intro.
const kOpeningInsightsRoute = '/opening-insights';

/// Branding feature flag. Opt-in: the intro shows only when the backend
/// publishes it as exactly `true` — a missing key (older backend) means OFF,
/// same as `featureFlagDefaultOff` in mobile_menu_config.dart.
const kOpeningInsightsFlag = 'FEATURE_OPENING_INSIGHTS';

/// Returning to the app after at least this long in the background replays
/// the intro.
const kOpeningInsightsResumeAfter = Duration(minutes: 5);

/// Demo/QA override: `--dart-define=FORCE_OPENING_INSIGHTS=true` treats the
/// flag as on regardless of the deployment's branding.
const _kForceOn = bool.fromEnvironment('FORCE_OPENING_INSIGHTS');

/// A notification tap this recent means the app was opened for that
/// notification — skip the intro and let the tap land.
const _kNotificationGrace = Duration(seconds: 30);

/// Screens the intro must never cover (signed-out flows and itself).
const _kNoIntroRoutes = {
  '/splash',
  '/welcome',
  '/login',
  '/first-login',
  '/forgot-password',
  kOpeningInsightsRoute,
};

bool openingInsightsEnabled(Branding b) =>
    _kForceOn || b.features[kOpeningInsightsFlag] == true;

/// Pure resume rule, kept separate so it can be unit-tested.
bool shouldShowOpeningInsightsOnResume({
  required Duration away,
  required bool signedIn,
  required bool enabled,
  required bool showing,
  required String location,
  required bool notificationSinceBackground,
}) {
  if (!enabled || !signedIn || showing || notificationSinceBackground) {
    return false;
  }
  if (away < kOpeningInsightsResumeAfter) return false;
  if (location.isEmpty || _kNoIntroRoutes.contains(location)) return false;
  return true;
}

/// Decides when the opening-insights intro is shown:
///   (a) right after a successful login and (b) on a cold start with a
///       restored session — both via [entryLocation], called by the router
///       redirect at the moment a signed-in user leaves /splash or /login;
///   (c) when the app returns to the foreground after ≥ 5 minutes in the
///       background — pushed on top of wherever the user was, and popped
///       back there when it ends, so no in-progress screen is lost.
///
/// Notification taps are funnelled through [openFromNotification] so a tap
/// always wins: it suppresses the intro, or ends a running one and then opens
/// the tapped route. Wired once at the app root (see app.dart).
class OpeningInsightsTrigger {
  OpeningInsightsTrigger(this._ref) {
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  final Ref _ref;
  GoRouter? _router;
  AppLifecycleListener? _lifecycle;
  Timer? _resumeCheck;

  DateTime? _backgroundedAt;
  DateTime? _notificationAt;

  /// A notification tapped while the session was still being restored (cold
  /// start). The router would bounce a push made then to /splash and lose it,
  /// so it is held here and opened once the user lands on /home.
  String? _bootRoute;

  /// Set by the live intro screen; ends it and then opens the given route.
  void Function(String route)? _interrupt;

  void attachRouter(GoRouter router) => _router = router;

  bool get enabled => openingInsightsEnabled(_ref.read(brandingProvider));

  /// True while an intro screen is on screen.
  bool get showing => _interrupt != null;

  /// Called by the intro screen while it is mounted.
  void register(void Function(String route) interrupt) => _interrupt = interrupt;

  void unregister(void Function(String route) interrupt) {
    // `==`, not identical: method tear-offs are equal but not identical.
    if (_interrupt == interrupt) _interrupt = null;
  }

  bool get _recentNotification {
    final at = _notificationAt;
    return at != null && DateTime.now().difference(at) < _kNotificationGrace;
  }

  /// Router-redirect hook for a signed-in user sitting on /splash, /login or
  /// /welcome — i.e. a fresh login or a restored session. Returns the
  /// location to land on: the intro, or /home as before.
  String entryLocation() {
    final boot = _bootRoute;
    if (boot != null) {
      _bootRoute = null;
      // Land on home first so Back from the notification's screen returns
      // there, then open the tapped route once home is in place.
      _afterFrame(() => _router?.push(boot));
      return '/home';
    }
    if (!enabled || showing || _recentNotification) return '/home';
    return kOpeningInsightsRoute;
  }

  /// Every push/local-notification tap goes through here instead of calling
  /// `router.push` directly.
  void openFromNotification(String route) {
    _notificationAt = DateTime.now();
    if (_ref.read(authControllerProvider).isLoading) {
      _bootRoute = route;
      return;
    }
    final interrupt = _interrupt;
    if (interrupt != null) {
      interrupt(route);
      return;
    }
    _router?.push(route);
  }

  /// Signed out (or the restore failed): a held cold-start tap is stale.
  void onSignedOut() => _bootRoute = null;

  void _onLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _backgroundedAt ??= DateTime.now();
        _resumeCheck?.cancel();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since == null) return;
        final away = DateTime.now().difference(since);
        // Give a notification tap that reopened the app a moment to arrive
        // (it can land just after `resumed`) before deciding.
        _resumeCheck?.cancel();
        _resumeCheck = Timer(
          const Duration(milliseconds: 700),
          () => _maybeShowOnResume(since, away),
        );
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _maybeShowOnResume(DateTime since, Duration away) {
    final router = _router;
    if (router == null) return;
    final tappedAt = _notificationAt;
    final show = shouldShowOpeningInsightsOnResume(
      away: away,
      signedIn: _ref.read(authControllerProvider).asData?.value != null,
      enabled: enabled,
      showing: showing,
      location: _location(router),
      notificationSinceBackground:
          tappedAt != null && !tappedAt.isBefore(since),
    );
    if (show) router.push(kOpeningInsightsRoute);
  }

  static String _location(GoRouter router) {
    try {
      return router.state.uri.path;
    } catch (_) {
      return ''; // no configuration yet
    }
  }

  static void _afterFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void dispose() {
    _resumeCheck?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}

final openingInsightsTriggerProvider = Provider<OpeningInsightsTrigger>((ref) {
  final trigger = OpeningInsightsTrigger(ref);
  ref.listen<AsyncValue<dynamic>>(authControllerProvider, (_, next) {
    if (!next.isLoading && next.asData?.value == null) trigger.onSignedOut();
  });
  ref.onDispose(trigger.dispose);
  return trigger;
});
