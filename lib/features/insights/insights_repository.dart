import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'insights_models.dart';

/// Opening-insights API. Scope (FO own customers / branch / area / division /
/// region / all) is decided by the server from the caller's designation, so
/// the app never sends one — only an optional month.
class InsightsRepository {
  InsightsRepository(this._api);
  final ApiClient _api;

  /// Month-to-date disbursement, FTOD and PTP counts. [month] is "YYYY-MM";
  /// omitted = the server's current month.
  Future<OpeningInsights> opening({String? month}) {
    return _api.get<OpeningInsights>(
      '/api/insights/opening',
      query: {if (month != null && month.isNotEmpty) 'month': month},
      parse: OpeningInsights.fromJson,
    );
  }
}

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) => InsightsRepository(ApiClient.instance),
);

/// This month's opening insights. autoDispose so every showing of the intro
/// fetches fresh numbers instead of replaying a stale copy.
final openingInsightsProvider = FutureProvider.autoDispose<OpeningInsights>(
  (ref) => ref.watch(insightsRepositoryProvider).opening(),
);
