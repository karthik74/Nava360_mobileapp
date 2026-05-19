import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'attendance_models.dart';

class AttendanceRepository {
  AttendanceRepository(this._api);
  final ApiClient _api;

  Future<AttendanceRecord> checkIn(
    int employeeId, {
    double? latitude,
    double? longitude,
  }) {
    return _api.post<AttendanceRecord>(
      '/api/attendance/check-in/$employeeId',
      query: _coordsQuery(latitude, longitude),
      parse: (d) => AttendanceRecord.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<AttendanceRecord> checkOut(
    int employeeId, {
    double? latitude,
    double? longitude,
  }) {
    return _api.post<AttendanceRecord>(
      '/api/attendance/check-out/$employeeId',
      query: _coordsQuery(latitude, longitude),
      parse: (d) => AttendanceRecord.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Lists this employee's records in [from..to]. Server returns a Spring Page;
  /// we just want the rows.
  Future<List<AttendanceRecord>> listForEmployee(
    int employeeId, {
    String? from,
    String? to,
    int page = 0,
    int size = 50,
  }) async {
    return _api.get<List<AttendanceRecord>>(
      '/api/attendance/employee/$employeeId',
      query: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'page': page,
        'size': size,
      },
      parse: (d) {
        final list = (d as Map<String, dynamic>)['content'] as List<dynamic>;
        return list
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Map<String, dynamic>? _coordsQuery(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return {'latitude': lat, 'longitude': lng};
  }
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(apiClientProvider)),
);
