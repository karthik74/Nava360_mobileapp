// Shell + dashboard, drawer, HRMS and More module screens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/home/dashboard_screen.dart';
import 'package:nava360/features/home/home_shell.dart';
import 'package:nava360/features/home/module_screens.dart';

import 'harness.dart';

Widget _shell(Widget child) => HomeShell(child: child);

final _pages = <String, PageBuilder>{
  '/home': (_, __) => const DashboardScreen(),
  '/hrms': (_, __) => const HrmsScreen(),
  '/more': (_, __) => const MoreScreen(),
};

void main() {
  previewSetUpAll();

  previewTest('home (shell + dashboard)', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/home', shell: _shell, shellPages: _pages));
    await snap(tester, 'home');
    await snapTall(tester, 'home');
    await finishPreview(tester);
  });

  previewTest('home drawer open', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/home', shell: _shell, shellPages: _pages));
    final scaffold = tester.firstState<ScaffoldState>(find.byWidgetPredicate(
        (w) => w is Scaffold && w.drawer != null));
    scaffold.openDrawer();
    await settle(tester, rounds: 2);
    await snap(tester, 'home_drawer');
    await snapTall(tester, 'home_drawer');
    await finishPreview(tester);
  });

  previewTest('quick actions arc', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/home', shell: _shell, shellPages: _pages));
    await tester.tap(find.bySemanticsLabel('Quick actions'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await snap(tester, 'quick_actions');
    await finishPreview(tester);
  });

  previewTest('hrms module', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/hrms', shell: _shell, shellPages: _pages));
    await snap(tester, 'hrms');
    await snapTall(tester, 'hrms');
    await finishPreview(tester);
  });

  previewTest('more module', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(
            initialLocation: '/more', shell: _shell, shellPages: _pages));
    await snap(tester, 'more');
    await finishPreview(tester);
  });
}
