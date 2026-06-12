import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'credit_sms_models.dart';

/// Version of the credit-SMS consent policy. Bump when the policy wording
/// changes so the backend can tell which version each employee agreed to.
const String kCreditSmsPolicyVersion = 'v1-2026-06';

/// Talks to the mobile credit-SMS endpoints. The current employee is implied by
/// the JWT, so no employeeId is sent from the client.
class CreditSmsRepository {
  CreditSmsRepository(this._api);
  final ApiClient _api;

  /// GET /api/mobile/sms-consent/status
  Future<CreditSmsConsent> consentStatus() {
    return _api.get<CreditSmsConsent>(
      '/api/mobile/sms-consent/status',
      parse: (d) => CreditSmsConsent.fromJson(d as Map<String, dynamic>),
    );
  }

  /// POST /api/mobile/sms-consent
  Future<CreditSmsConsent> setConsent({
    required bool granted,
    String? deviceId,
    String? policyVersion,
  }) {
    return _api.post<CreditSmsConsent>(
      '/api/mobile/sms-consent',
      body: {
        'granted': granted,
        if (deviceId != null) 'deviceId': deviceId,
        if (policyVersion != null) 'policyVersion': policyVersion,
      },
      parse: (d) => CreditSmsConsent.fromJson(d as Map<String, dynamic>),
    );
  }

  /// POST /api/mobile/credit-sms — upload one parsed+masked credit.
  Future<CreditSms> upload(ParsedCreditSms parsed) {
    return _api.post<CreditSms>(
      '/api/mobile/credit-sms',
      body: parsed.toJson(),
      parse: (d) => CreditSms.fromJson(d as Map<String, dynamic>),
    );
  }

  /// GET /api/mobile/credit-sms — the employee's own detected credits.
  Future<List<CreditSms>> myCredits({int page = 0, int size = 50}) {
    return _api.get<List<CreditSms>>(
      '/api/mobile/credit-sms',
      query: {'page': page, 'size': size},
      parse: (d) {
        final list = (d as Map<String, dynamic>)['content'] as List<dynamic>? ??
            const [];
        return list
            .map((e) => CreditSms.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }
}

final creditSmsRepositoryProvider = Provider<CreditSmsRepository>(
  (ref) => CreditSmsRepository(ref.watch(apiClientProvider)),
);

/// The current consent status, refreshable from the consent screen.
final creditSmsConsentProvider = FutureProvider.autoDispose<CreditSmsConsent>(
  (ref) => ref.watch(creditSmsRepositoryProvider).consentStatus(),
);

/// The employee's detected-credit list.
final myCreditsProvider = FutureProvider.autoDispose<List<CreditSms>>(
  (ref) => ref.watch(creditSmsRepositoryProvider).myCredits(),
);
