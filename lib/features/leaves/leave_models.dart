class LeaveRequest {
  final int id;
  final int employeeId;
  final String? employeeName;
  final String leaveType;
  final String fromDate;
  final String toDate;
  final int? numberOfDays;
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
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
        id: (j['id'] as num).toInt(),
        employeeId: (j['employeeId'] as num).toInt(),
        employeeName: j['employeeName'] as String?,
        leaveType: j['leaveType'] as String,
        fromDate: j['fromDate'] as String,
        toDate: j['toDate'] as String,
        numberOfDays: (j['numberOfDays'] as num?)?.toInt(),
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

class LeaveBalance {
  final String leaveTypeCode;
  final String leaveTypeLabel;
  final int? allowanceDays;
  final int usedDays;
  final int? balanceDays;

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
        usedDays: (j['usedDays'] as num).toInt(),
        balanceDays: (j['balanceDays'] as num?)?.toInt(),
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

  LeaveCreateRequest({
    required this.employeeId,
    required this.leaveType,
    required this.fromDate,
    required this.toDate,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'leaveType': leaveType,
        'fromDate': fromDate,
        'toDate': toDate,
        'reason': reason,
      };
}
