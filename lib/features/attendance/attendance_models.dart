/// A configured non-working-day rule (e.g. every Sunday, 2nd Saturday).
/// Mirrors the backend `NonWorkingDay`.
class NonWorkingRule {
  final String dayOfWeek; // MONDAY..SUNDAY
  final String week; // ALL | FIRST | SECOND | THIRD | FOURTH | FIFTH | LAST
  final bool active;

  NonWorkingRule({
    required this.dayOfWeek,
    required this.week,
    required this.active,
  });

  factory NonWorkingRule.fromJson(Map<String, dynamic> j) => NonWorkingRule(
        dayOfWeek: (j['dayOfWeek'] as String?) ?? '',
        week: (j['week'] as String?) ?? 'ALL',
        active: j['active'] != false,
      );
}

class AttendanceRecord {
  final int id;
  final int employeeId;
  final String employeeName;
  final String date; // YYYY-MM-DD
  final String? checkIn; // ISO datetime
  final String? checkOut;
  final double? checkInLatitude;
  final double? checkInLongitude;
  final double? checkOutLatitude;
  final double? checkOutLongitude;
  final double? workingHours;
  final String status; // PRESENT | HALF_DAY | ABSENT | ON_LEAVE | HOLIDAY

  AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.checkIn,
    required this.checkOut,
    required this.checkInLatitude,
    required this.checkInLongitude,
    required this.checkOutLatitude,
    required this.checkOutLongitude,
    required this.workingHours,
    required this.status,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: (j['id'] as num).toInt(),
        employeeId: (j['employeeId'] as num).toInt(),
        employeeName: j['employeeName'] as String? ?? '',
        date: j['date'] as String,
        checkIn: j['checkIn'] as String?,
        checkOut: j['checkOut'] as String?,
        checkInLatitude: (j['checkInLatitude'] as num?)?.toDouble(),
        checkInLongitude: (j['checkInLongitude'] as num?)?.toDouble(),
        checkOutLatitude: (j['checkOutLatitude'] as num?)?.toDouble(),
        checkOutLongitude: (j['checkOutLongitude'] as num?)?.toDouble(),
        workingHours: (j['workingHours'] as num?)?.toDouble(),
        status: j['status'] as String,
      );
}
