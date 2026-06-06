import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/secure_storage.dart';

/// Tracks whether the user has seen the welcome / onboarding screen.
///
/// Backed by [SecureStorage] but kept in memory so a [markSeen] during the
/// current session is reflected immediately — unlike a one-shot FutureProvider,
/// which would stay stale until the next app launch and wrongly bounce signed-
/// out users back to /welcome after sign-out or a failed login.
class WelcomeSeenController extends StateNotifier<AsyncValue<bool>> {
  WelcomeSeenController() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = AsyncValue.data(await SecureStorage.readWelcomeSeen());
  }

  /// Persist that the welcome was seen and update in-memory state now.
  Future<void> markSeen() async {
    state = const AsyncValue.data(true);
    await SecureStorage.markWelcomeSeen();
  }
}

final welcomeSeenProvider =
    StateNotifierProvider<WelcomeSeenController, AsyncValue<bool>>(
  (_) => WelcomeSeenController(),
);
