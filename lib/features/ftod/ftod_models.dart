// ─────────────────────────────────────────────────────────────────────────────
//  FTOD (first-time overdue) collections — models + formatting helpers.
//
//  Backed by GET /api/ftod/mine/distribution and GET /api/ftod/mine. The point
//  of the screen is the DATE-WISE distribution: customers whose EMI falls due
//  on the 1st often pay on the 4th or 5th, and some pay only part. So every
//  due date carries the days money actually came in, not just a paid/unpaid
//  flag.
//
//  Kept free of Flutter imports so the parsing and wording can be unit-tested
//  as plain Dart (test/ftod_models_test.dart).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:intl/intl.dart';

// ── Parsing helpers (tolerant: the backend sends BigDecimal as number, but an
//    older build or a proxy may stringify it) ────────────────────────────────

double _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _int(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// "2026-09-01" (or a full ISO timestamp) → a local, date-only DateTime.
DateTime? parseFtodDate(dynamic v) {
  final s = _str(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

// ── Formatting ───────────────────────────────────────────────────────────────

final NumberFormat _inWhole =
    NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);

/// Indian digit grouping in whole rupees: 725000 → "₹7,25,000", 7250.5 →
/// "₹7,251". Rounded like the push text (CrmPtpNotifier.rupees, HALF_UP) and
/// the PTP screen, so the screen never disagrees with the alert that opened it.
String ftodRupees(num? value) {
  final v = (value ?? 0).toDouble();
  return '₹${_inWhole.format(v.round())}';
}

/// Plain Indian-grouped count, e.g. 1234 → "1,234".
String ftodCount(num value) => _inWhole.format(value);

const List<String> _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _monthFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// DateTime → "01 Sep". Built by hand (not DateFormat) so it needs no locale
/// initialisation and reads the same on every device language.
String ftodDay(DateTime? d) {
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')} ${_mon[d.month - 1]}';
}

/// DateTime → the API's "YYYY-MM-DD".
String ftodIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// DateTime → the API's month key "YYYY-MM".
String ftodMonthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// DateTime → "September 2026" for the month switcher.
String ftodMonthLabel(DateTime d) => '${_monthFull[d.month - 1]} ${d.year}';

/// First day of the month [delta] months away from [month].
DateTime ftodShiftMonth(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta, 1);

/// "Tumkur" → "Tumkur Branch"; a name that already says branch is left alone.
/// Same rule as the backend's CrmPtpNotifier.branchLabel().
String ftodBranchLabel(String? name) {
  final n = name?.trim() ?? '';
  if (n.isEmpty) return '';
  return n.toLowerCase().contains('branch') ? n : '$n Branch';
}

/// Whole calendar days from [from] to [to], counted on UTC midnights so a
/// device in a DST timezone can't turn a 23-hour day into "0 days".
int ftodDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// "1 day" / "3 days".
String ftodDays(int n) => '$n ${n == 1 ? 'day' : 'days'}';

/// collected / due as a whole percentage (0 when nothing was due).
int ftodPercent(num collected, num due) {
  if (due <= 0) return 0;
  return (collected / due * 100).round().clamp(0, 100);
}

// ── Status ───────────────────────────────────────────────────────────────────

/// The backend's FtodStatus, in the order the customer list is sorted: money
/// still owed first, cleared accounts last.
enum FtodStatus {
  pending('PENDING', 'Pending'),
  partial('PARTIAL', 'Partial'),
  paidLate('PAID_LATE', 'Paid late'),
  paidOnTime('PAID_ON_TIME', 'On time');

  const FtodStatus(this.api, this.label);

  /// Value sent to / received from the API.
  final String api;

  /// Short chip label.
  final String label;

  static FtodStatus parse(dynamic v) {
    final s = v?.toString().trim().toUpperCase();
    for (final st in values) {
      if (st.api == s) return st;
    }
    return FtodStatus.pending;
  }
}

// ── Distribution ─────────────────────────────────────────────────────────────

/// The four status counts shared by the month totals and each due date.
class FtodStatusCounts {
  const FtodStatusCounts({
    this.paidOnTime = 0,
    this.paidLate = 0,
    this.partial = 0,
    this.pending = 0,
  });

  final int paidOnTime;
  final int paidLate;
  final int partial;
  final int pending;

  factory FtodStatusCounts.fromJson(Map<String, dynamic> j) => FtodStatusCounts(
        paidOnTime: _int(j['paidOnTime']),
        paidLate: _int(j['paidLate']),
        partial: _int(j['partial']),
        pending: _int(j['pending']),
      );

  int get total => paidOnTime + paidLate + partial + pending;

  int of(FtodStatus s) {
    switch (s) {
      case FtodStatus.pending:
        return pending;
      case FtodStatus.partial:
        return partial;
      case FtodStatus.paidLate:
        return paidLate;
      case FtodStatus.paidOnTime:
        return paidOnTime;
    }
  }
}

/// Month totals for the caller's scope.
class FtodTotals {
  const FtodTotals({
    required this.customers,
    required this.dueAmount,
    required this.collectedAmount,
    required this.counts,
  });

  final int customers;
  final double dueAmount;
  final double collectedAmount;
  final FtodStatusCounts counts;

  static const empty = FtodTotals(
    customers: 0,
    dueAmount: 0,
    collectedAmount: 0,
    counts: FtodStatusCounts(),
  );

  factory FtodTotals.fromJson(Map<String, dynamic> j) => FtodTotals(
        customers: _int(j['customers']),
        dueAmount: _num(j['dueAmount']),
        collectedAmount: _num(j['collectedAmount']),
        counts: FtodStatusCounts.fromJson(j),
      );

  int get collectedPercent => ftodPercent(collectedAmount, dueAmount);
}

/// Money received against one due date's customers on one calendar day.
class FtodCollectionDay {
  const FtodCollectionDay({
    required this.date,
    required this.customers,
    required this.amount,
  });

  final DateTime? date;
  final int customers;
  final double amount;

  factory FtodCollectionDay.fromJson(Map<String, dynamic> j) =>
      FtodCollectionDay(
        date: parseFtodDate(j['date']),
        customers: _int(j['customers']),
        amount: _num(j['amount']),
      );

  /// Days after the due date this money came in (0 = on the due date).
  int daysAfter(DateTime? dueDate) {
    if (date == null || dueDate == null) return 0;
    return ftodDaysBetween(dueDate, date!);
  }

  /// "04 Sep · 3 · ₹13,500" — the chip under each due-date card.
  String chipLabel() =>
      '${ftodDay(date)} · ${ftodCount(customers)} · ${ftodRupees(amount)}';
}

/// One due date in the month: who was due, and when their money actually came.
class FtodDueDay {
  const FtodDueDay({
    required this.dueDate,
    required this.customers,
    required this.dueAmount,
    required this.collectedAmount,
    required this.counts,
    required this.collections,
  });

  final DateTime? dueDate;
  final int customers;
  final double dueAmount;
  final double collectedAmount;
  final FtodStatusCounts counts;
  final List<FtodCollectionDay> collections;

  factory FtodDueDay.fromJson(Map<String, dynamic> j) {
    final cols = _maps(j['collections']).map(FtodCollectionDay.fromJson).toList()
      // Server sorts date asc already; re-sort so the "Collected on" chips
      // always read left-to-right in time even from an older backend.
      ..sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
    return FtodDueDay(
      dueDate: parseFtodDate(j['dueDate']),
      customers: _int(j['customers']),
      dueAmount: _num(j['dueAmount']),
      collectedAmount: _num(j['collectedAmount']),
      counts: FtodStatusCounts.fromJson(j),
      collections: cols,
    );
  }

  int get collectedPercent => ftodPercent(collectedAmount, dueAmount);

  /// Money that came in after the due date (the 1st → 4th/5th pattern).
  double get lateAmount => collections
      .where((c) => c.daysAfter(dueDate) > 0)
      .fold(0.0, (s, c) => s + c.amount);

  /// "Due 01 Sep · 12 customers · EMI ₹54,000".
  String headline() => 'Due ${ftodDay(dueDate)} · '
      '${ftodCount(customers)} ${customers == 1 ? 'customer' : 'customers'} · '
      'EMI ${ftodRupees(dueAmount)}';
}

/// GET /api/ftod/mine/distribution.
class FtodDistribution {
  const FtodDistribution({
    required this.month,
    required this.scope,
    required this.totals,
    required this.days,
  });

  /// "2026-09".
  final String month;

  /// "FO" (own customers), "BRANCH" or "ALL".
  final String scope;
  final FtodTotals totals;
  final List<FtodDueDay> days;

  factory FtodDistribution.fromJson(Map<String, dynamic> j) {
    final days = _maps(j['days']).map(FtodDueDay.fromJson).toList()
      ..sort((a, b) =>
          (a.dueDate ?? DateTime(0)).compareTo(b.dueDate ?? DateTime(0)));
    final totals = j['totals'];
    return FtodDistribution(
      month: _str(j['month']) ?? '',
      scope: (_str(j['scope']) ?? 'FO').toUpperCase(),
      totals: totals is Map
          ? FtodTotals.fromJson(Map<String, dynamic>.from(totals))
          : FtodTotals.empty,
      days: days,
    );
  }

  /// A field officer only sees their own customers, so naming the officer on
  /// every row would be noise; managers need it to know whom to chase.
  bool get showsOfficer => scope != 'FO';

  FtodDueDay? dayFor(DateTime? dueDate) {
    if (dueDate == null) return null;
    for (final d in days) {
      if (d.dueDate == dueDate) return d;
    }
    return null;
  }
}

// ── Customer list ────────────────────────────────────────────────────────────

class FtodPayment {
  const FtodPayment({required this.date, required this.amount});

  final DateTime? date;
  final double amount;

  factory FtodPayment.fromJson(Map<String, dynamic> j) => FtodPayment(
        date: parseFtodDate(j['date']),
        amount: _num(j['amount']),
      );
}

/// One customer's EMI for one due date (FtodDueResponse).
class FtodDue {
  const FtodDue({
    required this.id,
    required this.customerName,
    required this.dueDate,
    required this.dueAmount,
    required this.collectedAmount,
    required this.balance,
    required this.status,
    required this.daysLate,
    required this.collections,
    this.phone,
    this.accountId,
    this.clientId,
    this.branchName,
    this.fieldOfficerName,
    this.lastCollectionDate,
  });

  final int id;
  final String customerName;
  final String? phone;
  final String? accountId;
  final String? clientId;
  final String? branchName;
  final String? fieldOfficerName;
  final DateTime? dueDate;
  final double dueAmount;
  final double collectedAmount;
  final double balance;
  final FtodStatus status;
  final int daysLate;
  final DateTime? lastCollectionDate;
  final List<FtodPayment> collections;

  factory FtodDue.fromJson(Map<String, dynamic> j) {
    final due = _num(j['dueAmount']);
    final collected = _num(j['collectedAmount']);
    final rawBalance = j['balance'];
    final cols = _maps(j['collections']).map(FtodPayment.fromJson).toList()
      ..sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
    return FtodDue(
      id: _int(j['id']),
      customerName: _str(j['customerName']) ?? 'Customer',
      phone: _str(j['phone']),
      accountId: _str(j['accountId']),
      clientId: _str(j['clientId']),
      branchName: _str(j['branchName']),
      fieldOfficerName: _str(j['fieldOfficerName']),
      dueDate: parseFtodDate(j['dueDate']),
      dueAmount: due,
      collectedAmount: collected,
      balance: rawBalance == null
          ? (due - collected).clamp(0, double.infinity).toDouble()
          : _num(rawBalance),
      status: FtodStatus.parse(j['status']),
      daysLate: _int(j['daysLate']),
      lastCollectionDate: parseFtodDate(j['lastCollectionDate']),
      collections: cols,
    );
  }

  /// Days past the due date as of [today]. The server's daysLate for an unpaid
  /// row is frozen at its last recompute, so the screen counts from today and
  /// only falls back to the server figure when that is larger.
  int overdueDays(DateTime today) {
    if (dueDate == null) return daysLate;
    final live = ftodDaysBetween(dueDate!, today);
    return live > daysLate ? live : daysLate;
  }

  /// Badge wording: "On time", "Paid 3 days late", "Partial — ₹2,000 due",
  /// "Pending — 5 days" (or "Due today" / "Due 05 Oct" before it is overdue).
  String statusText(DateTime today) {
    switch (status) {
      case FtodStatus.paidOnTime:
        return 'On time';
      case FtodStatus.paidLate:
        return daysLate > 0 ? 'Paid ${ftodDays(daysLate)} late' : 'Paid late';
      case FtodStatus.partial:
        return 'Partial — ${ftodRupees(balance)} due';
      case FtodStatus.pending:
        final t = DateTime(today.year, today.month, today.day);
        if (dueDate != null && !dueDate!.isBefore(t)) {
          return dueDate == t ? 'Due today' : 'Due ${ftodDay(dueDate)}';
        }
        return 'Pending — ${ftodDays(overdueDays(today))}';
    }
  }

  /// "Collected ₹5,250 of ₹7,250".
  String collectedLine() =>
      'Collected ${ftodRupees(collectedAmount)} of ${ftodRupees(dueAmount)}';

  /// "01 Sep ₹2,000 · 04 Sep ₹5,250" — when the money came in.
  String paymentsLine() => collections
      .map((c) => '${ftodDay(c.date)} ${ftodRupees(c.amount)}')
      .join(' · ');

  /// Account id, else client id — what staff quote to the customer.
  String? get reference => accountId ?? clientId;
}

/// A page of GET /api/ftod/mine (PageResponse<FtodDueResponse>).
class FtodDuePage {
  const FtodDuePage({
    required this.items,
    required this.page,
    required this.totalElements,
    required this.last,
  });

  final List<FtodDue> items;
  final int page;
  final int totalElements;
  final bool last;

  factory FtodDuePage.fromJson(dynamic d) {
    if (d is List) {
      // Tolerate a bare list (no paging) — treat it as the only page.
      final items =
          _maps(d).map(FtodDue.fromJson).toList();
      return FtodDuePage(
          items: items, page: 0, totalElements: items.length, last: true);
    }
    final j = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    final items = _maps(j['content']).map(FtodDue.fromJson).toList();
    final page = _int(j['page']);
    final totalPages = _int(j['totalPages']);
    return FtodDuePage(
      items: items,
      page: page,
      totalElements: _int(j['totalElements']),
      last: j['last'] is bool ? j['last'] as bool : page + 1 >= totalPages,
    );
  }
}
