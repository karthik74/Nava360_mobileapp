import '../../core/theme.dart';

/// A direct report of the current manager, with today's attendance state
/// (from `GET /api/employees/my-team/today-status`).
class TeamMember {
  final int id;
  final String name;
  final String? employeeCode;
  final String? designation;
  final String? department;
  final String? phone;
  final String? email;
  final String? branchLabel;

  /// PUNCHED_IN | PUNCHED_OUT | ABSENT | LEAVE | NOT_LOGGED_IN
  final String state;
  final String? checkIn; // ISO datetime, when punched in
  final String? checkOut; // ISO datetime, when punched out

  const TeamMember({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.designation,
    required this.department,
    required this.phone,
    required this.email,
    required this.branchLabel,
    this.state = 'NOT_LOGGED_IN',
    this.checkIn,
    this.checkOut,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    // Tolerates both the plain /my-team shape (id, firstName, lastName) and the
    // /my-team/today-status shape (employeeId, name, state, checkIn, checkOut).
    final composed = '${j['firstName'] ?? ''} ${j['lastName'] ?? ''}'.trim();
    final given = (j['name'] as String?)?.trim();
    final resolvedName = (given != null && given.isNotEmpty)
        ? given
        : (composed.isNotEmpty
            ? composed
            : (j['employeeCode'] as String? ?? 'Employee'));
    final rawId = (j['id'] ?? j['employeeId']) as num;
    return TeamMember(
      id: rawId.toInt(),
      name: resolvedName,
      employeeCode: j['employeeCode'] as String?,
      designation: j['designation'] as String?,
      department: j['department'] as String?,
      phone: j['phone'] as String?,
      email: j['email'] as String?,
      branchLabel: j['branchLabel'] as String?,
      state: (j['state'] as String?) ?? 'NOT_LOGGED_IN',
      checkIn: j['checkIn'] as String?,
      checkOut: j['checkOut'] as String?,
    );
  }

  StatusTone get statusTone => StatusTone.forTeamState(state);

  String? get checkInHm => _hm(checkIn);
  String? get checkOutHm => _hm(checkOut);

  /// "HH:mm" (local) from an ISO datetime, or null.
  static String? _hm(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
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
