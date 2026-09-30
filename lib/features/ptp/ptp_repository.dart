import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'ptp_models.dart';

/// Reads the caller's PTP follow-ups. The server decides the scope (own
/// customers / whole branch / everything) from who is signed in, so the app
/// never sends an officer or branch id.
class PtpRepository {
  PtpRepository(this._api);

  final ApiClient _api;

  static const int pageSize = 50;

  Future<PtpPage> mine({
    required PtpFilter filter,
    int page = 0,
    int size = pageSize,
  }) {
    return _api.get<PtpPage>(
      '/api/crm-ptp/mine',
      query: {'filter': filter.api, 'page': page, 'size': size},
      parse: (d) => PtpPage.fromJson((d as Map).cast<String, dynamic>()),
    );
  }

  Future<PtpSummary> summary() {
    return _api.get<PtpSummary>(
      '/api/crm-ptp/mine/summary',
      parse: (d) => PtpSummary.fromJson((d as Map).cast<String, dynamic>()),
    );
  }
}

final ptpRepositoryProvider = Provider<PtpRepository>(
  (ref) => PtpRepository(ref.watch(apiClientProvider)),
);
