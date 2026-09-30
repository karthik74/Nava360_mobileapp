import 'package:intl/intl.dart';

import '../../core/theme.dart';

/// Promise-to-pay (PTP) follow-ups captured by the telecalling CRM and routed
/// to the field officer (or the branch manager when the officer is unmapped).
/// Wire shapes mirror `/api/crm-ptp/mine` and `/api/crm-ptp/mine/summary`.

/// The list filters the backend understands. Order = chip order on screen.
enum PtpFilter {
  all('ALL', 'All'),
  dueToday('DUE_TODAY', 'Due today'),
  dueTomorrow('DUE_TOMORROW', 'Due tomorrow'),
  broken('BROKEN', 'Broken'),
  upcoming('UPCOMING', 'Upcoming'),
  kept('KEPT', 'Kept');

  const PtpFilter(this.api, this.label);

  /// Query value for `?filter=` (also accepted in the `/ptp?filter=` deep link
  /// so a "due today" push can open straight on that chip).
  final String api;
  final String label;

  static PtpFilter fromApi(String? value) {
    final v = value?.trim().toUpperCase();
    for (final f in PtpFilter.values) {
      if (f.api == v) return f;
    }
    return PtpFilter.all;
  }

  /// What to say when a filter has nothing — the field officer should read
  /// "nothing to chase" rather than "something failed".
  String get emptyMessage {
    switch (this) {
      case PtpFilter.all:
        return 'No open PTPs.\nNew promises from the call centre will show up here.';
      case PtpFilter.dueToday:
        return 'No PTPs due today.';
      case PtpFilter.dueTomorrow:
        return 'No PTPs due tomorrow.';
      case PtpFilter.broken:
        return 'No broken PTPs.';
      case PtpFilter.upcoming:
        return 'No PTPs due after tomorrow.';
      case PtpFilter.kept:
        return 'No PTPs kept in the last 30 days.';
    }
  }
}

/// Who the server decided the caller is looking at: their own customers (FO),
/// their whole branch (BM) or everything (ops / management).
enum PtpScope {
  fo,
  branch,
  all;

  static PtpScope fromApi(String? value) {
    switch (value?.toUpperCase()) {
      case 'BRANCH':
        return PtpScope.branch;
      case 'ALL':
        return PtpScope.all;
      default:
        return PtpScope.fo;
    }
  }

  String get label {
    switch (this) {
      case PtpScope.fo:
        return 'Your customers';
      case PtpScope.branch:
        return 'Your branch';
      case PtpScope.all:
        return 'All branches';
    }
  }
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

num? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

int _int(dynamic v) => _num(v)?.toInt() ?? 0;

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

class CrmPtp {
  final int id;
  final String status; // OPEN / BROKEN / KEPT / CANCELLED / CLOSED
  final String? module; // FTOD, 1-90, NPA, PRE …
  final DateTime? promisedDate;
  final num? amount;
  final String customerName;
  final String? phone;
  final String? accountId;
  final String? clientId;
  final String? branchName;
  final String? officerText;
  final String? fieldOfficerName;
  final String? fieldOfficerCode;
  final int? taskId;
  final String? taskCode;
  final String? telecaller;
  final String? callNote;
  final int rescheduleCount;
  final DateTime? closedAt;

  const CrmPtp({
    required this.id,
    required this.status,
    required this.customerName,
    this.module,
    this.promisedDate,
    this.amount,
    this.phone,
    this.accountId,
    this.clientId,
    this.branchName,
    this.officerText,
    this.fieldOfficerName,
    this.fieldOfficerCode,
    this.taskId,
    this.taskCode,
    this.telecaller,
    this.callNote,
    this.rescheduleCount = 0,
    this.closedAt,
  });

  factory CrmPtp.fromJson(Map<String, dynamic> j) => CrmPtp(
        id: _int(j['id']),
        status: (_str(j['status']) ?? 'OPEN').toUpperCase(),
        module: _str(j['module']),
        promisedDate: _date(j['promisedDate']),
        amount: _num(j['amount']),
        customerName: _str(j['customerName']) ?? 'Customer',
        phone: _str(j['phone']),
        accountId: _str(j['accountId']),
        clientId: _str(j['clientId']),
        branchName: _str(j['branchName']),
        officerText: _str(j['officerText']),
        fieldOfficerName: _str(j['fieldOfficerName']),
        fieldOfficerCode: _str(j['fieldOfficerCode']),
        taskId: _num(j['taskId'])?.toInt(),
        taskCode: _str(j['taskCode']),
        telecaller: _str(j['telecaller']),
        callNote: _str(j['callNote']),
        rescheduleCount: _int(j['rescheduleCount']),
        closedAt: _date(j['closedAt']),
      );

  /// The officer to show a branch manager: the mapped employee when the CRM
  /// officer was resolved, otherwise the raw CRM text so the row is never blank.
  String? get officerLabel => fieldOfficerName ?? officerText;

  /// Account id is what the field officer quotes at the door; client id only
  /// when the CRM had no account on the call.
  String? get reference => accountId ?? clientId;
}

class PtpSummary {
  final PtpScope scope;
  final int all;
  final int dueToday;
  final int dueTomorrow;
  final int broken;
  final int upcoming;
  final int kept;
  final num dueTodayAmount;

  const PtpSummary({
    this.scope = PtpScope.fo,
    this.all = 0,
    this.dueToday = 0,
    this.dueTomorrow = 0,
    this.broken = 0,
    this.upcoming = 0,
    this.kept = 0,
    this.dueTodayAmount = 0,
  });

  factory PtpSummary.fromJson(Map<String, dynamic> j) => PtpSummary(
        scope: PtpScope.fromApi(_str(j['scope'])),
        all: _int(j['all']),
        dueToday: _int(j['dueToday']),
        dueTomorrow: _int(j['dueTomorrow']),
        broken: _int(j['broken']),
        upcoming: _int(j['upcoming']),
        kept: _int(j['kept']),
        dueTodayAmount: _num(j['dueTodayAmount']) ?? 0,
      );

  int countFor(PtpFilter f) {
    switch (f) {
      case PtpFilter.all:
        return all;
      case PtpFilter.dueToday:
        return dueToday;
      case PtpFilter.dueTomorrow:
        return dueTomorrow;
      case PtpFilter.broken:
        return broken;
      case PtpFilter.upcoming:
        return upcoming;
      case PtpFilter.kept:
        return kept;
    }
  }
}

/// One page of the backend `PageResponse`.
class PtpPage {
  final List<CrmPtp> items;
  final int page;
  final bool last;
  final int totalElements;

  const PtpPage({
    required this.items,
    required this.page,
    required this.last,
    required this.totalElements,
  });

  factory PtpPage.fromJson(Map<String, dynamic> j) {
    final content = (j['content'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => CrmPtp.fromJson(e.cast<String, dynamic>()))
        .toList();
    return PtpPage(
      items: content,
      page: _int(j['page']),
      // Missing `last` ⇒ treat as the final page so "load more" never loops.
      last: j['last'] != false,
      totalElements: _int(j['totalElements']),
    );
  }
}

// ── Formatting (matches the backend push wording: "EMI ₹7,250") ────────────

final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');

/// Whole rupees with Indian digit grouping, e.g. 125000 → "₹1,25,000".
/// Same rounding as CrmPtpNotifier.rupees() so push text and screen agree.
String ptpRupees(num amount) => '₹${_inr.format(amount.round())}';

/// "<name> Branch" unless the name already says branch (CrmPtpNotifier.branchLabel).
String? ptpBranchLabel(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  return n.toLowerCase().contains('branch') ? n : '$n Branch';
}

/// "Promised 30 Sep" — the year only when it is not the current one.
String ptpPromisedLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final fmt = date.year == today.year ? DateFormat('d MMM') : DateFormat('d MMM yyyy');
  return 'Promised ${fmt.format(date)}';
}

/// Badge for a row. OPEN promises are bucketed against the phone's date the
/// same way the backend filters do (today / tomorrow / later); an OPEN
/// promise already in the past has not been marked broken by the sync yet, so
/// it is called out as overdue rather than hidden.
StatusTone ptpBadge(CrmPtp p, {DateTime? now}) {
  switch (p.status) {
    case 'BROKEN':
      return const StatusTone(AppColors.danger, 'Broken');
    case 'KEPT':
      return const StatusTone(AppColors.success, 'Kept');
    case 'CANCELLED':
      return const StatusTone(AppColors.muted, 'Cancelled');
    case 'CLOSED':
      return const StatusTone(AppColors.muted, 'Closed');
  }
  final d = p.promisedDate;
  if (d == null) return const StatusTone(AppColors.info, 'Open');
  final t = now ?? DateTime.now();
  // UTC calendar days so a DST shift can never make "tomorrow" 0.96 days away.
  final today = DateTime.utc(t.year, t.month, t.day);
  final day = DateTime.utc(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff < 0) return const StatusTone(AppColors.danger, 'Overdue');
  if (diff == 0) return const StatusTone(AppColors.warning, 'Due today');
  if (diff == 1) return const StatusTone(AppColors.info, 'Due tomorrow');
  return StatusTone(AppColors.primary, 'Upcoming');
}
