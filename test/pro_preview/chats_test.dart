// /chats (ChatListScreen inside the shell).
import 'package:flutter/material.dart';
import 'package:nava360/features/chat/chat_list_screen.dart';
import 'package:nava360/features/home/home_shell.dart';

import 'harness.dart';

Widget _shell(Widget child) => HomeShell(child: child);
final _pages = <String, PageBuilder>{
  '/chats': (_, __) => const ChatListScreen(),
};

void main() {
  previewSetUpAll();

  previewTest('chats', (tester) async {
    await pumpShellTab(tester,
        location: '/chats', shell: _shell, shellPages: _pages);
    await snap(tester, 'chats');
    await snapTall(tester, 'chats');
    await finishPreview(tester);
  });
}
