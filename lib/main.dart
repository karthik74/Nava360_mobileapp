import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/notifications/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background message handler MUST be registered before runApp.
  // Safe even if Firebase isn't yet initialised — the registration just
  // remembers the handler for when a background push arrives.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final container = ProviderContainer();

  // Paint the app (and its branded splash loader) on the very first frame —
  // do NOT await any async init before runApp, otherwise the OS shows a blank
  // launch window until init finishes.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HrmsApp(),
    ),
  );

  // PushService.init() handles Firebase + local notifications and swallows any
  // failures (e.g. missing google-services.json), so the UI always boots. Run
  // it after the first frame so the loader appears instantly; push setup
  // completes a moment later in the background.
  container.read(pushServiceProvider).init();
}
