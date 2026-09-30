import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'ftod_models.dart';

/// FTOD collections API. Scope (own customers / branch / all) is decided by
/// the server from the caller's role, so the app never sends an officer or
/// branch id.
class FtodRepository {
  FtodRepository(this._api);
  final ApiClient _api;

  /// Month totals + the date-wise distribution (due date → days collected).
  Future<FtodDistribution> distribution(String month) {
    return _api.get<FtodDistribution>(
      '/api/ftod/mine/distribution',
      query: {'month': month},
      parse: (d) => FtodDistribution.fromJson(
        d is Map ? Map<String, dynamic>.from(d) : const <String, dynamic>{},
      ),
    );
  }

  /// One page of customers, optionally narrowed to a due date and/or status.
  Future<FtodDuePage> dues({
    required String month,
    DateTime? dueDate,
    FtodStatus? status,
    int page = 0,
    int size = 50,
  }) {
    return _api.get<FtodDuePage>(
      '/api/ftod/mine',
      query: {
        'month': month,
        if (dueDate != null) 'dueDate': ftodIsoDate(dueDate),
        if (status != null) 'status': status.api,
        'page': page,
        'size': size,
      },
      parse: FtodDuePage.fromJson,
    );
  }
}

final ftodRepositoryProvider = Provider<FtodRepository>(
  (ref) => FtodRepository(ApiClient.instance),
);

/// Distribution per month key ("2026-09"). autoDispose so leaving the screen
/// drops it and the next visit shows fresh collections.
final ftodDistributionProvider =
    FutureProvider.autoDispose.family<FtodDistribution, String>((ref, month) {
  return ref.watch(ftodRepositoryProvider).distribution(month);
});
