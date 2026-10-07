// /profile (ProfileScreen, full-screen route).
import 'package:nava360/features/profile/profile_screen.dart';

import 'package:nava360/features/profile/business_card_screen.dart';

import 'harness.dart';

void main() {
  previewSetUpAll();

  previewTest('profile', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/profile',
            pages: {'/profile': (_, __) => const ProfileScreen()}));
    await snap(tester, 'profile');
    await snapTall(tester, 'profile');
    await finishPreview(tester);
  });

  previewTest('business card', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/business-card',
            pages: {'/business-card': (_, __) => const BusinessCardScreen()}));
    await snap(tester, 'business_card');
    await snapTall(tester, 'business_card');
    await finishPreview(tester);
  });
}
