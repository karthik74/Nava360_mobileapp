import 'package:intl/intl.dart';

/// Opening-insights payload — `GET /api/insights/opening` (optional
/// `?month=YYYY-MM`): month-to-date disbursement / FTOD / PTP plus yesterday's
/// FTOD dues. Counts only, never rupee amounts; the scope (own
/// customers / branch / area / division / region / all) is decided by the
/// server from the caller's designation, so the app never sends one.
///
/// Parsing is deliberately forgiving: a missing key reads as 0 (or null), and
/// ints that arrive as doubles ("12.0") or strings are accepted, so a partial
/// or older backend still yields a usable intro instead of an exception.

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return num.tryParse(v.trim())?.round() ?? 0;
  return 0;
}

double? _doubleOrNull(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

String _str(dynamic v) => v == null ? '' : v.toString().trim();

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// Whose numbers these are.
enum InsightsScopeLevel {
  fo,
  branch,
  area,
  division,
  region,
  all;

  static InsightsScopeLevel parse(String? v) {
    switch (v?.trim().toUpperCase()) {
      case 'BRANCH':
        return InsightsScopeLevel.branch;
      case 'AREA':
        return InsightsScopeLevel.area;
      case 'DIVISION':
        return InsightsScopeLevel.division;
      case 'REGION':
        return InsightsScopeLevel.region;
      case 'ALL':
        return InsightsScopeLevel.all;
      default:
        return InsightsScopeLevel.fo;
    }
  }
}

class InsightsScope {
  final InsightsScopeLevel level;

  /// Ready-to-show label: "Your customers", "Dharwad Branch", "… Area", …
  final String label;

  const InsightsScope({this.level = InsightsScopeLevel.fo, this.label = ''});

  factory InsightsScope.fromJson(Map<String, dynamic> j) => InsightsScope(
        level: InsightsScopeLevel.parse(j['level']?.toString()),
        label: _str(j['label']),
      );
}

class DisbursementInsight {
  /// Accounts disbursed month-to-date.
  final int accounts;

  /// False while the deployment has no disbursement feed — the card then shows
  /// "—" / "not connected" instead of a misleading 0.
  final bool connected;

  const DisbursementInsight({this.accounts = 0, this.connected = false});

  /// A missing `disbursement` object means there is no feed (not connected);
  /// a present one is connected unless it says `connected: false`.
  factory DisbursementInsight.fromJson(dynamic raw) {
    if (raw is! Map) return const DisbursementInsight();
    final j = _map(raw);
    return DisbursementInsight(
      accounts: _int(j['accounts']),
      connected: j['connected'] != false,
    );
  }
}

class FtodInsight {
  final int accounts;
  final int collected;

  /// 0–100. Falls back to collected / accounts when the server omits it.
  final double collectedPct;
  final int pending;
  final int partial;
  final int paidLate;
  final int paidOnTime;

  const FtodInsight({
    this.accounts = 0,
    this.collected = 0,
    this.collectedPct = 0,
    this.pending = 0,
    this.partial = 0,
    this.paidLate = 0,
    this.paidOnTime = 0,
  });

  factory FtodInsight.fromJson(Map<String, dynamic> j) {
    final accounts = _int(j['accounts']);
    final collected = _int(j['collected']);
    final pct = _doubleOrNull(j['collectedPct']) ??
        (accounts > 0 ? collected * 100 / accounts : 0);
    return FtodInsight(
      accounts: accounts,
      collected: collected,
      collectedPct: pct.isNaN ? 0 : pct.clamp(0, 100).toDouble(),
      pending: _int(j['pending']),
      partial: _int(j['partial']),
      paidLate: _int(j['paidLate']),
      paidOnTime: _int(j['paidOnTime']),
    );
  }
}

class PtpInsight {
  final int total;
  final int open;
  final int kept;
  final int broken;
  final int cancelled;

  const PtpInsight({
    this.total = 0,
    this.open = 0,
    this.kept = 0,
    this.broken = 0,
    this.cancelled = 0,
  });

  factory PtpInsight.fromJson(Map<String, dynamic> j) => PtpInsight(
        total: _int(j['total']),
        open: _int(j['open']),
        kept: _int(j['kept']),
        broken: _int(j['broken']),
        cancelled: _int(j['cancelled']),
      );

  /// Denominator for the Open / Kept / Broken bar (cancelled is not drawn).
  int get barTotal => open + kept + broken;
}

/// FTOD accounts whose due date was yesterday (the intro's "FTD" column).
class YesterdayInsight {
  /// The day these dues fell on (server's yesterday); null when absent or
  /// unparsable — the intro then labels the column with the device's yesterday.
  final DateTime? date;
  final int due;

  /// Fully paid so far.
  final int collected;

  /// Still pending, including part-paid.
  final int pending;

  const YesterdayInsight({
    this.date,
    this.due = 0,
    this.collected = 0,
    this.pending = 0,
  });

  factory YesterdayInsight.fromJson(Map<String, dynamic> j) => YesterdayInsight(
        date: _date(j['date']),
        due: _int(j['due']),
        collected: _int(j['collected']),
        pending: _int(j['pending']),
      );
}

/// "2026-09-29" (optionally followed by a time) → local DateTime(2026, 9, 29).
/// Only the calendar date is read, so a UTC suffix can't shift the day.
DateTime? _date(dynamic v) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(_str(v));
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

class OpeningInsights {
  /// "2026-09".
  final String month;

  /// "2026-09-29" (server's today); blank when absent.
  final String asOf;
  final InsightsScope scope;
  final String greetingName;
  final DisbursementInsight disbursement;
  final FtodInsight ftod;
  final PtpInsight ptp;

  /// Null when the backend predates the `yesterday` object.
  final YesterdayInsight? yesterday;

  const OpeningInsights({
    this.month = '',
    this.asOf = '',
    this.scope = const InsightsScope(),
    this.greetingName = '',
    this.disbursement = const DisbursementInsight(),
    this.ftod = const FtodInsight(),
    this.ptp = const PtpInsight(),
    this.yesterday,
  });

  factory OpeningInsights.fromJson(dynamic raw) {
    final j = _map(raw);
    return OpeningInsights(
      month: _str(j['month']),
      asOf: _str(j['asOf']),
      scope: InsightsScope.fromJson(_map(j['scope'])),
      greetingName: _str(j['greetingName']),
      disbursement: DisbursementInsight.fromJson(j['disbursement']),
      ftod: FtodInsight.fromJson(_map(j['ftod'])),
      ptp: PtpInsight.fromJson(_map(j['ptp'])),
      yesterday: j['yesterday'] is Map
          ? YesterdayInsight.fromJson(_map(j['yesterday']))
          : null,
    );
  }
}

// ── Formatting ───────────────────────────────────────────────────────────────

final NumberFormat _inCount =
    NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);

/// Account counts with Indian digit grouping: 1234567 → "12,34,567".
String insightsCount(num? n) => _inCount.format((n ?? 0).round());

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "29 Sep". Built by hand (no DateFormat) so it needs no locale data.
String insightsShortDate(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';
