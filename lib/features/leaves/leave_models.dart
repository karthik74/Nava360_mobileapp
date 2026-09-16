class LeaveRequest {
  final int id;
  final int employeeId;
  final String? employeeName;
  final String leaveType;
  final String fromDate;
  final String toDate;
  /// Calendar days in the range; a half-day still reports 1 here — prefer [days].
  final int? numberOfDays;
  /// Days charged against the balance (0.5 for a half-day).
  final double? days;
  /// FIRST_HALF | SECOND_HALF for a half-day leave; null for a full day.
  final String? halfDaySession;
  final String? reason;
  final String status; // PENDING|APPROVED|REJECTED|CANCELLED
  final String? reviewedByName;
  final String? reviewComment;

  LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.leaveType,
    required this.fromDate,
    required this.toDate,
    required this.numberOfDays,
    required this.reason,
    required this.status,
    required this.reviewedByName,
    required this.reviewComment,
    this.days,
    this.halfDaySession,
  });

  bool get isHalfDay => halfDaySession != null;

  /// "½ day (1st half)", "1 day", "3 days" — "? day(s)" when unknown.
  String get daysLabel {
    if (halfDaySession != null) {
      return '½ day (${halfDaySession == 'FIRST_HALF' ? '1st' : '2nd'} half)';
    }
    final n = days ?? numberOfDays?.toDouble();
    if (n == null) return '? day(s)';
    return '${fmtLeaveDays(n)} day${n == 1 ? '' : 's'}';
  }

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
        id: (j['id'] as num).toInt(),
        employeeId: (j['employeeId'] as num).toInt(),
        employeeName: j['employeeName'] as String?,
        leaveType: j['leaveType'] as String,
        fromDate: j['fromDate'] as String,
        toDate: j['toDate'] as String,
        numberOfDays: (j['numberOfDays'] as num?)?.toInt(),
        days: (j['days'] as num?)?.toDouble(),
        halfDaySession: j['halfDaySession'] as String?,
        reason: j['reason'] as String?,
        status: j['status'] as String,
        reviewedByName: j['reviewedByName'] as String?,
        reviewComment: j['reviewComment'] as String?,
      );
}

/// A configured leave-type policy (mirrors the web `LeaveTypePolicy`).
/// The apply-leave form builds its type list from these, like the web does.
class LeaveTypePolicy {
  final int? id;
  final String code;
  final String label;
  final bool active;
  final String allowedGender; // ANY | MALE | FEMALE

  LeaveTypePolicy({
    required this.code,
    required this.label,
    this.id,
    this.active = true,
    this.allowedGender = 'ANY',
  });

  factory LeaveTypePolicy.fromJson(Map<String, dynamic> j) => LeaveTypePolicy(
        id: (j['id'] as num?)?.toInt(),
        code: j['code'] as String,
        label: (j['label'] as String?)?.trim().isNotEmpty == true
            ? j['label'] as String
            : j['code'] as String,
        active: j['active'] != false,
        allowedGender: (j['allowedGender'] as String?) ?? 'ANY',
      );
}

/// "2", "0.5", "2.5" — never "2.0".
String fmtLeaveDays(num? v) {
  if (v == null) return '?';
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

class LeaveBalance {
  final String leaveTypeCode;
  final String leaveTypeLabel;
  final int? allowanceDays;
  /// May be fractional (x.5) once half-day leaves are involved.
  final double usedDays;
  final double? balanceDays;

  LeaveBalance({
    required this.leaveTypeCode,
    required this.leaveTypeLabel,
    required this.allowanceDays,
    required this.usedDays,
    required this.balanceDays,
  });

  factory LeaveBalance.fromJson(Map<String, dynamic> j) => LeaveBalance(
        leaveTypeCode: j['leaveTypeCode'] as String,
        leaveTypeLabel: j['leaveTypeLabel'] as String,
        allowanceDays: (j['allowanceDays'] as num?)?.toInt(),
        usedDays: (j['usedDays'] as num? ?? 0).toDouble(),
        balanceDays: (j['balanceDays'] as num?)?.toDouble(),
      );
}

class EmployeeLeaveBalances {
  final int year;
  final List<LeaveBalance> balances;
  EmployeeLeaveBalances({required this.year, required this.balances});

  factory EmployeeLeaveBalances.fromJson(Map<String, dynamic> j) {
    final list = (j['balances'] as List<dynamic>? ?? [])
        .map((e) => LeaveBalance.fromJson(e as Map<String, dynamic>))
        .toList();
    return EmployeeLeaveBalances(year: (j['year'] as num).toInt(), balances: list);
  }
}

class LeaveCreateRequest {
  final int employeeId;
  final String leaveType;
  final String fromDate;
  final String toDate;
  final String reason;
  /// FIRST_HALF | SECOND_HALF for a half-day (fromDate == toDate); null = full day.
  final String? halfDaySession;

  LeaveCreateRequest({
    required this.employeeId,
    required this.leaveType,
    required this.fromDate,
    required this.toDate,
    required this.reason,
    this.halfDaySession,
  });

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'leaveType': leaveType,
        'fromDate': fromDate,
        'toDate': toDate,
        'reason': reason,
        if (halfDaySession != null) 'halfDaySession': halfDaySession,
      };
}
