// /tasks (CustomerTasksHub inside the shell): Customers, My tasks, Team.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/customers/customers_screen.dart';
import 'package:nava360/features/home/home_shell.dart';

import 'harness.dart';

Widget _shell(Widget child) => HomeShell(child: child);
final _pages = <String, PageBuilder>{
  '/tasks': (_, __) => const CustomerTasksHub(),
};

void main() {
  previewSetUpAll();

  previewTest('tasks hub - customers', (tester) async {
    await pumpShellTab(tester,
        location: '/tasks', shell: _shell, shellPages: _pages);
    await snap(tester, 'customers');
    await snapTall(tester, 'customers');
    await finishPreview(tester);
  });

  previewTest('tasks hub - my tasks', (tester) async {
    await pumpShellTab(tester,
        location: '/tasks', shell: _shell, shellPages: _pages);
    await tapAny(tester, [find.text('My tasks')]);
    await snap(tester, 'tasks');
    await snapTall(tester, 'tasks');
    await finishPreview(tester);
  });

  previewTest('tasks hub - my tasks filter sheet', (tester) async {
    await pumpShellTab(tester,
        location: '/tasks', shell: _shell, shellPages: _pages);
    await tapAny(tester, [find.text('My tasks')]);
    await tapAny(tester, [find.text('Filter')]);
    await tapAny(tester, [find.text('In progress').last]);
    await tapAny(tester, [find.text('High').last]);
    await settle(tester, rounds: 2);
    await snap(tester, 'tasks_filter_sheet');
    Navigator.of(tester.element(find.text('Filter tasks').last)).pop();
    await settle(tester, rounds: 2);
    await snap(tester, 'tasks_filtered');
    await finishPreview(tester);
  });

  previewTest('tasks hub - team', (tester) async {
    await pumpShellTab(tester,
        location: '/tasks', shell: _shell, shellPages: _pages);
    await tapAny(tester, [find.text('Team')]);
    await snap(tester, 'tasks_team');
    await snapTall(tester, 'tasks_team');
    await finishPreview(tester);
  });
}
