// /helpdesk (HelpdeskTicketsScreen).
import 'package:nava360/features/helpdesk/helpdesk_tickets_screen.dart';

import 'harness.dart';

void main() {
  previewSetUpAll();

  previewTest('helpdesk tickets', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/helpdesk',
            pages: {'/helpdesk': (_, __) => const HelpdeskTicketsScreen()}));
    await snap(tester, 'helpdesk');
    await snapTall(tester, 'helpdesk');
    await finishPreview(tester);
  });
}
