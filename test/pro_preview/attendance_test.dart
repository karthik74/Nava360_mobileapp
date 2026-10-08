// /attendance (AttendanceScreen inside the shell).
import 'package:flutter/material.dart';
import 'package:nava360/features/attendance/attendance_screen.dart';
import 'package:nava360/features/home/home_shell.dart';

import 'harness.dart';

Widget _shell(Widget child) => HomeShell(child: child);
final _pages = <String, PageBuilder>{
  '/attendance': (_, __) => const AttendanceScreen(),
};

void main() {
  previewSetUpAll();

  previewTest('attendance', (tester) async {
    await pumpShellTab(tester,
        location: '/attendance', shell: _shell, shellPages: _pages);
    await snap(tester, 'attendance');
    await snapTall(tester, 'attendance');
    await finishPreview(tester);
  });
}
