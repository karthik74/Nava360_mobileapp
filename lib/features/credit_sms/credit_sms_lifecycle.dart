import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'credit_sms_device.dart';
import 'credit_sms_repository.dart';
import 'credit_sms_sync.dart';

/// Records credit-SMS consent and resumes scanning + outbox draining on app
/// launch / login. There is no consent screen — every user is enrolled
/// automatically: immediately after login we POST `/api/mobile/sms-consent`
/// (granted) for all users, then start scanning if the OS SMS permission is
/// held. On logout it stops the service. Activate by
/// `ref.watch(creditSmsLifecycleProvider)` once at the app root.
///
/// This is what makes capture survive restarts and makes the outbox flush
/// "when internet is available" — every app open re-scans recent inbox and
/// pushes anything queued offline.
final creditSmsLifecycleProvider = Provider<void>((ref) {
  Future<void> resume() async {
    final repo = ref.read(creditSmsRepositoryProvider);

    // 1. Record consent for EVERY user, immediately after login. This fires
    //    regardless of platform or SMS permission so the backend always knows
    //    the employee is enrolled.
    try {
      debugPrint('[credit-sms] recording consent (POST /api/mobile/sms-consent)');
      await repo.setConsent(
        granted: true,
        deviceId: await CreditSmsDevice.id(),
        policyVersion: kCreditSmsPolicyVersion,
      );
    } catch (e) {
      debugPrint('[credit-sms] consent POST failed: $e');
    }

    // 2. Start scanning if we can actually read SMS (Android + permission held).
    try {
      final service = ref.read(creditSmsServiceProvider);
      if (await service.hasPermission()) {
        await service.start();
      } else {
        debugPrint('[credit-sms] resume: SMS permission not granted; '
            'scanning will start once it is granted');
      }
    } catch (e) {
      // Offline or transient error — the next app open will retry.
      debugPrint('[credit-sms] resume failed: $e');
    }
  }

  ref.listen<AsyncValue<dynamic>>(
    authControllerProvider,
    (prev, next) {
      final wasUser = prev?.asData?.value != null;
      final isUser = next.asData?.value != null;
      if (!wasUser && isUser) {
        resume();
      } else if (wasUser && !isUser) {
        ref.read(creditSmsServiceProvider).stop();
      }
    },
    fireImmediately: true,
  );
});
