import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'resignation_models.dart';

class ResignationRepository {
  ResignationRepository(this._api);
  final ApiClient _api;

  /// The logged-in employee's own resignations (newest first by the backend).
  Future<List<Resignation>> myResignations() {
    return _api.get<List<Resignation>>(
      '/api/resignations/my',
      parse: (d) {
        final list = d is List
            ? d
            : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const []);
        return list
            .map((e) => Resignation.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Notice period derived from the employee's tenure/designation.
  Future<NoticePeriodInfo> myNoticePeriod() {
    return _api.get<NoticePeriodInfo>(
      '/api/resignations/my-notice-period',
      parse: (d) => NoticePeriodInfo.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Self-service: submit a resignation. [resignationDate] / [lastWorkingDay]
  /// are ISO `yyyy-MM-dd` strings.
  Future<Resignation> apply({
    required String resignationDate,
    String? lastWorkingDay,
    String? reason,
  }) {
    return _api.post<Resignation>(
      '/api/resignations/apply',
      body: {
        'resignationDate': resignationDate,
        if (lastWorkingDay != null && lastWorkingDay.isNotEmpty)
          'lastWorkingDay': lastWorkingDay,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      parse: (d) => Resignation.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Withdraw one of the employee's own resignations.
  Future<Resignation> withdraw(int id, {String? comment}) {
    return _api.post<Resignation>(
      '/api/resignations/$id/withdraw',
      body: {if (comment != null && comment.isNotEmpty) 'comment': comment},
      parse: (d) => Resignation.fromJson(d as Map<String, dynamic>),
    );
  }
}

final resignationRepositoryProvider = Provider<ResignationRepository>(
  (ref) => ResignationRepository(ref.watch(apiClientProvider)),
);
