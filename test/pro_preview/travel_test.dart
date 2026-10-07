// /travel/claims (TravelClaimsScreen).
import 'package:nava360/features/travel/travel_claims_screen.dart';

import 'harness.dart';

void main() {
  previewSetUpAll();

  previewTest('travel claims', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/travel/claims',
            pages: {'/travel/claims': (_, __) => const TravelClaimsScreen()}));
    await snap(tester, 'travel_claims');
    await snapTall(tester, 'travel_claims');
    await finishPreview(tester);
  });
}
