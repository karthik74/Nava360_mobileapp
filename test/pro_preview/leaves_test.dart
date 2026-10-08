// /leaves (LeavesScreen inside the shell) and the apply-leave sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/home/home_shell.dart';
import 'package:nava360/features/leaves/leaves_screen.dart';

import 'harness.dart';

Widget _shell(Widget child) => HomeShell(child: child);
final _pages = <String, PageBuilder>{
  '/leaves': (_, __) => const LeavesScreen(),
};

void main() {
  previewSetUpAll();

  previewTest('leaves', (tester) async {
    await pumpShellTab(tester,
        location: '/leaves', shell: _shell, shellPages: _pages);
    await snap(tester, 'leaves');
    await snapTall(tester, 'leaves');
    await finishPreview(tester);
  });

  previewTest('apply leave sheet', (tester) async {
    await pumpShellTab(tester,
        location: '/leaves', shell: _shell, shellPages: _pages);
    await tapAny(tester, [
      find.text('Apply for leave'),
      find.byTooltip('Apply for leave'),
      find.byIcon(Icons.add_rounded),
    ]);
    await snap(tester, 'leave_apply');
    await finishPreview(tester);
  });
}
