// ─────────────────────────────────────────────────────────────────────────────
//  The shared MIS matrix table — the Flutter counterpart of the web module's
//  `.bmx` table (MatrixTables.css), used by every drill/bucket grid so Collection,
//  Portfolio, Disbursement and the Mode-of-Collection panel all read alike.
//
//  Structure, matching the web:
//    • an optional GROUPED header (group spans on top, sub-headers beneath)
//    • a leading "stub" column: colour chip + name + note + optional chevron
//    • right-aligned numeric columns
//    • percentage cells that carry an inline track bar under the value
//    • a bold Total row pinned last
//    • category / child row variants for the nested Mode-of-Collection table
//
//  Pro styling: a white hairline card, a soft grey header row with small muted
//  labels, hairline row dividers and tabular figures.
//
//  The stub column is pinned and the measure columns scroll horizontally — both
//  halves are Columns of identical row heights, so nothing can drift out of sync.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';

/// One measure cell.
class MisCell {
  final String text;
  final Color? color;
  final Color? bgColor;
  final FontWeight? weight;

  /// 0–1 fill of the track bar drawn under the value (percentage/share cells).
  /// Null draws no track.
  final double? track;
  final Color? trackColor;

  /// Renders the value in the muted tone (an inapplicable "—").
  final bool muted;

  const MisCell(
    this.text, {
    this.color,
    this.bgColor,
    this.weight,
    this.track,
    this.trackColor,
    this.muted = false,
  });

  /// A "—" cell for a figure that does not exist in the current metric.
  const MisCell.dash({this.bgColor})
      : text = '—',
        color = null,
        weight = null,
        track = null,
        trackColor = null,
        muted = true;
}

/// The leading (stub) cell of a row.
class MisLead {
  final String name;
  final String? note;

  /// Colour chip drawn before the name (bucket / category swatch).
  final Color? chip;

  /// Indents the name — used for a channel nested under its category.
  final bool indent;

  /// Extra control after the name (e.g. a call button). Its tap must not drill.
  final Widget? trailing;

  const MisLead(
    this.name, {
    this.note,
    this.chip,
    this.indent = false,
    this.trailing,
  });
}

/// Row styling variants, mirroring the web's `.bmx-cat` / `.bmx-child` /
/// `.bmx-total` / `.bmx-npa` classes.
enum MisRowKind { normal, category, child, total, accent }

class MisMatrixRow {
  final MisLead lead;
  final List<MisCell> cells;
  final MisRowKind kind;
  final VoidCallback? onTap;
  final Color? bgColor;

  const MisMatrixRow({
    required this.lead,
    required this.cells,
    this.kind = MisRowKind.normal,
    this.onTap,
    this.bgColor,
  });
}

/// A spanning header above a run of [span] sub-columns.
class MisGroup {
  final String label;
  final int span;
  const MisGroup(this.label, this.span);
}

// ── Shared Pro table chrome ──────────────────────────────────────────────────

/// Header band fill (the Pro "surfaceAlt" header row).
const Color _headBg = Color(0xFFF6F8F8);

/// The design system never goes heavier than w600 — callers' bolder weights
/// are capped here so every grid reads alike.
FontWeight _cap(FontWeight w) =>
    (w == FontWeight.w700 || w == FontWeight.w800 || w == FontWeight.w900)
        ? FontWeight.w600
        : w;

Color _rowBgFor(MisMatrixRow r) {
  if (r.bgColor != null) return r.bgColor!;
  switch (r.kind) {
    case MisRowKind.total:
    case MisRowKind.category:
      return _headBg;
    case MisRowKind.child:
    case MisRowKind.normal:
      return AppColors.surface;
    case MisRowKind.accent:
      return AppColors.danger.withValues(alpha: 0.04);
  }
}

FontWeight _rowWeightFor(MisMatrixRow r) =>
    r.kind == MisRowKind.total || r.kind == MisRowKind.category
        ? FontWeight.w600
        : FontWeight.w500;

/// Header label colour on a band — muted on the default grey, white/ink on a
/// caller-supplied fill (kept for screens that pass their own header colour).
Color _headInk(Color? fill) => fill == null
    ? AppColors.muted
    : (fill.computeLuminance() < 0.4 ? Colors.white : AppColors.ink);

class MisMatrixTable extends StatefulWidget {
  const MisMatrixTable({
    super.key,
    required this.stubHeader,
    required this.headers,
    required this.rows,
    this.groups,
    this.stubWidth = 132,
    this.cellWidth = 86,
    this.headerColor,
    this.groupHeaderColor,
  });

  /// Header of the pinned first column — "Region", "Bucket", "Mode", …
  final String stubHeader;

  /// Sub-column headers, one per measure.
  final List<String> headers;

  /// Optional spanning header row above [headers]. Spans must sum to
  /// `headers.length`.
  final List<MisGroup>? groups;

  final List<MisMatrixRow> rows;
  final double stubWidth;
  final double cellWidth;

  /// Overrides the column-header band colour (default: the neutral Pro header
  /// row). Used by screens whose header colour is a fixed identity regardless
  /// of the app theme.
  final Color? headerColor;

  /// Overrides the spanning group-header band colour (default: neutral).
  final Color? groupHeaderColor;

  @override
  State<MisMatrixTable> createState() => _MisMatrixTableState();
}

class _MisMatrixTableState extends State<MisMatrixTable> {
  // Only the measure columns scroll (the stub stays pinned) — a persistent
  // thumb makes that scrollability visible up front, instead of a reader
  // having to discover it by swiping and landing mid-table with no cue why
  // the leftmost columns are gone.
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  static const double _rowH = 44;
  static const double _groupH = 30;
  static const double _subH = 36;

  bool get _grouped => widget.groups != null && widget.groups!.isNotEmpty;
  double get _headerH => _subH + (_grouped ? _groupH : 0);

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pinned stub column, divided from the scrolling measures by a
            // hairline.
            Container(
              width: widget.stubWidth,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                children: [
                  Container(
                    height: _headerH,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    color: widget.headerColor ?? _headBg,
                    child: Text(
                      widget.stubHeader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _headInk(widget.headerColor),
                      ),
                    ),
                  ),
                  for (var i = 0; i < widget.rows.length; i++)
                    _stubCell(widget.rows[i], i),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _hScroll,
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 4,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_grouped)
                        Row(
                          children: [
                            for (var g = 0; g < widget.groups!.length; g++)
                              _groupCell(
                                widget.groups![g].label,
                                widget.cellWidth * widget.groups![g].span,
                                first: g == 0,
                              ),
                          ],
                        ),
                      Row(
                        children: [
                          for (final h in widget.headers)
                            _headerCell(h, widget.cellWidth),
                        ],
                      ),
                      for (var i = 0; i < widget.rows.length; i++)
                        _cellsRow(widget.rows[i], i),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCell(String text, double width, {required bool first}) {
    final fill = widget.groupHeaderColor;
    return Container(
      width: width,
      height: _groupH,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fill ?? _headBg,
        border: Border(
          left: first
              ? BorderSide.none
              : const BorderSide(color: AppColors.hairline),
          bottom: const BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fill == null ? AppColors.inkSoft : _headInk(fill),
        ),
      ),
    );
  }

  Widget _headerCell(String text, double width) {
    final fill = widget.headerColor;
    return Container(
      width: width,
      height: _subH,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: fill ?? _headBg,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: _headInk(fill),
        ),
      ),
    );
  }

  BoxDecoration _rowDecoration(MisMatrixRow r, Color bg) => BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(
            color: r.kind == MisRowKind.total
                ? AppColors.hairline
                : AppColors.hairlineSoft,
          ),
        ),
      );

  Widget _stubCell(MisMatrixRow r, int i) {
    final lead = r.lead;
    final weight = r.kind == MisRowKind.child
        ? FontWeight.w400
        : (_rowWeightFor(r) == FontWeight.w600
            ? FontWeight.w600
            : FontWeight.w500);
    final cell = Container(
      height: _rowH,
      decoration: _rowDecoration(r, _rowBgFor(r)),
      padding: EdgeInsets.only(left: lead.indent ? 24 : 12, right: 6),
      child: Row(
        children: [
          if (lead.chip != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: lead.chip, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: weight,
                    color: AppColors.ink,
                  ),
                ),
                if (lead.note != null && lead.note!.isNotEmpty)
                  Text(
                    lead.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          if (lead.trailing != null) lead.trailing!,
          if (r.onTap != null)
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: Color(0xFFB3C0C3)),
        ],
      ),
    );
    if (r.onTap == null) return cell;
    return InkWell(onTap: r.onTap, child: cell);
  }

  Widget _cellsRow(MisMatrixRow r, int i) {
    final band = SizedBox(
      height: _rowH,
      child: Row(
        children: [
          for (final c in r.cells) _valueCell(c, _rowWeightFor(r), r),
        ],
      ),
    );
    if (r.onTap == null) return band;
    return InkWell(onTap: r.onTap, child: band);
  }

  Widget _valueCell(MisCell c, FontWeight rowWeight, MisMatrixRow r) {
    final color =
        c.muted ? AppColors.faint : (c.color ?? AppColors.inkSoft);
    return Container(
      width: widget.cellWidth,
      decoration: _rowDecoration(r, c.bgColor ?? _rowBgFor(r)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              c.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: _cap(c.weight ?? rowWeight),
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (c.track != null) ...[
              const SizedBox(height: 4),
              ProBar(
                value: c.track!.clamp(0.0, 1.0),
                height: 3,
                color: c.trackColor ?? c.color ?? AppColors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The colour scale the web uses for a collection percentage: ≥99 green,
/// ≥95 amber, below that red. A cell with no demand is muted.
Color misPctColor(double collection, double demand,
    {double hi = 99, double mid = 95}) {
  if (demand == 0) return AppColors.muted;
  final p = collection / demand * 100;
  return p >= hi
      ? AppColors.success
      : p >= mid
          ? AppColors.warning
          : AppColors.danger;
}

/// Two-decimal percentage text, "—" when there is nothing to divide by.
String misPct2(double collection, double demand) =>
    demand > 0 ? '${(collection / demand * 100).toStringAsFixed(2)}%' : '—';

/// A warning banner in the web's `.bmx-warn` style — used when a feed carries no
/// rupee figures, so blank Amount columns read as "not loaded", not "zero".
class MisWarnBanner extends StatelessWidget {
  const MisWarnBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ProNote(message, tone: ProNoteTone.warn),
    );
  }
}

/// The small grey explanatory line the web prints under a matrix table.
class MisFootNote extends StatelessWidget {
  const MisFootNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, left: 2, right: 2),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 12, height: 1.42, color: AppColors.muted),
        ),
      );
}

/// The web's `.cc-section-title` — a plain heading above a card or table.
class MisCcTitle extends StatelessWidget {
  const MisCcTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10, left: 2),
        child: Row(
          children: [
            Expanded(child: Text(text, style: AppText.section)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// A matrix table that NEVER scrolls — every column is laid out with
/// Expanded/flex so the whole grid always fits the available width, unlike
/// [MisMatrixTable] (built for an open-ended column count, which scrolls the
/// measure columns horizontally). Used where the caller has already made
/// enough room for every column to fit without scrolling — e.g. the Branch
/// Report card, which switches the device to landscape for exactly this
/// reason — rather than where the column count is unbounded.
class MisFlexMatrixTable extends StatelessWidget {
  const MisFlexMatrixTable({
    super.key,
    required this.stubHeader,
    required this.headers,
    required this.rows,
    this.groups,
    this.stubFlex = 3,
    this.cellFlex = 2,
    this.headerColor,
    this.groupHeaderColor,
  });

  final String stubHeader;
  final List<String> headers;
  final List<MisGroup>? groups;
  final List<MisMatrixRow> rows;
  final int stubFlex;
  final int cellFlex;
  final Color? headerColor;
  final Color? groupHeaderColor;

  bool get _grouped => groups != null && groups!.isNotEmpty;

  Widget _headerCell(String text, int flex, Color? fill,
      {bool left = false, bool center = false, bool divider = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: fill ?? _headBg,
          border: divider
              ? const Border(left: BorderSide(color: AppColors.hairline))
              : null,
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: left
              ? TextAlign.left
              : (center ? TextAlign.center : TextAlign.right),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: _headInk(fill),
          ),
        ),
      ),
    );
  }

  Widget _valueCell(MisCell c, int flex, FontWeight rowWeight, Color bg) {
    return Expanded(
      flex: flex,
      child: Container(
        color: c.bgColor ?? bg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(
          c.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: _cap(c.weight ?? rowWeight),
            color: c.muted ? AppColors.faint : (c.color ?? AppColors.inkSoft),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupFill = groupHeaderColor ?? headerColor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          children: [
            if (_grouped)
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.hairline)),
                ),
                child: Row(
                  children: [
                    _headerCell('', stubFlex, groupFill),
                    for (final g in groups!)
                      _headerCell(g.label, cellFlex * g.span, groupFill,
                          center: true, divider: true),
                  ],
                ),
              ),
            Row(
              children: [
                _headerCell(stubHeader, stubFlex, headerColor, left: true),
                for (final h in headers) _headerCell(h, cellFlex, headerColor),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: rows[i].kind == MisRowKind.total
                          ? AppColors.hairline
                          : AppColors.hairlineSoft,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: stubFlex,
                      child: Container(
                        color: _rowBgFor(rows[i]),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        child: Text(
                          rows[i].lead.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: rows[i].kind == MisRowKind.total
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    for (final c in rows[i].cells)
                      _valueCell(
                        c,
                        cellFlex,
                        rows[i].kind == MisRowKind.total
                            ? FontWeight.w600
                            : FontWeight.w500,
                        _rowBgFor(rows[i]),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
