import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stable, app-local device identifier for credit-SMS enrolment. A persisted,
/// non-PII random id — shared by the consent screen and the auto-enrol path so
/// both report the same device.
class CreditSmsDevice {
  CreditSmsDevice._();

  static const _opts = AndroidOptions(encryptedSharedPreferences: true);
  static const _store = FlutterSecureStorage(aOptions: _opts);
  static const _kDeviceId = 'credit_sms.device_id';

  static Future<String> id() async {
    final existing = await _store.read(key: _kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = Random();
    final id =
        List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
    await _store.write(key: _kDeviceId, value: id);
    return id;
  }
}
