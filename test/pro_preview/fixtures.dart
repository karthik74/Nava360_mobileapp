// Realistic fake backend data for the preview harness (Indian/NLPL context).
//
// Dates are RELATIVE to the day the goldens are generated (today = the real
// device date), because screens compare against DateTime.now() for "today",
// "this month", "due today" and so on. Shapes follow each repository's
// fromJson; the envelope is added by FakeApi.
import 'package:dio/dio.dart';

import 'fake_api.dart';

// ── dates ───────────────────────────────────────────────────────────────────

final DateTime _now = DateTime.now();
final DateTime _today = DateTime(_now.year, _now.month, _now.day);

String _two(int v) => v.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// yyyy-MM-dd for today + [offset] days.
String day(int offset) => ymd(_today.add(Duration(days: offset)));

/// Local ISO date-time (no zone) for today + [offset] days at [h]:[m].
String at(int offset, int h, [int m = 0]) {
  final d = _today.add(Duration(days: offset));
  return '${ymd(d)}T${_two(h)}:${_two(m)}:00';
}

// ── people ──────────────────────────────────────────────────────────────────

const _me = 42;

class _Emp {
  const _Emp(this.id, this.first, this.last, this.code, this.designation,
      this.branch, this.phone, this.state,
      [this.inH, this.inM, this.outH, this.outM]);
  final int id;
  final String first, last, code, designation, branch, phone, state;
  final int? inH, inM, outH, outM;
  String get name => '$first $last';
  String get email => '${first.toLowerCase()}.${last[0].toLowerCase()}@nlpl.in';
}

const _team = <_Emp>[
  _Emp(101, 'Ramesh', 'Kulkarni', 'NLPL0101', 'Field Officer', 'Dharwad',
      '+91 94481 22310', 'PUNCHED_IN', 9, 5),
  _Emp(102, 'Anitha', 'Shetty', 'NLPL0102', 'Senior Field Officer', 'Hubballi',
      '+91 99001 45872', 'PUNCHED_IN', 9, 22),
  _Emp(103, 'Mohan', 'Gowda', 'NLPL0103', 'Field Officer', 'Belagavi',
      '+91 97422 61094', 'PUNCHED_OUT', 9, 10, 17, 48),
  _Emp(104, 'Shweta', 'Patil', 'NLPL0104', 'Collection Officer', 'Dharwad',
      '+91 98864 30127', 'LEAVE'),
  _Emp(105, 'Prakash', 'Hiremath', 'NLPL0105', 'Field Officer', 'Hubballi',
      '+91 90080 77215', 'ABSENT'),
  _Emp(106, 'Lakshmi', 'Naik', 'NLPL0106', 'Branch Accountant', 'Dharwad',
      '+91 96325 11804', 'NOT_LOGGED_IN'),
  _Emp(107, 'Vinay', 'Desai', 'NLPL0107', 'Field Officer', 'Belagavi',
      '+91 95382 90461', 'PUNCHED_IN', 8, 52),
];

_Emp? _emp(int id) {
  for (final e in _team) {
    if (e.id == id) return e;
  }
  return null;
}

Map<String, Object?> _teamMember(_Emp e) => {
      'id': e.id,
      'employeeId': e.id,
      'name': e.name,
      'firstName': e.first,
      'lastName': e.last,
      'employeeCode': e.code,
      'designation': e.designation,
      'department': 'Operations',
      'phone': e.phone,
      'email': e.email,
      'branchLabel': e.branch,
      'state': e.state,
      'checkIn': e.inH == null ? null : at(0, e.inH!, e.inM ?? 0),
      'checkOut': e.outH == null ? null : at(0, e.outH!, e.outM ?? 0),
    };

Map<String, Object?> _employee(int id) {
  if (id == _me) {
    return {
      'id': _me,
      'firstName': 'Kavya',
      'lastName': 'Rao',
      'active': true,
      'employeeCode': 'NLPL0042',
      'email': 'kavya@nlpl.in',
      'phone': '+91 98450 12345',
      'gender': 'FEMALE',
      'designation': 'Branch Manager',
      'department': 'Operations',
      'businessVertical': 'Microfinance',
      'address': '14, Saptapur Main Road, Dharwad 580001',
      'branchLabel': 'Dharwad',
      'reportingManagerName': 'Suresh Angadi',
      'employeeType': 'PERMANENT',
      'joiningDate': '2021-06-14',
      'dateOfBirth': '1991-03-22',
      'profileImageUrl': null,
    };
  }
  final e = _emp(id) ?? _team.first;
  return {
    'id': id,
    'firstName': e.first,
    'lastName': e.last,
    'active': true,
    'employeeCode': e.code,
    'email': e.email,
    'phone': e.phone,
    'gender': const {104, 106, 102}.contains(e.id) ? 'FEMALE' : 'MALE',
    'designation': e.designation,
    'department': 'Operations',
    'businessVertical': 'Microfinance',
    'address': '${e.branch}, Karnataka',
    'branchLabel': e.branch,
    'reportingManagerName': 'Kavya Rao',
    'employeeType': 'PERMANENT',
    'joiningDate': '2023-0${(id % 9) + 1}-1${id % 9}',
    'dateOfBirth': '1996-0${(id % 9) + 1}-0${(id % 8) + 1}',
    'profileImageUrl': null,
  };
}

// ── attendance ──────────────────────────────────────────────────────────────

final _holidays = <String, String>{
  '${_today.year}-01-26': 'Republic Day',
  '${_today.year}-05-01': 'May Day',
  '${_today.year}-08-15': 'Independence Day',
  '${_today.year}-10-02': 'Gandhi Jayanti',
  '${_today.year}-10-20': 'Vijayadashami',
  '${_today.year}-11-01': 'Kannada Rajyotsava',
  '${_today.year}-11-09': 'Deepavali',
  '${_today.year}-12-25': 'Christmas',
};

bool _nonWorking(DateTime d) {
  if (d.weekday == DateTime.sunday) return true;
  if (d.weekday == DateTime.saturday) {
    final nth = ((d.day - 1) ~/ 7) + 1;
    return nth == 2 || nth == 4;
  }
  return false;
}

List<Map<String, Object?>> _attendance(int empId, DateTime from, DateTime to) {
  final out = <Map<String, Object?>>[];
  var id = empId * 1000;
  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    if (d.isAfter(_today)) break;
    if (_nonWorking(d) || _holidays.containsKey(ymd(d))) continue;
    final offset = d.difference(_today).inDays;
    final seed = (d.day * 7 + empId) % 11;
    String status = 'PRESENT';
    if (offset == -12) status = 'ON_LEAVE';
    if (offset != 0 && seed == 3) status = 'HALF_DAY';
    if (offset == -3) status = 'ABSENT';
    final isToday = offset == 0;
    final inM = 2 + (seed * 3) % 25;
    final record = <String, Object?>{
      'id': id++,
      'employeeId': empId,
      'employeeName': empId == _me ? 'Kavya Rao' : _emp(empId)?.name,
      'date': ymd(d),
      'status': status,
    };
    if (status == 'PRESENT' || status == 'HALF_DAY') {
      final outH = status == 'HALF_DAY' ? 13 : 18;
      final outM = (seed * 5) % 50;
      record.addAll({
        'checkIn': at(offset, 9, inM),
        'checkOut': isToday ? null : at(offset, outH, outM),
        'checkInLatitude': 15.4589 + seed / 10000,
        'checkInLongitude': 75.0078 + seed / 10000,
        'checkOutLatitude': isToday ? null : 15.4592,
        'checkOutLongitude': isToday ? null : 75.0081,
        'workingHours': isToday
            ? null
            : double.parse(
                ((outH * 60 + outM - (9 * 60 + inM)) / 60).toStringAsFixed(2)),
      });
    }
    out.add(record);
  }
  return out;
}

DateTime _q(RequestOptions r, String key, DateTime fallback) =>
    DateTime.tryParse(r.uri.queryParameters[key] ?? '') ?? fallback;

// ── leaves ──────────────────────────────────────────────────────────────────

Map<String, Object?> _leave(int id, int emp, String type, int from, int to,
        String status,
        {num? days,
        String? reason,
        String? half,
        String? reviewer,
        String? comment}) =>
    {
      'id': id,
      'employeeId': emp,
      'employeeName': emp == _me ? 'Kavya Rao' : _emp(emp)?.name,
      'leaveType': type,
      'fromDate': day(from),
      'toDate': day(to),
      'numberOfDays': days ?? (to - from + 1),
      'days': days ?? (to - from + 1),
      'halfDaySession': half,
      'reason': reason,
      'status': status,
      'reviewedByName': reviewer,
      'reviewComment': comment,
    };

List<Map<String, Object?>> _myLeaves() => [
      _leave(501, _me, 'CASUAL', 9, 10, 'PENDING',
          reason: 'Sister\'s wedding in Hubballi'),
      _leave(502, _me, 'SICK', -12, -12, 'APPROVED',
          reason: 'Viral fever', reviewer: 'Suresh Angadi'),
      _leave(503, _me, 'EARNED', -41, -37, 'APPROVED',
          reason: 'Family trip to Mysuru', reviewer: 'Suresh Angadi'),
      _leave(504, _me, 'CASUAL', -20, -20, 'REJECTED',
          days: 0.5,
          half: 'FIRST_HALF',
          reason: 'Bank work',
          reviewer: 'Suresh Angadi',
          comment: 'Month-end closing — please reschedule'),
    ];

List<Map<String, Object?>> _teamLeaves() => [
      _leave(601, 104, 'SICK', -1, 1, 'APPROVED',
          reason: 'Recovering from dengue', reviewer: 'Kavya Rao'),
      _leave(602, 101, 'CASUAL', 3, 4, 'PENDING',
          reason: 'Village jatre at Kalghatgi'),
      _leave(603, 102, 'EARNED', 14, 18, 'PENDING',
          reason: 'Deepavali at native place, Udupi'),
      _leave(604, 105, 'CASUAL', 0, 0, 'PENDING',
          days: 0.5, half: 'SECOND_HALF', reason: 'Child\'s school PTM'),
      _leave(605, 107, 'SICK', -8, -7, 'APPROVED',
          reason: 'Back pain', reviewer: 'Kavya Rao'),
      _leave(606, 103, 'CASUAL', -15, -15, 'REJECTED',
          reason: 'Personal work',
          reviewer: 'Kavya Rao',
          comment: 'Branch audit that day'),
    ];

List<Map<String, Object?>> _approvalSteps(int requesterLevelId) => [
      {
        'levelOrder': 1,
        'levelName': 'Branch Manager',
        'approverEmployeeId': _me,
        'approverEmployeeName': 'Kavya Rao',
        'status': 'PENDING',
        'actionComment': null,
        'actedAt': null,
      },
      {
        'levelOrder': 2,
        'levelName': 'Area Manager',
        'approverEmployeeId': 31,
        'approverEmployeeName': 'Suresh Angadi',
        'status': 'NOT_STARTED',
        'actionComment': null,
        'actedAt': null,
      },
    ];

const _leaveTypes = [
  {'id': 1, 'code': 'CASUAL', 'label': 'Casual Leave', 'active': true, 'allowedGender': 'ANY'},
  {'id': 2, 'code': 'SICK', 'label': 'Sick Leave', 'active': true, 'allowedGender': 'ANY'},
  {'id': 3, 'code': 'EARNED', 'label': 'Earned Leave', 'active': true, 'allowedGender': 'ANY'},
  {'id': 4, 'code': 'MATERNITY', 'label': 'Maternity Leave', 'active': true, 'allowedGender': 'FEMALE'},
  {'id': 5, 'code': 'PATERNITY', 'label': 'Paternity Leave', 'active': true, 'allowedGender': 'MALE'},
  {'id': 6, 'code': 'RESTRICTED_HOLIDAY', 'label': 'Restricted Holiday', 'active': true, 'allowedGender': 'ANY'},
];

Map<String, Object?> _balance() => {
      'year': _today.year,
      'balances': [
        {'leaveTypeCode': 'CASUAL', 'leaveTypeLabel': 'Casual Leave', 'allowanceDays': 12, 'usedDays': 4.5, 'balanceDays': 7.5},
        {'leaveTypeCode': 'SICK', 'leaveTypeLabel': 'Sick Leave', 'allowanceDays': 8, 'usedDays': 2, 'balanceDays': 6},
        {'leaveTypeCode': 'EARNED', 'leaveTypeLabel': 'Earned Leave', 'allowanceDays': 18, 'usedDays': 5, 'balanceDays': 13},
      ],
    };

// ── tasks ───────────────────────────────────────────────────────────────────

Map<String, Object?> _task(int id, String title, String status, String priority,
        {String type = 'INTERNAL',
        String? customer,
        int? due,
        int dueH = 17,
        int progress = 0,
        String category = 'Field visit',
        String assignedBy = 'Suresh Angadi',
        String? desc}) =>
    {
      'id': id,
      'taskCode': 'TSK-${2400 + id}',
      'title': title,
      'status': status,
      'priority': priority,
      'taskType': type,
      'customerName': customer,
      'customerId': customer == null ? null : 900 + id,
      'description': desc,
      'dueDate': due == null ? null : at(due, dueH),
      'dueTime': due == null ? null : '${_two(dueH)}:00',
      'startDate': at(-2, 10),
      'createdAt': at(-3, 11, 20),
      'completedAt': status == 'DONE' ? at(-1, 16, 40) : null,
      'assignedToId': _me,
      'assignedToName': 'Kavya Rao',
      'assignedById': 31,
      'assignedByName': assignedBy,
      'categoryName': category,
      'completionPercentage': progress,
      'requiresReview': status == 'IN_REVIEW',
      'allowSelfCompletion': true,
      'allowAttachments': true,
      'completionLocationRequired': false,
      'performableByCaller': true,
    };

List<Map<String, Object?>> _myTasks() => [
      _task(1, 'Collect overdue EMI — Gangamma Hosamani', 'IN_PROGRESS', 'URGENT',
          type: 'CUSTOMER', customer: 'Gangamma Hosamani', due: 0, dueH: 15,
          progress: 40, category: 'Collections',
          desc: 'Two instalments overdue (₹4,860). Visit at home, Saptapur.'),
      _task(2, 'JLG group meeting — Sri Renuka SHG', 'TODO', 'HIGH',
          type: 'CUSTOMER', customer: 'Sri Renuka SHG', due: 0, dueH: 11,
          category: 'Group meeting'),
      _task(3, 'Verify KYC documents for 6 new applicants', 'TODO', 'MEDIUM',
          due: 1, category: 'Onboarding'),
      _task(4, 'Branch cash audit — September', 'IN_REVIEW', 'HIGH',
          due: -1, progress: 100, category: 'Audit'),
      _task(5, 'Loan utilisation check — Basavaraj Kammar', 'TODO', 'MEDIUM',
          type: 'CUSTOMER', customer: 'Basavaraj Kammar', due: 2,
          category: 'Field visit'),
      _task(6, 'Submit weekly portfolio report', 'DONE', 'LOW',
          due: -2, progress: 100, category: 'Reporting'),
      _task(7, 'Disbursement camp at Alnavar', 'TODO', 'HIGH',
          due: 4, category: 'Disbursement'),
    ];

List<Map<String, Object?>> _teamTasks() {
  var id = 0;
  Map<String, Object?> t(String title, _Emp e, String status, String prio,
          int due, {String? customer, int progress = 0}) =>
      {
        'id': 7000 + ++id,
        'taskId': 3000 + id,
        'taskTitle': title,
        'taskCode': 'TSK-${3100 + id}',
        'taskType': customer == null ? 'INTERNAL' : 'CUSTOMER',
        'taskPriority': prio,
        'templateName': customer == null ? 'Internal task' : 'Customer visit',
        'customerName': customer,
        'status': status,
        'assigneeId': e.id,
        'assigneeName': e.name,
        'assigneeCode': e.code,
        'assigneeBranchName': e.branch,
        'assignedByName': 'Kavya Rao',
        'reviewerName': 'Kavya Rao',
        'dueDate': at(due, 17),
        'dueTime': '17:00',
        'progressPercentage': progress,
        'createdAt': at(-4, 10),
        'updatedAt': at(-1, 15, 30),
        'completedAt': status == 'DONE' ? at(-1, 15, 30) : null,
        'submittedAt': status == 'IN_REVIEW' ? at(-1, 14) : null,
      };
  return [
    t('Collect EMI — Mallappa Kotur', _team[0], 'IN_PROGRESS', 'URGENT', 0,
        customer: 'Mallappa Kotur', progress: 50),
    t('Centre meeting — Navodaya JLG', _team[1], 'TODO', 'HIGH', 0,
        customer: 'Navodaya JLG'),
    t('KYC re-verification — 4 members', _team[2], 'IN_REVIEW', 'MEDIUM', -1,
        progress: 100),
    t('PTP follow-up — Rudrappa Yaligar', _team[4], 'TODO', 'HIGH', 1,
        customer: 'Rudrappa Yaligar'),
    t('Cash deposit reconciliation', _team[5], 'DONE', 'MEDIUM', -1,
        progress: 100),
    t('Loan utilisation check — Fakirappa Madar', _team[6], 'IN_PROGRESS',
        'MEDIUM', 2,
        customer: 'Fakirappa Madar', progress: 30),
  ];
}

// ── customers ───────────────────────────────────────────────────────────────

List<Map<String, Object?>> _customers() {
  const rows = [
    ['Gangamma Hosamani', 'Dharwad', '+91 94480 11234', 'Saptapur, Dharwad', 'ACTIVE', true],
    ['Basavaraj Kammar', 'Dharwad', '+91 99645 20871', 'Kelgeri Road, Dharwad', 'ACTIVE', true],
    ['Sri Renuka SHG', 'Hubballi', '+91 97311 45620', 'Gokul Road, Hubballi', 'ACTIVE', true],
    ['Mallappa Kotur', 'Hubballi', '+91 90195 77302', 'Old Hubballi', 'ACTIVE', false],
    ['Shantavva Biradar', 'Belagavi', '+91 95910 38446', 'Tilakwadi, Belagavi', 'ACTIVE', true],
    ['Rudrappa Yaligar', 'Dharwad', '+91 96635 90124', 'Alnavar, Dharwad', 'OVERDUE', false],
    ['Fakirappa Madar', 'Belagavi', '+91 98443 61759', 'Shahapur, Belagavi', 'ACTIVE', true],
    ['Navodaya JLG', 'Hubballi', '+91 99016 22984', 'Unkal, Hubballi', 'ACTIVE', false],
    ['Parvati Kurubar', 'Dharwad', '+91 93412 50473', 'Mugad, Dharwad', 'CLOSED', false],
  ];
  var i = 0;
  return [
    for (final r in rows)
      {
        'id': 900 + ++i,
        'customerName': r[0],
        'customerCode': 'CUS-${(r[1] as String).substring(0, 3).toUpperCase()}-${(10230 + i * 37)}',
        'mobileNumber': r[2],
        'email': null,
        'address': r[3],
        'branchId': 3,
        'branchName': r[1],
        'assignedEmployeeId': _team[i % _team.length].id,
        'assignedEmployeeName': _team[i % _team.length].name,
        'status': r[4],
        'createdBy': 'kavya.r',
        'createdAt': at(-120 + i * 9, 11),
        'updatedAt': at(-i, 16),
        'latitude': r[5] == true ? 15.45 + i / 100 : null,
        'longitude': r[5] == true ? 75.00 + i / 100 : null,
        'locationStatus': r[5] == true ? 'APPROVED' : null,
        'customFields': {'loanAccount': 'LN00${48210 + i}'},
      }
  ];
}

// ── chat ────────────────────────────────────────────────────────────────────

Map<String, Object?> _contact(int id, String name, String designation,
        {bool online = false, String status = 'WORKING'}) =>
    {
      'employeeId': id,
      'name': name,
      'designation': designation,
      'employeeCode': 'NLPL${id.toString().padLeft(4, '0')}',
      'avatarUrl': null,
      'department': 'Operations',
      'status': status,
      'online': online,
    };

List<Map<String, Object?>> _conversations() {
  final me = _contact(_me, 'Kavya Rao', 'Branch Manager', online: true);
  final nowM = _now;
  String ago(Duration d) => nowM.subtract(d).toIso8601String();
  return [
    {
      'id': 11,
      'type': 'DIRECT',
      'title': 'Ramesh Kulkarni',
      'otherEmployeeId': 101,
      'members': [me, _contact(101, 'Ramesh Kulkarni', 'Field Officer', online: true)],
      'lastMessagePreview': 'Collected ₹4,860 from Gangamma, receipt uploaded 👍',
      'lastMessageAt': ago(const Duration(minutes: 4)),
      'unreadCount': 2,
      'otherStatus': 'WORKING',
      'otherOnline': true,
    },
    {
      'id': 12,
      'type': 'GROUP',
      'title': 'Dharwad Branch Team',
      'createdByEmployeeId': _me,
      'members': [
        me,
        _contact(101, 'Ramesh Kulkarni', 'Field Officer'),
        _contact(104, 'Shweta Patil', 'Collection Officer'),
        _contact(106, 'Lakshmi Naik', 'Branch Accountant'),
      ],
      'lastMessagePreview': 'Lakshmi: Cash deposited at SBI Dharwad main branch',
      'lastMessageAt': ago(const Duration(minutes: 26)),
      'unreadCount': 5,
    },
    {
      'id': 13,
      'type': 'DIRECT',
      'title': 'Anitha Shetty',
      'otherEmployeeId': 102,
      'members': [me, _contact(102, 'Anitha Shetty', 'Senior Field Officer', online: true)],
      'lastMessagePreview': 'Sri Renuka SHG meeting moved to 11:30',
      'lastMessageAt': ago(const Duration(hours: 1, minutes: 12)),
      'unreadCount': 0,
      'otherStatus': 'WORKING',
      'otherOnline': true,
    },
    {
      'id': 14,
      'type': 'DIRECT',
      'title': 'Suresh Angadi',
      'otherEmployeeId': 31,
      'members': [me, _contact(31, 'Suresh Angadi', 'Area Manager')],
      'lastMessagePreview': 'Please share the September PAR report by EOD',
      'lastMessageAt': ago(const Duration(hours: 3)),
      'unreadCount': 1,
      'otherStatus': 'WORKING',
      'otherOnline': false,
    },
    {
      'id': 15,
      'type': 'GROUP',
      'title': 'Hubballi–Dharwad Collections',
      'createdByEmployeeId': 31,
      'members': [
        me,
        _contact(31, 'Suresh Angadi', 'Area Manager'),
        _contact(102, 'Anitha Shetty', 'Senior Field Officer'),
        _contact(105, 'Prakash Hiremath', 'Field Officer'),
      ],
      'lastMessagePreview': 'Suresh: FTOD at 96.4% — great work everyone',
      'lastMessageAt': ago(const Duration(days: 1, hours: 2)),
      'unreadCount': 0,
    },
    {
      'id': 16,
      'type': 'DIRECT',
      'title': 'Shweta Patil',
      'otherEmployeeId': 104,
      'members': [me, _contact(104, 'Shweta Patil', 'Collection Officer', status: 'ON_LEAVE')],
      'lastMessagePreview': 'Thank you madam, will join on Thursday',
      'lastMessageAt': ago(const Duration(days: 2, hours: 5)),
      'unreadCount': 0,
      'otherStatus': 'ON_LEAVE',
      'otherOnline': false,
    },
    {
      'id': 17,
      'type': 'DIRECT',
      'title': 'Mohan Gowda',
      'otherEmployeeId': 103,
      'members': [me, _contact(103, 'Mohan Gowda', 'Field Officer')],
      'lastMessagePreview': 'You: Ok, go ahead with the Belagavi camp',
      'lastMessageAt': ago(const Duration(days: 4)),
      'unreadCount': 0,
      'otherStatus': 'OFF',
      'otherOnline': false,
    },
  ];
}

// ── travel ──────────────────────────────────────────────────────────────────

List<Map<String, Object?>> _claims() {
  Map<String, Object?> c(int id, String title, String status, num amount,
          int submitted,
          {bool violation = false, int level = 1}) =>
      {
        'id': id,
        'claimCode': 'TC-${_today.year}-${(310 + id).toString().padLeft(5, '0')}',
        'employeeId': _me,
        'employeeName': 'Kavya Rao',
        'title': title,
        'status': status,
        'currentLevel': level,
        'totalClaimedAmount': amount,
        'hasPolicyViolation': violation,
        'submittedAt': status == 'DRAFT' ? null : at(submitted, 18, 20),
      };
  return [
    c(1, 'Branch visit — Belagavi', 'SUBMITTED', 2840, -1),
    c(2, 'Area review meeting, Hubballi', 'LEVEL_1_APPROVED', 1260, -6, level: 2),
    c(3, 'Customer visits — Kalghatgi & Alnavar', 'DRAFT', 780, 0),
    c(4, 'Audit support — Gadag branch', 'SENT_BACK', 3415.5, -9, violation: true),
    c(5, 'Training at Bengaluru head office', 'SETTLED', 6450, -24, level: 3),
    c(6, 'Disbursement camp — Navalgund', 'APPROVED', 1920, -15, level: 3),
    c(7, 'Hotel stay — Sirsi review', 'REJECTED', 5200, -30, violation: true),
  ];
}

// ── helpdesk ────────────────────────────────────────────────────────────────

List<Map<String, Object?>> _tickets(String scope) {
  Map<String, Object?> t(int id, String title, String category, String status,
          String priority, int created,
          {String? assignee, bool breached = false}) =>
      {
        'id': id,
        'ticketNumber': 'HD-${_today.year}-${(400 + id).toString().padLeft(5, '0')}',
        'title': title,
        'category': category,
        'status': status,
        'priority': priority,
        'raisedByName': scope == 'mine' ? 'Kavya Rao' : 'Ramesh Kulkarni',
        'assignedToName': assignee,
        'branchName': 'Dharwad',
        'department': 'Operations',
        'resolutionDueAt': at(created + 3, 18),
        'responseBreached': false,
        'resolutionBreached': breached,
        'escalationLevel': breached ? 1 : 0,
        'createdAt': at(created, 10, 15),
        'updatedAt': at(created < -1 ? created + 1 : 0, 12, 40),
      };
  return [
    t(12, 'Biometric device not syncing at Dharwad branch', 'IT Hardware',
        'IN_PROGRESS', 'HIGH', -1, assignee: 'Naveen (IT Support)'),
    t(11, 'September payslip not visible in app', 'Payroll', 'OPEN', 'MEDIUM',
        0),
    t(9, 'Laptop battery drains within an hour', 'IT Hardware', 'ON_HOLD',
        'LOW', -6, assignee: 'Naveen (IT Support)', breached: true),
    t(7, 'Branch printer toner replacement', 'Admin', 'RESOLVED', 'LOW', -12,
        assignee: 'Raghavendra (Admin)'),
    t(4, 'VPN access for branch accounting system', 'IT Access', 'CLOSED',
        'CRITICAL', -20, assignee: 'Naveen (IT Support)'),
  ];
}

// ── team (regularizations / resignations) ───────────────────────────────────

List<Map<String, Object?>> _regularizations() => [
      {
        'id': 801,
        'employeeId': 105,
        'employeeName': 'Prakash Hiremath',
        'date': day(-3),
        'requestedStatus': 'PRESENT',
        'requestedCheckIn': '09:20',
        'requestedCheckOut': '18:05',
        'reason': 'Phone battery died during field visits at Unkal',
        'status': 'PENDING',
      },
      {
        'id': 802,
        'employeeId': 103,
        'employeeName': 'Mohan Gowda',
        'date': day(-6),
        'requestedStatus': 'PRESENT',
        'requestedCheckIn': '09:05',
        'requestedCheckOut': '17:50',
        'reason': 'GPS not available at Kittur centre',
        'status': 'PENDING',
      },
      {
        'id': 803,
        'employeeId': 101,
        'employeeName': 'Ramesh Kulkarni',
        'date': day(-10),
        'requestedStatus': 'HALF_DAY',
        'requestedCheckIn': '13:30',
        'requestedCheckOut': '18:10',
        'reason': 'Hospital visit in the morning',
        'status': 'APPROVED',
      },
    ];

List<Map<String, Object?>> _resignationApprovals() => [
      {
        'step': {
          'id': 41,
          'levelOrder': 1,
          'levelName': 'Reporting Manager',
          'stepStatus': 'PENDING',
          'approverEmployeeId': _me,
          'approverEmployeeName': 'Kavya Rao',
          'approverDesignation': 'Branch Manager',
          'remarks': null,
          'actionAt': null,
        },
        'resignation': {
          'id': 9,
          'status': 'IN_APPROVAL',
          'employeeName': 'Prakash Hiremath',
          'employeeCode': 'NLPL0105',
          'designation': 'Field Officer',
          'department': 'Operations',
          'branch': 'Hubballi',
          'resignationDate': day(-2),
          'noticePeriodDays': 30,
          'lastWorkingDay': day(28),
          'reason': 'Pursuing higher studies (MBA) in Bengaluru',
          'createdAt': at(-2, 10, 5),
        },
      },
    ];

// ── registration ────────────────────────────────────────────────────────────

void registerDefaultFixtures(FakeApi api) {
  const id = r'(\d+)';

  // Identity / profile
  api.getFn('/api/employees/$id',
      (_, m) => _employee(int.parse(m.group(1)!)));
  api.get('/api/employees/my-team/full/today-status',
      [for (final e in _team) _teamMember(e)]);
  api.get('/api/employees/my-team', [for (final e in _team) _teamMember(e)]);
  api.getFn('/api/employees/$id/documents', (_, m) => [
        {'id': 1, 'docType': 'AADHAAR', 'docTypeLabel': 'Aadhaar card', 'fileName': 'aadhaar.pdf', 'uploadedBy': 'HR Desk', 'createdAt': at(-300, 11)},
        {'id': 2, 'docType': 'PAN', 'docTypeLabel': 'PAN card', 'fileName': 'pan.pdf', 'uploadedBy': 'HR Desk', 'createdAt': at(-300, 11)},
        {'id': 3, 'docType': 'APPOINTMENT', 'docTypeLabel': 'Appointment letter', 'fileName': 'appointment.pdf', 'uploadedBy': 'HR Desk', 'createdAt': at(-400, 11)},
      ]);
  api.getFn('/api/employees/$id/timeline', (_, m) => page([
        {
          'id': 1,
          'action': 'UPDATED',
          'actorName': 'Kavya Rao',
          'actorUsername': 'kavya.r',
          'createdAt': at(-20, 12),
          'changes': [
            {'field': 'designation', 'label': 'Designation', 'oldValue': 'Field Officer', 'newValue': 'Senior Field Officer'}
          ],
        },
      ]));
  api.get('/api/me/documents', const []);
  api.get('/api/employees/me/documents', const []);
  api.get('/api/document-types', const []);

  // Attendance
  api.getFn('/api/attendance/employee/$id', (r, m) {
    final emp = int.parse(m.group(1)!);
    final from = _q(r, 'from', DateTime(_today.year, _today.month, 1));
    final to = _q(r, 'to', _today);
    return page(_attendance(emp, from, to).reversed.toList(), size: 100);
  });
  api.get('/api/attendance-settings', {'cycleStartDay': 1});
  api.getFn('/api/holidays/my', (_, __) => [
        for (final e in _holidays.entries)
          {'date': e.key, 'name': e.value, 'optional': false}
      ]);
  api.get('/api/non-working-days/applicable', [
    {'dayOfWeek': 'SUNDAY', 'week': 'ALL', 'active': true},
    {'dayOfWeek': 'SATURDAY', 'week': 'SECOND', 'active': true},
    {'dayOfWeek': 'SATURDAY', 'week': 'FOURTH', 'active': true},
  ]);
  api.getFn('/api/regularizations', (_, __) => page([
        {'id': 811, 'employeeId': _me, 'date': day(-3), 'status': 'PENDING'},
      ]));
  api.getFn('/api/regularizations/team', (_, __) => page(_regularizations()));
  api.getFn('/api/regularizations/pending-my-approval',
      (_, __) => _regularizations().where((r) => r['status'] == 'PENDING').toList());
  api.getFn('/api/regularizations/$id/approval-steps',
      (_, m) => _approvalSteps(int.parse(m.group(1)!)));
  api.getFn('/api/attendance/locations/team/$id', (_, m) => [
        for (var i = 0; i < 9; i++)
          {
            'recordedAt': at(0, 9 + i ~/ 2, (i * 25) % 60),
            'latitude': 15.4589 + i * 0.004,
            'longitude': 75.0078 + i * 0.003,
            'accuracyMeters': 8 + i,
            'speedMps': i.isEven ? 0 : 6.5,
            'type': 'PING',
            'referenceTitle': i == 3 ? 'Visit · Gangamma Hosamani' : null,
          }
      ]);
  api.getFn('/api/attendance/locations/team/$id/live', (_, __) => {
        'state': 'ON',
        'latitude': 15.4712,
        'longitude': 75.0201,
        'responded': true,
        'pending': false,
        'respondedAt': _now.subtract(const Duration(minutes: 3)).toIso8601String(),
      });
  api.getFn('/api/attendance/locations/status/$id/history', (_, __) => [
        {'id': 3, 'occurredAt': at(0, 9, 5), 'state': 'ON', 'latitude': 15.4589, 'longitude': 75.0078},
        {'id': 2, 'occurredAt': at(-1, 13, 40), 'state': 'LOCATION_OFF'},
        {'id': 1, 'occurredAt': at(-1, 13, 55), 'state': 'ON'},
      ]);

  // Leaves
  api.getFn('/api/leaves/employee/$id', (_, m) {
    final emp = int.parse(m.group(1)!);
    if (emp == _me) return page(_myLeaves(), size: 50);
    return page(_teamLeaves().where((l) => l['employeeId'] == emp).toList(),
        size: 50);
  });
  api.getFn('/api/leaves/team', (_, __) => page(_teamLeaves(), size: 50));
  api.getFn('/api/leaves/pending-my-approval',
      (_, __) => _teamLeaves().where((l) => l['status'] == 'PENDING').toList());
  api.getFn('/api/leaves/$id/approval-steps',
      (_, m) => _approvalSteps(int.parse(m.group(1)!)));
  api.getFn('/api/leaves/balance/$id', (_, __) => _balance());
  api.get('/api/leave-types', _leaveTypes);

  // Tasks
  api.getFn('/api/tasks/employee/$id', (_, m) {
    final emp = int.parse(m.group(1)!);
    final list = emp == _me
        ? _myTasks()
        : _myTasks()
            .map((t) => {...t, 'assignedToId': emp, 'assignedToName': _emp(emp)?.name})
            .toList();
    return page(list, size: 200);
  });
  api.get('/api/tasks/dashboard', {
    'totalTasks': 7,
    'myPending': 4,
    'myInProgress': 1,
    'myInReview': 1,
    'myOverdue': 1,
    'myDoneThisMonth': 9,
    'pendingReview': 2,
    'createdByMe': 6,
    'urgentTasks': 1,
  });
  api.getFn('/api/tasks/team', (_, __) => page(_teamTasks(), size: 300));
  api.get('/api/task-templates', page(const []));

  // Customers
  api.getFn('/api/customers', (_, __) => page(_customers()));

  // Chat
  api.getFn('/api/chat/conversations', (_, __) => _conversations());

  // Drawer badges / content lists
  api.get('/api/announcements/my/unread-count', 3);
  api.get('/api/policies/my', [
    {'id': 1, 'title': 'Code of Conduct ${_today.year}', 'category': 'HR', 'effectiveDate': '${_today.year}-04-01', 'versionNumber': '3.0', 'versionId': 13, 'publishedAt': at(-60, 10), 'allowDownload': true, 'read': true},
    {'id': 2, 'title': 'Field Travel & Conveyance Policy', 'category': 'Finance', 'effectiveDate': day(-5), 'versionNumber': '2.1', 'versionId': 22, 'publishedAt': at(-5, 10), 'allowDownload': false, 'read': false},
    {'id': 3, 'title': 'Cash Handling SOP', 'category': 'Operations', 'effectiveDate': day(-2), 'versionNumber': '1.4', 'versionId': 31, 'publishedAt': at(-2, 10), 'allowDownload': false, 'read': false},
  ]);

  // Team
  api.getFn('/api/resignations/my-approvals', (_, __) => _resignationApprovals());

  // Employee detail tabs
  api.getFn('/api/assets/employee/$id', (_, m) => [
        {
          'id': 1,
          'assetId': 55,
          'assetName': 'Lenovo ThinkPad E14',
          'assetTag': 'NLPL-LT-0412',
          'serialNumber': 'PF3K9X2M',
          'assetType': 'Laptop',
          'brand': 'Lenovo',
          'model': 'E14 Gen 5',
          'category': 'IT',
          'employeeId': int.parse(m.group(1)!),
          'assignedDate': day(-210),
          'acknowledgementStatus': 'ACKNOWLEDGED',
          'status': 'ACTIVE',
        },
        {
          'id': 2,
          'assetId': 81,
          'assetName': 'Samsung Galaxy M14',
          'assetTag': 'NLPL-MB-1180',
          'imeiNumber': '356938035643809',
          'assetType': 'Mobile',
          'brand': 'Samsung',
          'model': 'M14 5G',
          'category': 'IT',
          'employeeId': int.parse(m.group(1)!),
          'assignedDate': day(-150),
          'acknowledgementStatus': 'ACKNOWLEDGED',
          'status': 'ACTIVE',
        },
      ]);
  api.getFn('/api/performance/employee/$id', (_, m) => {
        'employeeId': int.parse(m.group(1)!),
        'employeeCode': 'NLPL0101',
        'employeeName': 'Ramesh Kulkarni',
        'lastSyncedAt': at(0, 6),
        'availablePeriods': [
          {'month': _today.month == 1 ? 12 : _today.month - 1, 'year': _today.month == 1 ? _today.year - 1 : _today.year, 'label': 'Last month'},
        ],
        'summary': {
          'employeeName': 'Ramesh Kulkarni',
          'branchName': 'Dharwad',
          'areaName': 'Dharwad Area',
          'divisionName': 'North Karnataka',
          'regionName': 'Karnataka',
          'month': _today.month == 1 ? 12 : _today.month - 1,
          'year': _today.month == 1 ? _today.year - 1 : _today.year,
          'dbTarget': 2500000,
          'dbAchievement': 2210000,
          'dbPercentage': 0.884,
          'regularCollectionPercentage': 0.972,
          'oneToNinetyPercentage': 0.915,
          'onDatePercentage': 0.948,
          'npaRecoveryPercentage': 0.41,
          'overallPercentage': 0.902,
          'nlplRank': 37,
          'branchRank': 2,
          'branchGrade': 'A',
        },
      });

  // Travel
  api.getFn('/api/travel/claims/my', (_, __) => page(_claims(), size: 100));

  // Helpdesk
  api.getFn('/api/helpdesk/tickets/(mine|assigned)',
      (_, m) => page(_tickets(m.group(1)!)));

  // Auth flows (login screen steps)
  api.post('/api/auth/first-login/start', {
    'requiresOtp': true,
    'maskedMobile': '+91 ••••• ••345',
    'message': 'OTP sent to your registered mobile',
  });
  api.post('/api/auth/forgot-password',
      {'maskedPhone': '+91 ••••• ••345', 'expiresInSeconds': 300});

  // Branding (only if something refreshes it)
  api.get('/api/public/branding', {
    'productName': 'Nava360',
    'companyName': 'Navachetana Livelihoods Pvt Ltd',
    'companyShortName': 'NLPL',
    'primaryColor': '#00748C',
    'features': {'FEATURE_OPENING_INSIGHTS': false},
  });
}
