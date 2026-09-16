// ─────────────────────────────────────────────────────────────────────────────
//  Intra-day (hourly) series extraction for the Hourly screen. Ports
//  src/mis/gwm/utils/hourly.ts.
//
//  The backend is adding per-hour collection columns to the hourly rows. Their
//  exact shape isn't fixed yet, so this parser accepts every reasonable form and
//  normalises to a sorted [MisHourPoint] series. Recognised shapes:
//
//    1. List:  row.hourly | row.hours | row.by_hour =
//         [{ hour: 9|"09:00"|"9AM", collection_count|count|value|collected: n }, …]
//    2. Map:   row.hours | row.by_hour = { "9": n, "09:00": n, "h09": n, … }
//    3. Flat:  prefixed keys on the row itself — h9 / h09 / hr9 / hour_9 / t9 /
//              "09:00" / "9am". (Bare numeric keys are NOT auto-detected on the
//              flat row, to avoid mistaking an unrelated numeric column for an
//              hour.)
//
//  If nothing matches the series is empty and the screen falls back to its
//  classic table/cards — so it keeps working before the new columns land.
// ─────────────────────────────────────────────────────────────────────────────

/// One hour of the intra-day series.
class MisHourPoint {
  final int hour; // 0–23
  final String label; // "9 AM"
  final double value;
  const MisHourPoint(this.hour, this.label, this.value);
}

/// Row keys that are never hours — excluded before any numeric/hour matching.
const Set<String> _nonHour = {
  'region', 'division', 'area', 'branch', 'name', 'emp_id', 'product', 'unit',
  'level', 'code', 'id', 'demand_count', 'collection_count', 'demand_amt',
  'collection_amt', 'balance', 'pct', 'total',
};

final RegExp _reAmPm = RegExp(r'^(\d{1,2})\s*(am|pm)$');
final RegExp _reClock = RegExp(r'^(\d{1,2}):?[0-5]\d$');
final RegExp _rePrefixed = RegExp(r'^(?:h|hr|hour|t)_?(\d{1,2})$');
final RegExp _reBare = RegExp(r'^(\d{1,2})$');

/// "9 AM" / "12 PM" for an hour 0–23.
String misHourLabel(int h) {
  final ampm = h < 12 ? 'AM' : 'PM';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh $ampm';
}

/// Parse a key/label into an hour 0–23, or null. [allowBare] permits a plain
/// number like "9"/"09" — used only for explicit hour maps/lists, not flat rows.
int? _parseHour(dynamic raw, {bool allowBare = true}) {
  if (raw is num) {
    final h = raw.floor();
    return (h >= 0 && h <= 23) ? h : null;
  }
  if (raw is! String) return null;
  final key = raw.trim().toLowerCase();
  if (key.isEmpty || _nonHour.contains(key)) return null;

  // "9am" / "9 pm"
  var m = _reAmPm.firstMatch(key);
  if (m != null) {
    var h = (int.tryParse(m.group(1)!) ?? 0) % 12;
    if (m.group(2) == 'pm') h += 12;
    return (h >= 0 && h <= 23) ? h : null;
  }
  // "09:00" / "0900"
  m = _reClock.firstMatch(key);
  if (m != null) {
    final h = int.tryParse(m.group(1)!);
    return (h != null && h >= 0 && h <= 23) ? h : null;
  }
  // "h9" / "h09" / "hr9" / "hour_9" / "t9"
  m = _rePrefixed.firstMatch(key);
  if (m != null) {
    final h = int.tryParse(m.group(1)!);
    return (h != null && h >= 0 && h <= 23) ? h : null;
  }
  // bare "9" / "09" — only where the context is an explicit hour map/list
  if (allowBare) {
    m = _reBare.firstMatch(key);
    if (m != null) {
      final h = int.tryParse(m.group(1)!);
      return (h != null && h >= 0 && h <= 23) ? h : null;
    }
  }
  return null;
}

double _num(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : 0;
  final n = double.tryParse(v?.toString() ?? '');
  return (n != null && n.isFinite) ? n : 0;
}

List<MisHourPoint> _sorted(Map<int, double> map) {
  final hours = map.keys.toList()..sort();
  return [
    for (final h in hours) MisHourPoint(h, misHourLabel(h), map[h] ?? 0),
  ];
}

/// Pull the sorted per-hour series out of a drill row (any recognised shape).
List<MisHourPoint> misHourSeries(Map<String, dynamic> row) {
  final map = <int, double>{};
  void add(int? h, double v) {
    if (h == null) return;
    map[h] = (map[h] ?? 0) + v;
  }

  final container = row['hourly'] ?? row['hours'] ?? row['by_hour'];

  if (container is List) {
    for (final it in container) {
      if (it is Map) {
        final o = it.cast<String, dynamic>();
        add(
          _parseHour(o['hour'] ?? o['h'] ?? o['time'] ?? o['label']),
          _num(o['collection_count'] ??
              o['count'] ??
              o['value'] ??
              o['collected']),
        );
      }
    }
  } else if (container is Map) {
    container.forEach((k, v) => add(_parseHour(k?.toString()), _num(v)));
  }

  // Fall back to prefixed flat keys on the row (bare numbers disallowed here).
  if (map.isEmpty) {
    row.forEach((k, v) {
      if (v is! num && v is! String) return;
      add(_parseHour(k, allowBare: false), _num(v));
    });
  }

  return _sorted(map);
}

/// Sum many rows' series into one scope-level intra-day series (union of hours).
List<MisHourPoint> misAggregateHourSeries(List<Map<String, dynamic>> rows) {
  final map = <int, double>{};
  for (final r in rows) {
    for (final p in misHourSeries(r)) {
      map[p.hour] = (map[p.hour] ?? 0) + p.value;
    }
  }
  return _sorted(map);
}

/// The hour with the highest value, for a "peak hour" KPI. Null if empty.
MisHourPoint? misPeakHour(List<MisHourPoint> series) {
  MisHourPoint? best;
  for (final p in series) {
    if (best == null || p.value > best.value) best = p;
  }
  return best;
}
