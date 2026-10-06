import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nava360/core/api_client.dart';
import 'package:nava360/core/branding.dart';
import 'package:nava360/features/auth/auth_controller.dart';
import 'package:nava360/features/auth/auth_models.dart';
import 'package:nava360/features/auth/auth_repository.dart';
import 'package:nava360/features/insights/insights_models.dart';
import 'package:nava360/features/insights/insights_repository.dart';
import 'package:nava360/features/insights/opening_insights_screen.dart';
import 'package:nava360/features/insights/opening_insights_trigger.dart';

class _Branding extends BrandingNotifier {
  _Branding(this._b);
  final Branding _b;
  @override
  Branding build() => _b;
}

/// Signed-out restore without touching secure storage.
class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(ApiClient.instance);
  @override
  Future<AuthUser?> restore() async => null;
}

class _FakeInsightsRepo extends InsightsRepository {
  _FakeInsightsRepo(this._answer) : super(ApiClient.instance);
  final Future<OpeningInsights> Function() _answer;
  int calls = 0;

  @override
  Future<OpeningInsights> opening({String? month}) {
    calls++;
    return _answer();
  }
}

final _sample = OpeningInsights.fromJson({
  'month': '2026-09',
  'asOf': '2026-09-30',
  'scope': {'level': 'BRANCH', 'label': 'Dharwad Branch'},
  'disbursement': {'accounts': 123456, 'connected': true},
  'ftod': {'accounts': 120, 'collected': 90, 'pending': 20, 'partial': 10},
  'ptp': {'total': 30, 'open': 12, 'kept': 10, 'broken': 5, 'cancelled': 3},
  'yesterday': {'date': '2026-09-28', 'due': 12, 'collected': 9, 'pending': 3},
  'mtd': {
    'date': '2026-09-30',
    'disbursement': 123456,
    'ftod': 30,
    'ftodDue': 120,
    'ftodCollected': 90,
    'ptp': 25,
  },
  'ftd': {
    'date': '2026-09-28',
    'disbursement': null, // the feed has no daily disbursement
    'ftod': 12,
    'ftodDue': 130,
    'ftodCollected': 118,
    'ptp': 4,
  },
});

const _ctaKey = ValueKey('opening-insights-cta');

/// Every final value of [_sample], as the cards show them (FTD disbursement is "—").
const _finalValues = ['1,23,456', '30', '25', '12', '4'];

void main() {
  late List<String?> finished;
  late ProviderContainer container;

  Future<void> pumpIntro(
    WidgetTester tester,
    _FakeInsightsRepo repo, {
    bool disableAnimations = false,
  }) async {
    // A phone-sized surface (390 × 844) so the stage lays out like on a device.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    finished = [];
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
      insightsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              disableAnimations: disableAnimations,
            ),
            child: OpeningInsightsScreen(
              now: () => DateTime(2026, 9, 30, 9, 30),
              onFinish: finished.add,
              // Don't wait on the WebP's first frame (it never decodes here).
              characterWait: Duration.zero,
            ),
          ),
        ),
      ),
    );
  }

  /// Advances the intro's timeline to [seconds] from its start (the first
  /// frame after pumpWidget), given [at] seconds already pumped.
  Future<double> pumpTo(WidgetTester tester, double at, double seconds) async {
    await tester.pump(Duration(milliseconds: ((seconds - at) * 1000).round()));
    return seconds;
  }

  /// Combined opacity of [f]'s Opacity / AnimatedOpacity (target) ancestors.
  double opacityOf(WidgetTester tester, Finder f) {
    var o = 1.0;
    for (final w in tester.widgetList(find.ancestor(
        of: f,
        matching: find
            .byWidgetPredicate((w) => w is Opacity || w is AnimatedOpacity)))) {
      o *= w is Opacity ? w.opacity : (w as AnimatedOpacity).opacity;
    }
    return o;
  }

  bool ctaEnabled(WidgetTester tester) =>
      tester.widget<GestureDetector>(find.byKey(_ctaKey)).onTap != null;

  testWidgets('reveals on the prototype timeline and never leaves by itself',
      (tester) async {
    final repo = _FakeInsightsRepo(() async => _sample);
    await pumpIntro(tester, repo);
    await tester.pump(); // repository future resolves
    expect(repo.calls, 1);

    // FTD (left) comes in first, then MTD (right). FTD uses the API's `ftd.date`.
    var t = await pumpTo(tester, 0, .9);
    expect(opacityOf(tester, find.text('FTD · 28 SEP')), 0);
    t = await pumpTo(tester, t, 1.8); // FTD in at 1.05 + .6
    expect(opacityOf(tester, find.text('FTD · 28 SEP')), 1);
    expect(opacityOf(tester, find.text('MTD')), 0);
    t = await pumpTo(tester, t, 3.4); // MTD in at 2.65 + .6
    expect(opacityOf(tester, find.text('MTD')), 1);
    // FTD heading sits left of MTD.
    expect(tester.getCenter(find.text('FTD · 28 SEP')).dx,
        lessThan(tester.getCenter(find.text('MTD')).dx));

    // Cards are still hidden before 7.35 s.
    t = await pumpTo(tester, t, 7.2);
    expect(opacityOf(tester, find.text('DISBURSEMENT')), 0);
    expect(opacityOf(tester, find.text('PTP')), 0);

    // Mid rise/count-up of the first pair.
    t = await pumpTo(tester, t, 7.6);
    expect(find.text('1,23,456'), findsNothing);

    // All six settled with their final numbers.
    t = await pumpTo(tester, t, 8.6);
    for (final v in _finalValues) {
      expect(find.text(v), findsOneWidget, reason: v);
    }
    // Both columns carry the same three cards.
    expect(find.text('DISBURSEMENT'), findsNWidgets(2));
    expect(find.text('FTOD'), findsNWidgets(2));
    expect(find.text('PTP'), findsNWidgets(2));
    expect(find.text('of 120 due'), findsOneWidget);
    expect(find.text('of 130 due'), findsOneWidget);
    expect(find.text('promises due'), findsNWidgets(2));
    // No daily disbursement: "—", said plainly — not 0.
    expect(find.text('—'), findsOneWidget);
    // Cards follow the headings: FTD (yesterday's "—") left, MTD (1,23,456) right.
    expect(tester.getCenter(find.text('—')).dx,
        lessThan(tester.getCenter(find.text('1,23,456')).dx));
    expect(find.text('not available'), findsOneWidget);
    expect(opacityOf(tester, find.text('PTP')), 1);

    // Well past the 10 s reveal: still here, waiting for the button.
    await pumpTo(tester, t, 20);
    expect(finished, isEmpty);
    expect(find.byKey(_ctaKey), findsOneWidget);
    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('the button is disabled until it is fully in', (tester) async {
    await pumpIntro(tester, _FakeInsightsRepo(() async => _sample));
    await tester.pump();
    var t = await pumpTo(tester, 0, 6.0); // 5.55 + .75 = 6.3
    expect(ctaEnabled(tester), isFalse);
    await tester.tap(find.byKey(_ctaKey), warnIfMissed: false);
    t = await pumpTo(tester, t, 6.2);
    expect(ctaEnabled(tester), isFalse);
    await pumpTo(tester, t, 9);
    expect(finished, isEmpty);
    expect(
        opacityOf(tester, find.text('You’ve got this. Let’s get started.')), 0);
  });

  testWidgets('tapping the button shows the feedback, then leaves',
      (tester) async {
    await pumpIntro(tester, _FakeInsightsRepo(() async => _sample));
    await tester.pump();
    await pumpTo(tester, 0, 6.4);
    expect(ctaEnabled(tester), isTrue);
    await tester.tap(find.byKey(_ctaKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        opacityOf(tester, find.text('You’ve got this. Let’s get started.')), 1);
    expect(finished, isEmpty);

    // Still showing the encouragement just before the 1.1 s beat ends.
    await tester.pump(const Duration(milliseconds: 700));
    expect(finished, isEmpty);

    // 1.1 s beat + the short fade-out.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(finished, [null]);

    await tester.pump(const Duration(seconds: 2));
    expect(finished, [null]); // never twice
  });

  testWidgets('late numbers fill the "—" cards; the button never waits',
      (tester) async {
    final slow = Completer<OpeningInsights>();
    await pumpIntro(tester, _FakeInsightsRepo(() => slow.future));
    await tester.pump();
    var t = await pumpTo(tester, 0, 6.4);
    expect(ctaEnabled(tester), isTrue); // no data, still usable
    // The FTD heading falls back to the device's yesterday.
    expect(find.text('FTD · 29 SEP'), findsOneWidget);

    t = await pumpTo(tester, t, 8.6);
    expect(find.text('—'), findsNWidgets(6));
    expect(find.text('not available'),
        findsNothing); // unknown yet, not "unavailable"

    slow.complete(_sample);
    await tester.pump(); // data arrives
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('1,23,456'), findsNothing); // counting up
    expect(find.text('—'), findsOneWidget); // only FTD disbursement
    await tester.pump(const Duration(milliseconds: 500));
    for (final v in _finalValues) {
      expect(find.text(v), findsOneWidget, reason: v);
    }
    expect(find.text('FTD · 28 SEP'), findsOneWidget);
    expect(finished, isEmpty);
  });

  testWidgets('a failed load keeps "—" and the button still works',
      (tester) async {
    await pumpIntro(
      tester,
      _FakeInsightsRepo(() async => throw ApiException('boom')),
    );
    await tester.pump();
    await pumpTo(tester, 0, 9);
    expect(find.text('—'), findsNWidgets(6));
    await tester.tap(find.byKey(_ctaKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(finished, [null]);
  });

  testWidgets(
      'reduced motion shows the final state at once (older backend: no mtd/ftd)',
      (tester) async {
    final data = OpeningInsights.fromJson({
      'disbursement': {'accounts': 0, 'connected': false},
      'ftod': {'accounts': 4, 'collected': 1, 'pending': 3},
      'ptp': {'total': 2, 'open': 2},
      'yesterday': {'date': '2026-09-29', 'due': 6, 'collected': 5},
    });
    await pumpIntro(
      tester,
      _FakeInsightsRepo(() async => data),
      disableAnimations: true,
    );
    await tester.pump();
    // MTD from the month objects: disbursement not connected, FTOD 3 of 4 due, PTP 2.
    // FTD from `yesterday`: FTOD 0 of 6 due; no disbursement or PTP there.
    expect(find.text('not available'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(3)); // both disbursements + FTD PTP
    expect(find.text('of 4 due'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('of 6 due'), findsOneWidget);
    expect(find.text('0'), findsOneWidget); // yesterday's still-unpaid
    expect(opacityOf(tester, find.text('PTP')), 1);
    expect(opacityOf(tester, find.text('FTD · 29 SEP')), 1);
    expect(ctaEnabled(tester), isTrue);

    await tester.tap(find.byKey(_ctaKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(finished, [null]); // no fade-out when motion is reduced
  });

  testWidgets('Back before the button is in simply leaves', (tester) async {
    await pumpIntro(tester, _FakeInsightsRepo(() async => _sample));
    await tester.pump();
    await pumpTo(tester, 0, 2);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(finished, [null]);
  });

  testWidgets('Back once the button is in acts like tapping it',
      (tester) async {
    await pumpIntro(tester, _FakeInsightsRepo(() async => _sample));
    await tester.pump();
    await pumpTo(tester, 0, 7);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        opacityOf(tester, find.text('You’ve got this. Let’s get started.')), 1);
    expect(finished, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 400));
    expect(finished, [null]);
  });

  testWidgets('a notification tap ends the intro and forwards its route',
      (tester) async {
    await pumpIntro(tester, _FakeInsightsRepo(() async => _sample));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final trigger = container.read(openingInsightsTriggerProvider);
    expect(trigger.showing, isTrue);
    trigger.openFromNotification('/ptp');
    await tester.pump();
    expect(finished, ['/ptp']);
    expect(trigger.showing, isFalse);
  });

  testWidgets('a notification tap during the feedback beat wins at once',
      (tester) async {
    await pumpIntro(tester, _FakeInsightsRepo(() async => _sample));
    await tester.pump();
    await pumpTo(tester, 0, 6.5);
    await tester.tap(find.byKey(_ctaKey));
    await tester.pump(const Duration(milliseconds: 300));
    container.read(openingInsightsTriggerProvider).openFromNotification('/ptp');
    await tester.pump();
    expect(finished, ['/ptp']);
    await tester.pump(const Duration(seconds: 2));
    expect(finished, ['/ptp']); // the beat's own leave is cancelled
  });

  group('default navigation (real GoRouter)', () {
    Future<GoRouter> pumpRouter(WidgetTester tester, String initial) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
          GoRoute(path: '/ptp', builder: (_, __) => const Text('PTP')),
          GoRoute(
            path: kOpeningInsightsRoute,
            builder: (_, __) =>
                const OpeningInsightsScreen(characterWait: Duration.zero),
          ),
        ],
      );
      addTearDown(router.dispose);
      container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        insightsRepositoryProvider
            .overrideWithValue(_FakeInsightsRepo(() async => _sample)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      return router;
    }

    Future<void> tapCtaAndWait(WidgetTester tester) async {
      await tester.tap(find.byKey(_ctaKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    testWidgets('entry (login / cold start) ends on /home', (tester) async {
      final router = await pumpRouter(tester, kOpeningInsightsRoute);
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      expect(router.state.uri.path, kOpeningInsightsRoute); // still waiting
      await tapCtaAndWait(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(router.state.uri.path, '/home');
    });

    testWidgets('resume (pushed) pops back to where the user was',
        (tester) async {
      final router = await pumpRouter(tester, '/ptp');
      router.push(kOpeningInsightsRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 6500));
      await tapCtaAndWait(tester);
      expect(find.text('PTP'), findsOneWidget);
      expect(router.state.uri.path, '/ptp');
      expect(router.canPop(), isFalse);
    });

    testWidgets('a notification tap lands on its route over /home',
        (tester) async {
      final router = await pumpRouter(tester, kOpeningInsightsRoute);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      container
          .read(openingInsightsTriggerProvider)
          .openFromNotification('/ptp');
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('PTP'), findsOneWidget);
      expect(router.state.uri.path, '/ptp');
      router.pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('entry decision (router redirect hook)', () {
    ProviderContainer make(Map<String, bool> features) {
      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        brandingProvider
            .overrideWith(() => _Branding(Branding(features: features))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('flag missing or false → /home as before', (tester) async {
      expect(make({}).read(openingInsightsTriggerProvider).entryLocation(),
          '/home');
      expect(
        make({'FEATURE_OPENING_INSIGHTS': false})
            .read(openingInsightsTriggerProvider)
            .entryLocation(),
        '/home',
      );
    });

    testWidgets('flag true → the intro', (tester) async {
      final c = make({'FEATURE_OPENING_INSIGHTS': true});
      expect(c.read(openingInsightsTriggerProvider).entryLocation(),
          kOpeningInsightsRoute);
    });

    testWidgets('opened by a notification tap → skip the intro',
        (tester) async {
      final c = make({'FEATURE_OPENING_INSIGHTS': true});
      final trigger = c.read(openingInsightsTriggerProvider);
      // Tap arrives while the session is still restoring (cold start).
      expect(c.read(authControllerProvider).isLoading, isTrue);
      trigger.openFromNotification('/ptp');
      expect(trigger.entryLocation(), '/home');
      // The held tap is used once; a later sign-in gets the intro again only
      // after the notification grace window — still suppressed right now.
      expect(trigger.entryLocation(), '/home');
    });
  });
}
