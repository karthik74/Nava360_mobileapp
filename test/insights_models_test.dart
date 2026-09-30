import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/core/branding.dart';
import 'package:nava360/features/insights/insights_models.dart';
import 'package:nava360/features/insights/opening_insights_trigger.dart';

void main() {
  group('OpeningInsights.fromJson', () {
    test('parses the full contract', () {
      final o = OpeningInsights.fromJson({
        'month': '2026-09',
        'asOf': '2026-09-29',
        'scope': {'level': 'BRANCH', 'label': 'Dharwad Branch'},
        'greetingName': 'Karthik',
        'disbursement': {'accounts': 42, 'connected': true},
        'ftod': {
          'accounts': 120,
          'collected': 90,
          'collectedPct': 75,
          'pending': 20,
          'partial': 10,
          'paidLate': 15,
          'paidOnTime': 75,
        },
        'ptp': {
          'total': 30,
          'open': 12,
          'kept': 10,
          'broken': 5,
          'cancelled': 3
        },
        'yesterday': {
          'date': '2026-09-29',
          'due': 12,
          'collected': 9,
          'pending': 3,
        },
      });
      expect(o.month, '2026-09');
      expect(o.asOf, '2026-09-29');
      expect(o.scope.level, InsightsScopeLevel.branch);
      expect(o.scope.label, 'Dharwad Branch');
      expect(o.greetingName, 'Karthik');
      expect(o.disbursement.accounts, 42);
      expect(o.disbursement.connected, isTrue);
      expect(o.ftod.accounts, 120);
      expect(o.ftod.collected, 90);
      expect(o.ftod.collectedPct, 75);
      expect(o.ftod.pending, 20);
      expect(o.ftod.partial, 10);
      expect(o.ftod.paidLate, 15);
      expect(o.ftod.paidOnTime, 75);
      expect(o.ptp.total, 30);
      expect(o.ptp.open, 12);
      expect(o.ptp.kept, 10);
      expect(o.ptp.broken, 5);
      expect(o.ptp.cancelled, 3);
      expect(o.ptp.barTotal, 27);
      expect(o.yesterday, isNotNull);
      expect(o.yesterday!.date, DateTime(2026, 9, 29));
      expect(o.yesterday!.due, 12);
      expect(o.yesterday!.collected, 9);
      expect(o.yesterday!.pending, 3);
    });

    test('ints arriving as doubles or strings are accepted', () {
      final o = OpeningInsights.fromJson({
        'disbursement': {'accounts': 42.0},
        'ftod': {'accounts': 120.0, 'collected': '90', 'collectedPct': 75.5},
        'ptp': {'total': 30.0, 'open': 12.0, 'kept': '10', 'broken': 5.0},
      });
      expect(o.disbursement.accounts, 42);
      expect(o.ftod.accounts, 120);
      expect(o.ftod.collected, 90);
      expect(o.ftod.collectedPct, 75.5);
      expect(o.ptp.total, 30);
      expect(o.ptp.kept, 10);
    });

    test('missing keys and a non-map payload read as zeros / blanks', () {
      for (final raw in [<String, dynamic>{}, null, 'oops', 7]) {
        final o = OpeningInsights.fromJson(raw);
        expect(o.month, '');
        expect(o.greetingName, '');
        expect(o.scope.level, InsightsScopeLevel.fo);
        expect(o.scope.label, '');
        expect(o.disbursement.accounts, 0);
        expect(o.disbursement.connected, isFalse); // no feed at all
        expect(o.ftod.accounts, 0);
        expect(o.ftod.collectedPct, 0);
        expect(o.ptp.total, 0);
        expect(o.ptp.barTotal, 0);
        expect(o.yesterday, isNull); // older backend: no FTD column data
      }
    });

    test('yesterday parses defensively', () {
      final o = OpeningInsights.fromJson({
        'yesterday': {'due': '7', 'collected': 4.0},
      });
      expect(o.yesterday!.date, isNull);
      expect(o.yesterday!.due, 7);
      expect(o.yesterday!.collected, 4);
      expect(o.yesterday!.pending, 0);

      expect(OpeningInsights.fromJson({'yesterday': 'oops'}).yesterday, isNull);
      expect(OpeningInsights.fromJson({'yesterday': null}).yesterday, isNull);

      DateTime? date(Object? v) => YesterdayInsight.fromJson({'date': v}).date;
      // Only the calendar day is read — a UTC suffix can't shift it.
      expect(date('2026-09-29T00:00:00Z'), DateTime(2026, 9, 29));
      expect(date('2026-1-5'), DateTime(2026, 1, 5));
      expect(date('2026-13-01'), isNull);
      expect(date('29/09/2026'), isNull);
      expect(date(''), isNull);
      expect(date(null), isNull);
    });

    test('disbursement is connected unless it says connected:false', () {
      expect(DisbursementInsight.fromJson({'accounts': 3}).connected, isTrue);
      expect(
        DisbursementInsight.fromJson({'accounts': 0, 'connected': false})
            .connected,
        isFalse,
      );
      expect(DisbursementInsight.fromJson(null).connected, isFalse);
    });

    test('collectedPct falls back to collected/accounts and is clamped', () {
      expect(FtodInsight.fromJson({'accounts': 8, 'collected': 2}).collectedPct,
          25);
      expect(FtodInsight.fromJson({'accounts': 0, 'collected': 0}).collectedPct,
          0);
      expect(FtodInsight.fromJson({'collectedPct': 140}).collectedPct, 100);
      expect(FtodInsight.fromJson({'collectedPct': -5}).collectedPct, 0);
    });

    test('scope levels parse case-insensitively, unknown → FO', () {
      expect(InsightsScopeLevel.parse('area'), InsightsScopeLevel.area);
      expect(InsightsScopeLevel.parse('DIVISION'), InsightsScopeLevel.division);
      expect(InsightsScopeLevel.parse('Region'), InsightsScopeLevel.region);
      expect(InsightsScopeLevel.parse('ALL'), InsightsScopeLevel.all);
      expect(InsightsScopeLevel.parse('FO'), InsightsScopeLevel.fo);
      expect(InsightsScopeLevel.parse(null), InsightsScopeLevel.fo);
      expect(InsightsScopeLevel.parse('???'), InsightsScopeLevel.fo);
    });
  });

  group('formatting', () {
    test('counts use Indian digit grouping, no decimals', () {
      expect(insightsCount(0), '0');
      expect(insightsCount(null), '0');
      expect(insightsCount(999), '999');
      expect(insightsCount(1000), '1,000');
      expect(insightsCount(123456), '1,23,456');
      expect(insightsCount(12345678), '1,23,45,678');
      expect(insightsCount(41.6), '42'); // mid count-up values round
    });

    test('short date for the FTD heading', () {
      expect(insightsShortDate(DateTime(2026, 9, 29)), '29 Sep');
      expect(insightsShortDate(DateTime(2027, 1, 1)), '1 Jan');
      expect(insightsShortDate(DateTime(2026, 12, 31)), '31 Dec');
    });
  });

  group('trigger rules', () {
    test('FEATURE_OPENING_INSIGHTS is opt-in: only an explicit true enables',
        () {
      expect(openingInsightsEnabled(const Branding()), isFalse);
      expect(
        openingInsightsEnabled(
          const Branding(features: {'FEATURE_OPENING_INSIGHTS': false}),
        ),
        isFalse,
      );
      expect(
        openingInsightsEnabled(
          const Branding(features: {'FEATURE_OPENING_INSIGHTS': true}),
        ),
        isTrue,
      );
    });

    bool resume({
      Duration away = const Duration(minutes: 6),
      bool signedIn = true,
      bool enabled = true,
      bool showing = false,
      String location = '/home',
      bool notified = false,
    }) =>
        shouldShowOpeningInsightsOnResume(
          away: away,
          signedIn: signedIn,
          enabled: enabled,
          showing: showing,
          location: location,
          notificationSinceBackground: notified,
        );

    test('resume shows after ≥ 5 min away on an ordinary signed-in screen', () {
      expect(resume(), isTrue);
      expect(resume(away: const Duration(minutes: 5)), isTrue);
      expect(resume(location: '/ptp'), isTrue);
    });

    test('resume never shows when it should not', () {
      expect(resume(away: const Duration(minutes: 4, seconds: 59)), isFalse);
      expect(resume(signedIn: false), isFalse);
      expect(resume(enabled: false), isFalse);
      expect(resume(showing: true), isFalse);
      expect(resume(notified: true), isFalse);
      for (final loc in [
        '/login',
        '/first-login',
        '/welcome',
        '/splash',
        '/forgot-password',
        '/opening-insights',
        '',
      ]) {
        expect(resume(location: loc), isFalse, reason: loc);
      }
    });
  });
}
