import 'package:flutter/material.dart';
import 'package:nava360/core/pro_ui.dart';
import 'package:nava360/core/theme.dart';
import 'package:nava360/core/widgets.dart';

import 'harness.dart';

/// The Home shift card in all three states: green "check in", red "check out",
/// grey "done" — so the next action is obvious at a glance.
void main() {
  previewSetUpAll();

  previewTest('shift card states', (tester) async {
    setFrame(tester, const Size(360, 1180));
    Widget card({required bool inn, required bool out}) => AttendanceHeroCard(
          timerText: inn ? (out ? '08:42:10' : '04:15:29') : '00:00:00',
          hasCheckedIn: inn,
          hasCheckedOut: out,
          checkInTime: inn ? '9:11 AM' : '—',
          checkOutTime: out ? '5:53 PM' : '—',
          onTap: () {},
          location: 'Vidyagiri, Dharwad',
        );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: previewTheme(),
      builder: (context, child) => ProTextDensity(child: child!),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            card(inn: false, out: false),
            const SizedBox(height: 16),
            card(inn: true, out: false),
            const SizedBox(height: 16),
            card(inn: true, out: true),
          ],
        ),
      ),
    ));
    await settle(tester);
    await snap(tester, 'shift_card_states');
    await finishPreview(tester);
  });
}
