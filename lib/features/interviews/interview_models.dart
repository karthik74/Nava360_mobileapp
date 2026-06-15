import '../../core/theme.dart';

/// A candidate the current user has been assigned to interview — a subset of the
/// backend `CandidateResponse` relevant to the interviewer.
class Interview {
  final int id;
  final String fullName;
  final String? designation;
  final String? department;
  final String? requisitionTitle;
  final String? interviewerName;
  final DateTime? interviewAt;
  final String status; // CandidateStatus
  final String? phone;
  final String? email;
  final String? notes;

  const Interview({
    required this.id,
    required this.fullName,
    required this.designation,
    required this.department,
    required this.requisitionTitle,
    required this.interviewerName,
    required this.interviewAt,
    required this.status,
    required this.phone,
    required this.email,
    required this.notes,
  });

  factory Interview.fromJson(Map<String, dynamic> j) {
    final full = (j['fullName'] as String?)?.trim();
    final name = (full == null || full.isEmpty)
        ? '${j['firstName'] ?? ''} ${j['lastName'] ?? ''}'.trim()
        : full;
    return Interview(
      id: (j['id'] as num).toInt(),
      fullName: name.isEmpty ? 'Candidate' : name,
      designation: j['designation'] as String?,
      department: j['department'] as String?,
      requisitionTitle: j['requisitionTitle'] as String?,
      interviewerName: j['interviewerName'] as String?,
      interviewAt: DateTime.tryParse((j['interviewAt'] as String?) ?? ''),
      status: (j['status'] as String?) ?? 'INTERVIEW',
      phone: j['phone'] as String?,
      email: j['email'] as String?,
      notes: j['notes'] as String?,
    );
  }

  /// True while the candidate is still awaiting this interviewer's verdict.
  bool get isPending => status == 'INTERVIEW' || status == 'APPLIED';

  StatusTone get statusTone {
    switch (status) {
      case 'SELECTED':
      case 'OFFER_SENT':
      case 'OFFER_ACCEPTED':
      case 'HIRED':
        return const StatusTone(AppColors.success, 'Selected');
      case 'REJECTED':
      case 'OFFER_DECLINED':
        return const StatusTone(AppColors.danger, 'Rejected');
      case 'APPLIED':
        return const StatusTone(AppColors.info, 'Applied');
      default:
        return const StatusTone(AppColors.warning, 'Interview');
    }
  }
}
