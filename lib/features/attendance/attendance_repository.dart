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

  /// Submits an attendance regularization request for [date] (yyyy-MM-dd).
  /// [requestedStatus] is an AttendanceStatus name; times are "HH:mm" (optional).
  Future<void> createRegularization({
    required int employeeId,
    required String date,
    required String requestedStatus,
    String? checkIn,
    String? checkOut,
    required String reason,
  }) {
    return _api.post<void>(
      '/api/regularizations',
      body: {
        'employeeId': employeeId,
        'date': date,
        'requestedStatus': requestedStatus,
        if (checkIn != null && checkIn.isNotEmpty) 'requestedCheckIn': '$checkIn:00',
        if (checkOut != null && checkOut.isNotEmpty) 'requestedCheckOut': '$checkOut:00',
        'reason': reason,
      },
      parse: (_) {},
    );
  }

  /// The current user's own regularization requests in [from..to] (yyyy-MM-dd),
  /// returned as a date→status map for quick per-day lookups.
  Future<Map<String, String>> myRegularizationStatusByDate({
    String? from,
    String? to,
  }) async {
    return _api.get<Map<String, String>>(
      '/api/regularizations',
      query: {'size': 100, 'sort': 'date,desc'},
      parse: (d) {
        final map = (d as Map<String, dynamic>?) ?? const {};
        final content = (map['content'] as List?) ?? const [];
        final out = <String, String>{};
        for (final e in content) {
          final m = e as Map<String, dynamic>;
          final dt = m['date'] as String?;
          final st = m['status'] as String?;
          if (dt == null || st == null) continue;
          if (from != null && dt.compareTo(from) < 0) continue;
          if (to != null && dt.compareTo(to) > 0) continue;
          // Keep the newest (list is desc) — don't overwrite with older rows.
          out.putIfAbsent(dt, () => st);
        }
        return out;
      },
    );
  }

  /// The attendance cycle start day (1 = calendar month). Employee-readable.
  Future<int> getCycleStartDay() {
    return _api.get<int>(
      '/api/attendance-settings',
      parse: (d) {
        final m = (d as Map<String, dynamic>?) ?? const {};
        return (m['cycleStartDay'] as num?)?.toInt() ?? 1;
      },
    );
  }

  /// Holidays visible to the current employee in [from..to], as date→name.
  Future<Map<String, String>> listMyHolidays({String? from, String? to}) {
    return _api.get<Map<String, String>>(
      '/api/holidays/my',
      query: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
      parse: (d) {
        final list = (d as List?) ?? const [];
        final out = <String, String>{};
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          final dt = m['date'] as String?;
          if (dt != null) out[dt] = (m['name'] as String?) ?? 'Holiday';
        }
        return out;
      },
    );
  }

  /// Active non-working-day rules used to classify week-offs.
  Future<List<NonWorkingRule>> listNonWorkingDays() {
    return _api.get<List<NonWorkingRule>>(
      '/api/non-working-days',
      query: {'activeOnly': true},
      parse: (d) {
        final list = (d as List?) ?? const [];
        return list
            .map((e) => NonWorkingRule.fromJson(e as Map<String, dynamic>))
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
