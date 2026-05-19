import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'location_ping_models.dart';

class LocationRepository {
  LocationRepository(this._api);
  final ApiClient _api;

  /// Uploads a batch of pings. Server returns the saved count.
  Future<int> uploadBatch(LocationPingBatch batch) {
    return _api.post<int>(
      '/api/attendance/locations',
      body: batch.toJson(),
      parse: (d) => (d as num).toInt(),
    );
  }
}

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => LocationRepository(ref.watch(apiClientProvider)),
);
