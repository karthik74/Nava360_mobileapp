// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Comparison — the full month-vs-month TABLES (the card views show one
//  paired day at a time; these show the whole month at once). Ports
//  renderCollectionTable / renderDisbursementTable from ComparisonScreen.tsx,
//  including the collection table's sortable Day / prev-date / cur-date columns.
//
//  Both tables are wide, so they use the same shape as the other MIS grids: a
//  pinned first column beside a horizontally-scrolling body, built as two
//  Columns of identical row heights.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Which column the collection table is ordered by.
enum MisCompareSort { day, prevDate, curDate }

/// Previous month — a quiet slate; the current month carries the brand colour.
const Color _prevTint = Color(0xFF43585D);
Color get _curTint => AppColors.primary;

/// FTOD (the collection gap) — amber ink.
const Color _ftodTint = Color(0xFF9A5B00);

/// Header band fill + the underline that marks each month's column group.
const Color _headBg = Color(0xFFF6F8F8);
const Color _prevRule = Color(0xFFB9C7CA);

/// One paired row of the collection table: a weekday-occurrence label plus each
/// month's date and cumulative regular demand / collection.
class MisCompareCollRow {
  final String label; // "1 - Mon"
  final int occurrence;
  final int dayIndex; // Mon=0 … Sun=6, for the Day sort
  final String prevDateLabel; // "3rd Jun" or "-"
  final String curDateLabel;
  final int prevDateNum; // 99 when the day doesn't exist that month
  final int curDateNum;

  /// Null when that month has nothing to show for this label.
  final ({double demand, double collection})? prev;
  final ({double demand, double collection})? cur;

  /// The current month hasn't reached this day yet — the previous month's
  /// figures are shown dimmed rather than as a real comparison.
  final bool future;

  const MisCompareCollRow({
    required this.label,
    required this.occurrence,
    required this.dayIndex,
    required this.prevDateLabel,
    required this.curDateLabel,
    required this.prevDateNum,
    required this.curDateNum,
    required this.prev,
    required this.cur,
    required this.future,
  });
}

/// One day-of-month row of the disbursement table.
class MisCompareDisbRow {
  final int day;
  final String prevDateLabel;
  final String curDateLabel;
  final double? prevAccounts, curAccounts;

  /// Cumulative amounts, null past the last day that month has data for.
  final double? prevAmount, curAmount;
  final bool beyondCurrent;

  const MisCompareDisbRow({
    required this.day,
    required this.prevDateLabel,
    required this.curDateLabel,
    this.prevAccounts,
    this.curAccounts,
    this.prevAmount,
    this.curAmount,
    this.beyondCurrent = false,
  });
}

// ── Shared grid chrome ───────────────────────────────────────────────────────

const double _rowH = 44;
const double _bandH = 34;

/// A month's spanning header: grey band, the month name in its colour and a
/// 2px underline in that colour ([rule]). Without [rule] it is a plain grey
/// sub-header cell with a small muted label.
Widget _bandCell(
  String text,
  double width, {
  Color? ink,
  Color? rule,
  double? height,
  bool divider = false,
}) {
  return Container(
    width: width,
    height: height ?? _bandH,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: _headBg,
      border: Border(
        left: divider
            ? const BorderSide(color: AppColors.hairlineSoft)
            : BorderSide.none,
        bottom: rule == null
            ? BorderSide.none
            : BorderSide(color: rule, width: 2),
      ),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: rule == null ? 11.5 : 12,
        fontWeight: FontWeight.w600,
        color: ink ?? AppColors.muted,
      ),
    ),
  );
}

/// Hairline divider between rows.
const BoxDecoration _rowLine = BoxDecoration(
  color: AppColors.surface,
  border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
);

Widget _valueCell(
  String text,
  double width, {
  Color color = AppColors.ink,
  FontWeight weight = FontWeight.w400,
  bool dim = false,
  Alignment align = Alignment.centerRight,
  bool divider = false,
}) {
  return Container(
    width: width,
    alignment: align,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: divider
        ? const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.hairlineSoft)))
        : null,
    child: Opacity(
      opacity: dim ? 0.4 : 1,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: weight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

/// The colour of a "-" (nothing to show) cell.
const Color _none = AppColors.faint;

Color _collPctColor(double demand, double collection) {
  if (demand == 0) return AppColors.muted;
  final p = collection / demand * 100;
  return p >= 95
      ? AppColors.success
      : p >= 80
          ? AppColors.warning
          : AppColors.danger;
}

String _pct(double demand, double collection) =>
    demand > 0 ? '${(collection / demand * 100).toStringAsFixed(1)}%' : '-';

// ── Collection table ─────────────────────────────────────────────────────────

/// Day | previous month (Date, RD, RC, FTOD, Coll%) | current month (same).
/// Tap the Day / Date headers to re-sort; tapping the active one flips it.
class MisCompareCollectionTable extends StatefulWidget {
  const MisCompareCollectionTable({
    super.key,
    required this.rows,
    required this.prevMonth,
    required this.curMonth,
    required this.numberFormat,
  });

  final List<MisCompareCollRow> rows;
  final String prevMonth;
  final String curMonth;
  final String Function(num) numberFormat;

  @override
  State<MisCompareCollectionTable> createState() =>
      _MisCompareCollectionTableState();
}

class _MisCompareCollectionTableState extends State<MisCompareCollectionTable> {
  MisCompareSort _sort = MisCompareSort.curDate;
  bool _asc = true;

  static const double _dayW = 88;
  static const double _dateW = 82;
  static const double _numW = 78;

  List<MisCompareCollRow> get _sorted {
    final rows = [...widget.rows];
    int key(MisCompareCollRow r) => switch (_sort) {
          MisCompareSort.day => r.occurrence * 10 + r.dayIndex,
          MisCompareSort.prevDate => r.prevDateNum,
          MisCompareSort.curDate => r.curDateNum,
        };
    rows.sort((a, b) => _asc ? key(a) - key(b) : key(b) - key(a));
    return rows;
  }

  void _toggle(MisCompareSort col) {
    setState(() {
      if (_sort == col) {
        _asc = !_asc;
      } else {
        _sort = col;
        _asc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    const headerH = _bandH * 2;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pinned Day column, divided from the scrolling months.
            Container(
              width: _dayW,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                children: [
                  _sortHeader('Day', MisCompareSort.day, _dayW, headerH),
                  for (var i = 0; i < rows.length; i++)
                    Container(
                      height: _rowH,
                      decoration: _rowLine,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        rows[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _bandCell(widget.prevMonth, _dateW + _numW * 4,
                            ink: AppColors.inkSoft, rule: _prevRule),
                        _bandCell(widget.curMonth, _dateW + _numW * 4,
                            ink: _curTint, rule: _curTint, divider: true),
                      ],
                    ),
                    Row(
                      children: [
                        _sortHeader('Date', MisCompareSort.prevDate, _dateW,
                            _bandH),
                        for (final h in const ['RD', 'RC', 'FTOD', 'Coll%'])
                          _bandCell(h, _numW),
                        _sortHeader(
                            'Date', MisCompareSort.curDate, _dateW, _bandH,
                            divider: true),
                        for (final h in const ['RD', 'RC', 'FTOD', 'Coll%'])
                          _bandCell(h, _numW),
                      ],
                    ),
                    for (var i = 0; i < rows.length; i++)
                      Container(
                        height: _rowH,
                        decoration: _rowLine,
                        child: Row(
                          children: [
                            _valueCell(rows[i].prevDateLabel, _dateW,
                                color: _prevTint,
                                weight: FontWeight.w600,
                                dim: rows[i].future,
                                align: Alignment.center),
                            ..._sideCells(rows[i].prev, dim: rows[i].future),
                            _valueCell(rows[i].curDateLabel, _dateW,
                                color: _curTint,
                                weight: FontWeight.w600,
                                align: Alignment.center,
                                divider: true),
                            ..._sideCells(rows[i].cur),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Regular demand, regular collection, FTOD (the gap) and collection %.
  List<Widget> _sideCells(({double demand, double collection})? d,
      {bool dim = false}) {
    if (d == null) {
      return [
        for (var i = 0; i < 4; i++) _valueCell('-', _numW, color: _none),
      ];
    }
    final ftod = d.demand - d.collection;
    return [
      _valueCell(widget.numberFormat(d.demand), _numW,
          color: AppColors.inkSoft, dim: dim),
      _valueCell(widget.numberFormat(d.collection), _numW,
          color: AppColors.ink, weight: FontWeight.w500, dim: dim),
      _valueCell(widget.numberFormat(ftod), _numW,
          color: _ftodTint, weight: FontWeight.w600, dim: dim),
      _valueCell(_pct(d.demand, d.collection), _numW,
          color: _collPctColor(d.demand, d.collection),
          weight: FontWeight.w600,
          dim: dim),
    ];
  }

  Widget _sortHeader(
    String label,
    MisCompareSort col,
    double width,
    double height, {
    bool divider = false,
  }) {
    final active = _sort == col;
    final ink = active ? AppColors.ink : AppColors.muted;
    return Material(
      color: _headBg,
      child: InkWell(
        onTap: () => _toggle(col),
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: divider
              ? const BoxDecoration(
                  border:
                      Border(left: BorderSide(color: AppColors.hairlineSoft)))
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                active
                    ? (_asc
                        ? Icons.arrow_drop_up_rounded
                        : Icons.arrow_drop_down_rounded)
                    : Icons.unfold_more_rounded,
                size: active ? 18 : 13,
                color: active ? AppColors.ink : AppColors.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Disbursement table ───────────────────────────────────────────────────────

/// Previous month (Date, Accounts, Amount) | current month (same) | Diff %.
/// Amounts are cumulative through the month, so the last row is the month total.
class MisCompareDisbursementTable extends StatelessWidget {
  const MisCompareDisbursementTable({
    super.key,
    required this.rows,
    required this.prevMonth,
    required this.curMonth,
    required this.totalPrevAccounts,
    required this.totalCurAccounts,
    required this.totalPrevAmount,
    required this.totalCurAmount,
    required this.numberFormat,
    required this.croreFormat,
  });

  final List<MisCompareDisbRow> rows;
  final String prevMonth;
  final String curMonth;
  final double totalPrevAccounts, totalCurAccounts;
  final double totalPrevAmount, totalCurAmount;
  final String Function(num) numberFormat;
  final String Function(num) croreFormat;

  static const double _dateW = 84;
  static const double _numW = 84;
  static const double _diffW = 76;

  @override
  Widget build(BuildContext context) {
    const headerH = _bandH * 2;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _bandCell(prevMonth, _dateW + _numW * 2,
                      ink: AppColors.inkSoft, rule: _prevRule),
                  _bandCell(curMonth, _dateW + _numW * 2,
                      ink: _curTint, rule: _curTint, divider: true),
                  _bandCell('Diff %', _diffW, height: headerH, divider: true),
                ],
              ),
              Row(
                children: [
                  for (final h in const ['Date', 'Accounts', 'Amount'])
                    _bandCell(h, h == 'Date' ? _dateW : _numW),
                  for (final h in const ['Date', 'Accounts', 'Amount'])
                    _bandCell(h, h == 'Date' ? _dateW : _numW,
                        divider: h == 'Date'),
                  const SizedBox(width: _diffW),
                ],
              ),
              for (var i = 0; i < rows.length; i++) _row(rows[i]),
              if (rows.isNotEmpty) _totalRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(MisCompareDisbRow r) {
    return Container(
      height: _rowH,
      decoration: _rowLine,
      child: Row(
        children: [
          _valueCell(r.prevDateLabel, _dateW,
              color: _prevTint,
              weight: FontWeight.w600,
              dim: r.prevAccounts == null,
              align: Alignment.center),
          _valueCell(
            r.prevAccounts == null ? '-' : numberFormat(r.prevAccounts!),
            _numW,
            color: r.prevAccounts == null ? _none : AppColors.inkSoft,
          ),
          _valueCell(
            r.prevAmount == null ? '-' : croreFormat(r.prevAmount!),
            _numW,
            color: r.prevAmount == null ? _none : _prevTint,
            weight: FontWeight.w600,
          ),
          _valueCell(r.curDateLabel, _dateW,
              color: _curTint,
              weight: FontWeight.w600,
              dim: r.curAccounts == null,
              align: Alignment.center,
              divider: true),
          _valueCell(
            r.curAccounts == null ? '-' : numberFormat(r.curAccounts!),
            _numW,
            color: r.curAccounts == null ? _none : AppColors.inkSoft,
          ),
          _valueCell(
            r.curAmount == null ? '-' : croreFormat(r.curAmount!),
            _numW,
            color: r.curAmount == null ? _none : _curTint,
            weight: FontWeight.w600,
          ),
          // Past the current month's last loaded day there is nothing to
          // compare against, so the cell is blanked rather than showing -100%.
          r.beyondCurrent
              ? _valueCell('—', _diffW, color: _none, divider: true)
              : _diffCell(r.prevAmount, r.curAmount),
        ],
      ),
    );
  }

  Widget _totalRow() {
    return Container(
      height: _rowH,
      decoration: const BoxDecoration(
        color: _headBg,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          _valueCell('Total', _dateW,
              weight: FontWeight.w600, align: Alignment.center),
          _valueCell(numberFormat(totalPrevAccounts), _numW,
              weight: FontWeight.w600),
          _valueCell(croreFormat(totalPrevAmount), _numW,
              color: _prevTint, weight: FontWeight.w600),
          _valueCell('Total', _dateW,
              weight: FontWeight.w600,
              align: Alignment.center,
              divider: true),
          _valueCell(numberFormat(totalCurAccounts), _numW,
              weight: FontWeight.w600),
          _valueCell(croreFormat(totalCurAmount), _numW,
              color: _curTint, weight: FontWeight.w600),
          _diffCell(
            totalPrevAmount == 0 ? null : totalPrevAmount,
            totalCurAmount == 0 ? null : totalCurAmount,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _diffCell(double? prev, double? cur, {bool bold = false}) {
    if (prev == null || cur == null || prev == 0) {
      return _valueCell('-', _diffW, color: _none, divider: true);
    }
    final diff = (cur - prev) / prev * 100;
    final up = diff >= 0;
    return _valueCell(
      '${up ? '+' : ''}${diff.toStringAsFixed(1)}%',
      _diffW,
      color: up ? AppColors.success : AppColors.danger,
      weight: bold ? FontWeight.w600 : FontWeight.w500,
      divider: true,
    );
  }
}
