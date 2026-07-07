// Number / currency / label formatting shared across MIS screens. Ports
// src/mis/gwm/utils/format.ts so figures match the web app exactly.

import 'package:intl/intl.dart';

final NumberFormat _inIN = NumberFormat.decimalPattern('en_IN');

num _toNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? 0;
}

/// Indian-grouped integer/decimal string (e.g. 1234567 → "12,34,567").
String misNum(dynamic value) => _inIN.format(_toNum(value));

/// Indian-format rupee amounts as thousands / lakhs / crores — mirrors the web
/// `rupees()`: ₹X.XX Cr ≥1cr, ₹X.XX L ≥1L, ₹X.X K ≥1k, else en-IN grouping.
String misRupees(dynamic value) {
  final n = _toNum(value).toDouble();
  final a = n.abs();
  if (a >= 1e7) return '₹${(n / 1e7).toStringAsFixed(2)} Cr';
  if (a >= 1e5) return '₹${(n / 1e5).toStringAsFixed(2)} L';
  if (a >= 1e3) return '₹${(n / 1e3).toStringAsFixed(1)} K';
  return '₹${_inIN.format(n)}';
}

/// collection / demand → percentage achieved.
String misPct(dynamic collection, dynamic demand) {
  final d = _toNum(demand).toDouble();
  if (d == 0) return '—';
  return '${(_toNum(collection) / d * 100).toStringAsFixed(1)}%';
}

const Map<String, String> _tierLabels = {
  'all': 'CEO / Director',
  'region': 'Regional Manager',
  'division': 'Divisional Manager',
  'area': 'Area Manager',
  'branch': 'Branch Manager',
  'self': 'Field Officer',
};

String misTierLabel(String? tier) =>
    (tier != null ? _tierLabels[tier] : null) ?? tier ?? '—';

const List<String> _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2026-04-01" → "Apr-26".
String misMonthLabel(String key) {
  if (key.length < 7) return key;
  final parts = key.substring(0, 7).split('-');
  if (parts.length < 2) return key;
  final m = int.tryParse(parts[1]) ?? 0;
  if (m < 1 || m > 12) return key;
  return '${_mon[m - 1]}-${parts[0].substring(2)}';
}

/// Format a Month-Highlights cell for display. type: count | cr | pct | na.
String misCell(String type, double? v) {
  if (type == 'na' || v == null || v.isNaN) return '—';
  if (type == 'count') return misNum(v.round());
  if (type == 'pct') return '${v.toStringAsFixed(2)}%';
  return v.toStringAsFixed(2);
}

/// Fiscal year runs Apr→Mar. FY 2026 = Apr-26 … Mar-27.
int misFyStart(String key) {
  final y = int.tryParse(key.substring(0, 4)) ?? 0;
  final m = key.length >= 7 ? (int.tryParse(key.substring(5, 7)) ?? 1) : 1;
  return m >= 4 ? y : y - 1;
}

String misFyLabel(int start) => 'FY $start-${(start + 1).toString().substring(2)}';

const Map<String, String> _bucketLabels = {
  'regular': 'Regular',
  'on_date': 'On-date',
  '1_30': '1-30 DPD',
  '31_60': '31-60 DPD',
  '61_90': '61-90 DPD',
  'pnpa': 'PNPA',
  'npa': 'NPA',
  'sma0': 'SMA-0',
  'sma1': 'SMA-1',
  'total': 'Grand Total',
};

/// "1_30" → "1-30 DPD". Falls back to the raw key.
String misBucketLabel(String name) => _bucketLabels[name] ?? name;

/// "2026-06-19" → "19 Jun 2026". Empty/invalid input passes through.
String misPrettyDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final s = iso.length >= 10 ? iso.substring(0, 10) : iso;
  final p = s.split('-');
  if (p.length < 3) return iso;
  final m = int.tryParse(p[1]) ?? 0;
  final d = int.tryParse(p[2]) ?? 0;
  if (m < 1 || m > 12) return iso;
  return '${d.toString().padLeft(2, '0')} ${_mon[m - 1]} ${p[0]}';
}
