// Signed-out flows: /login, the first-login (activate account) wizard up to
// its OTP step, and forgot-password.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/auth/first_login_screen.dart';
import 'package:nava360/features/auth/forgot_password_screen.dart';
import 'package:nava360/features/auth/login_screen.dart';

import 'harness.dart';

final _pages = <String, PageBuilder>{
  '/login': (_, __) => const LoginScreen(),
  '/first-login': (_, __) => const FirstLoginScreen(),
  '/forgot-password': (_, __) => const ForgotPasswordScreen(),
};

void main() {
  previewSetUpAll();

  previewTest('login', (tester) async {
    await pumpPreview(tester,
        user: null,
        router: previewRouter(initialLocation: '/login', pages: _pages));
    await snap(tester, 'login');
    await finishPreview(tester);
  });

  previewTest('first login - employee code, then OTP step', (tester) async {
    await pumpPreview(tester,
        user: null,
        router: previewRouter(initialLocation: '/first-login', pages: _pages));
    await snap(tester, 'first_login');
    final field = find.byType(TextField);
    if (field.evaluate().isNotEmpty) {
      await tester.enterText(field.first, 'NLPL0042');
      await settle(tester, rounds: 1);
    }
    await tapAny(tester, [find.text('Send OTP')]);
    // Dismiss the keyboard focus so the step renders like a fresh screen.
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, rounds: 1);
    await snap(tester, 'first_login_otp');
    await finishPreview(tester);
  });

  previewTest('forgot password', (tester) async {
    await pumpPreview(tester,
        user: null,
        router:
            previewRouter(initialLocation: '/forgot-password', pages: _pages));
    await snap(tester, 'forgot_password');
    await finishPreview(tester);
  });
}
