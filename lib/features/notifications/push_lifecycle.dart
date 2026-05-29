import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'push_service.dart';

/// Wires the [PushService] to the auth state:
///   - When the user becomes non-null (login or restored session), call
///     [PushService.start] so the device token is registered with the
///     backend and foreground messages are surfaced as notifications.
///   - When the user becomes null (logout), call [PushService.stop].
///
/// Simply `ref.watch(pushLifecycleProvider)` once at the app root to
/// activate this side-effect.
final pushLifecycleProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<dynamic>>(
    authControllerProvider,
    (prev, next) {
      final wasUser = prev?.asData?.value != null;
      final isUser = next.asData?.value != null;
      if (!wasUser && isUser) {
        // Fire-and-forget — service handles its own errors.
        ref.read(pushServiceProvider).start();
      } else if (wasUser && !isUser) {
        ref.read(pushServiceProvider).stop();
      }
    },
    fireImmediately: true,
  );
});
