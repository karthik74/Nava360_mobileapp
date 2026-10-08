// /team (TeamScreen, inside the real HomeShell) and a team member's detail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/home/home_shell.dart';
import 'package:nava360/features/team/employee_detail_screen.dart';
import 'package:nava360/features/team/team_screen.dart';

import 'harness.dart';

Widget _shell(Widget child) => HomeShell(child: child);
final _pages = <String, PageBuilder>{'/team': (_, __) => const TeamScreen()};

void main() {
  previewSetUpAll();

  previewTest('team members', (tester) async {
    await pumpShellTab(tester,
        location: '/team', shell: _shell, shellPages: _pages);
    await snap(tester, 'team');
    await snapTall(tester, 'team');
    await finishPreview(tester);
  });

  previewTest('team leaves tab', (tester) async {
    await pumpShellTab(tester,
        location: '/team', shell: _shell, shellPages: _pages);
    await tapAny(tester, [
      find.descendant(
          of: find.byType(TeamScreen), matching: find.text('Leaves')),
    ]);
    await snap(tester, 'team_leaves');
    await snapTall(tester, 'team_leaves');
    await finishPreview(tester);
  });

  previewTest('team attendance tab', (tester) async {
    await pumpShellTab(tester,
        location: '/team', shell: _shell, shellPages: _pages);
    await tapAny(tester, [
      find.descendant(
          of: find.byType(TeamScreen), matching: find.text('Attendance')),
    ]);
    await snap(tester, 'team_attendance');
    await finishPreview(tester);
  });

  previewTest('employee detail', (tester) async {
    await pumpPreview(tester,
        router: previewRouter(initialLocation: '/employee', pages: {
          '/employee': (_, __) => const EmployeeDetailScreen(
              employeeId: 101, name: 'Ramesh Kulkarni'),
        }));
    await snap(tester, 'employee_detail');
    await snapTall(tester, 'employee_detail');
    await finishPreview(tester);
  });
}
