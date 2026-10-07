// /profile (ProfileScreen, full-screen route).
import 'package:nava360/features/profile/profile_screen.dart';

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
}
