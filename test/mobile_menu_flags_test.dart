import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/core/branding.dart';
import 'package:nava360/core/navigation/mobile_menu_config.dart';

/// PTP / FTOD have no permission gate, only their feature flag — so they must
/// stay hidden when a backend (not yet upgraded, or cached branding) does not
/// publish the key at all. Other flags keep "on unless explicitly false".
void main() {
  tearDown(() => Branding.current = Branding.defaults);

  Set<String> hrmsKeys() => menuFor(MobileModule.hrms, null).map((m) => m.key).toSet();

  test('missing PTP/FTOD keys hide both entries', () {
    Branding.current = Branding.defaults;

    expect(hrmsKeys(), isNot(contains('hrms.ptpFollowups')));
    expect(hrmsKeys(), isNot(contains('hrms.ftodCollections')));
  });

  test('each shows only when the backend publishes it as true', () {
    Branding.current = const Branding(features: {'FEATURE_CRM_PTP': true, 'FEATURE_FTOD': false});

    expect(hrmsKeys(), contains('hrms.ptpFollowups'));
    expect(hrmsKeys(), isNot(contains('hrms.ftodCollections')));
  });

  test('ordinary flags still default on when the key is missing', () {
    Branding.current = Branding.defaults;

    expect(bottomNavTabs(null).map((m) => m.key), contains('hrms.chats'));
  });
}
