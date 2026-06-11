DateTime? _date(dynamic v) =>
    (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

/// An employee resignation record (mirrors the backend `ResignationResponse`).
class Resignation {
  Resignation({
    required this.id,
    required this.status,
    this.resignationDate,
    this.noticePeriodDays,
    this.lastWorkingDay,
    this.reason,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewComment,
    this.createdAt,
  });

  final int id;
  final String status; // PENDING | IN_APPROVAL | APPROVED | REJECTED | WITHDRAWN | COMPLETED
  final DateTime? resignationDate;
  final int? noticePeriodDays;
  final DateTime? lastWorkingDay;
  final String? reason;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewComment;
  final DateTime? createdAt;

  /// Still in flight — the employee can withdraw it.
  bool get isActive =>
      status == 'PENDING' || status == 'IN_APPROVAL' || status == 'APPROVED';

  bool get isClosed =>
      status == 'REJECTED' || status == 'WITHDRAWN' || status == 'COMPLETED';

  factory Resignation.fromJson(Map<String, dynamic> j) => Resignation(
        id: (j['id'] as num).toInt(),
        status: j['status'] as String? ?? 'PENDING',
        resignationDate: _date(j['resignationDate']),
        noticePeriodDays: (j['noticePeriodDays'] as num?)?.toInt(),
        lastWorkingDay: _date(j['lastWorkingDay']),
        reason: j['reason'] as String?,
        reviewedBy: j['reviewedBy'] as String?,
        reviewedAt: _date(j['reviewedAt']),
        reviewComment: j['reviewComment'] as String?,
        createdAt: _date(j['createdAt']),
      );
}

/// Notice period resolved from the employee's tenure slab.
class NoticePeriodInfo {
  NoticePeriodInfo({
    required this.noticePeriodDays,
    required this.resolved,
    this.tenureMonths,
  });

  final int noticePeriodDays;
  final bool resolved;
  final int? tenureMonths;

  factory NoticePeriodInfo.fromJson(Map<String, dynamic> j) => NoticePeriodInfo(
        noticePeriodDays: (j['noticePeriodDays'] as num?)?.toInt() ?? 0,
        resolved: j['resolved'] == true,
        tenureMonths: (j['tenureMonths'] as num?)?.toInt(),
      );
}
