import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'location_tracker.dart';

/// Wires the [LocationTracker] to the auth state:
///   - When the user becomes non-null (login or restored session), call
///     [LocationTracker.restoreIfActive] so an in-progress tracking session
///     (started before the app was killed) resumes automatically.
///   - When the user becomes null (logout), stop tracking.
///
/// Simply `ref.watch(locationLifecycleProvider)` once at the app root to
/// activate this side-effect.
final locationLifecycleProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<dynamic>>(
    authControllerProvider,
    (prev, next) {
      final wasUser = prev?.asData?.value != null;
      final isUser = next.asData?.value != null;
      if (!wasUser && isUser) {
        // Fire-and-forget — tracker handles its own errors.
        ref.read(locationTrackerProvider.notifier).restoreIfActive();
      } else if (wasUser && !isUser) {
        ref.read(locationTrackerProvider.notifier).stop(flushBuffer: false);
      }
    },
    fireImmediately: true,
  );
});
