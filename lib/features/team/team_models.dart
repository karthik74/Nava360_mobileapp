import '../../core/theme.dart';

/// A direct report of the current manager (from `GET /api/employees/my-team`).
class TeamMember {
  final int id;
  final String name;
  final String? employeeCode;
  final String? designation;
  final String? department;
  final String? phone;
  final String? email;
  final String? branchLabel;

  const TeamMember({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.designation,
    required this.department,
    required this.phone,
    required this.email,
    required this.branchLabel,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    final name =
        '${j['firstName'] ?? ''} ${j['lastName'] ?? ''}'.trim();
    return TeamMember(
      id: (j['id'] as num).toInt(),
      name: name.isEmpty ? (j['employeeCode'] as String? ?? 'Employee') : name,
      employeeCode: j['employeeCode'] as String?,
      designation: j['designation'] as String?,
      department: j['department'] as String?,
      phone: j['phone'] as String?,
      email: j['email'] as String?,
      branchLabel: j['branchLabel'] as String?,
    );
  }
}

/// An attendance regularization request (from `GET /api/regularizations/team`).
class RegularizationRequest {
  final int id;
  final int? employeeId;
  final String? employeeName;
  final String? date; // yyyy-MM-dd
  final String? requestedStatus; // AttendanceStatus
  final String? requestedCheckIn; // HH:mm[:ss]
  final String? requestedCheckOut;
  final String? reason;
  final String status; // PENDING | APPROVED | REJECTED | CANCELLED

  const RegularizationRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.requestedStatus,
    required this.requestedCheckIn,
    required this.requestedCheckOut,
    required this.reason,
    required this.status,
  });

  factory RegularizationRequest.fromJson(Map<String, dynamic> j) =>
      RegularizationRequest(
        id: (j['id'] as num).toInt(),
        employeeId: (j['employeeId'] as num?)?.toInt(),
        employeeName: j['employeeName'] as String?,
        date: j['date'] as String?,
        requestedStatus: j['requestedStatus'] as String?,
        requestedCheckIn: j['requestedCheckIn'] as String?,
        requestedCheckOut: j['requestedCheckOut'] as String?,
        reason: j['reason'] as String?,
        status: (j['status'] as String?) ?? 'PENDING',
      );

  bool get isPending => status == 'PENDING';

  StatusTone get statusTone {
    switch (status) {
      case 'APPROVED':
        return const StatusTone(AppColors.success, 'Approved');
      case 'REJECTED':
        return const StatusTone(AppColors.danger, 'Rejected');
      case 'CANCELLED':
        return const StatusTone(AppColors.muted, 'Cancelled');
      default:
        return const StatusTone(AppColors.warning, 'Pending');
    }
  }

  /// Short "hh:mm" from a "HH:mm[:ss]" wire value.
  static String? _hm(String? t) {
    if (t == null || t.isEmpty) return null;
    final parts = t.split(':');
    if (parts.length < 2) return t;
    return '${parts[0]}:${parts[1]}';
  }

  String get timeSummary {
    final inT = _hm(requestedCheckIn);
    final outT = _hm(requestedCheckOut);
    if (inT == null && outT == null) return '';
    return '${inT ?? '—'} → ${outT ?? '—'}';
  }
}
