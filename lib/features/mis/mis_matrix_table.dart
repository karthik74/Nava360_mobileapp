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
//  The stub column is pinned and the measure columns scroll horizontally — both
//  halves are Columns of identical row heights, so nothing can drift out of sync.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

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

  /// Overrides the column-header band colour (default: the app's brand
  /// primary). Used by screens whose header colour is a fixed identity
  /// regardless of the app theme (e.g. the Branch Report card's navy).
  final Color? headerColor;

  /// Overrides the spanning group-header band colour (default: primaryDark).
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
  static const double _bandH = 26;

  bool get _grouped => widget.groups != null && widget.groups!.isNotEmpty;
  double get _headerH => _bandH * (_grouped ? 2 : 1);

  Color _rowBg(MisMatrixRow r, int i) {
    if (r.bgColor != null) return r.bgColor!;
    switch (r.kind) {
      case MisRowKind.total:
        return const Color(0xFFF4B084);
      case MisRowKind.category:
        return AppColors.surfaceAlt;
      case MisRowKind.child:
        return AppColors.surface;
      case MisRowKind.accent:
        return AppColors.danger.withValues(alpha: 0.04);
      case MisRowKind.normal:
        return i.isOdd ? AppColors.surfaceAlt : AppColors.surface;
    }
  }

  FontWeight _rowWeight(MisMatrixRow r) =>
      r.kind == MisRowKind.total || r.kind == MisRowKind.category
          ? FontWeight.w800
          : FontWeight.w500;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      shadow: AppShadows.soft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.black),
              left: BorderSide(color: Colors.black),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.stubWidth,
                child: Column(
                  children: [
                    Container(
                      height: _headerH,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: widget.headerColor ?? AppColors.primary,
                        border: const Border(
                          right: BorderSide(color: Colors.black),
                          bottom: BorderSide(color: Colors.black),
                        ),
                      ),
                      child: Text(
                        widget.stubHeader,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
                              for (final g in widget.groups!)
                                _headerCell(
                                    g.label,
                                    widget.cellWidth * g.span,
                                    widget.groupHeaderColor ??
                                        AppColors.primaryDark),
                            ],
                          ),
                        Row(
                          children: [
                            for (final h in widget.headers)
                              _headerCell(
                                h,
                                widget.cellWidth,
                                widget.headerColor ??
                                    (h == 'Demand' ||
                                            h == 'Balance' ||
                                            h == 'Pending'
                                        ? const Color(0xFFFCE4D6)
                                        : h == 'Collection'
                                            ? const Color(0xFFE2EFDA)
                                            : h == 'Coll %' ||
                                                    h == 'Collection %'
                                                ? const Color(0xFFFFFFCC)
                                                : AppColors.primary),
                              ),
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
      ),
    );
  }

  Widget _headerCell(String text, double width, Color color) {
    return Container(
      width: width,
      height: _bandH,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        border: const Border(
          right: BorderSide(color: Colors.black),
          bottom: BorderSide(color: Colors.black),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color.computeLuminance() < 0.4 ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _stubCell(MisMatrixRow r, int i) {
    final lead = r.lead;
    final cell = Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: r.bgColor ?? _rowBg(r, i),
        border: const Border(
          right: BorderSide(color: Colors.black),
          bottom: BorderSide(color: Colors.black),
        ),
      ),
      padding: EdgeInsets.only(left: lead.indent ? 22 : 10, right: 6),
      child: Row(
        children: [
          if (lead.chip != null) ...[
            Container(
              width: 9,
              height: 9,
              decoration:
                  BoxDecoration(color: lead.chip, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
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
                    fontSize: 11.5,
                    fontWeight: r.kind == MisRowKind.child
                        ? FontWeight.w500
                        : (_rowWeight(r) == FontWeight.w800
                            ? FontWeight.w800
                            : FontWeight.w700),
                    color: AppColors.ink,
                  ),
                ),
                if (lead.note != null && lead.note!.isNotEmpty)
                  Text(
                    lead.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 9.5, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          if (lead.trailing != null) lead.trailing!,
          if (r.onTap != null)
            const Icon(Icons.chevron_right_rounded,
                size: 15, color: AppColors.muted),
        ],
      ),
    );
    if (r.onTap == null) return cell;
    return InkWell(onTap: r.onTap, child: cell);
  }

  Widget _cellsRow(MisMatrixRow r, int i) {
    final band = Container(
      height: _rowH,
      child: Row(
        children: [
          for (final c in r.cells) _valueCell(c, _rowWeight(r), r, i),
        ],
      ),
    );
    if (r.onTap == null) return band;
    return InkWell(onTap: r.onTap, child: band);
  }

  Widget _valueCell(MisCell c, FontWeight rowWeight, MisMatrixRow r, int i) {
    final color =
        c.muted ? AppColors.muted : (c.color ?? AppColors.inkSoft);
    return Container(
      width: widget.cellWidth,
      decoration: BoxDecoration(
        color: c.bgColor ?? r.bgColor ?? _rowBg(r, i),
        border: const Border(
          right: BorderSide(color: Colors.black),
          bottom: BorderSide(color: Colors.black),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              c.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: c.weight ?? rowWeight,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (c.track != null) ...[
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: c.track!.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: AppColors.hairline,
                  valueColor: AlwaysStoppedAnimation(
                      c.trackColor ?? c.color ?? AppColors.primary),
                ),
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
      ? const Color(0xFF059669)
      : p >= mid
          ? const Color(0xFFF59E0B)
          : const Color(0xFFE11D48);
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.35, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small grey explanatory line the web prints under a matrix table.
class MisFootNote extends StatelessWidget {
  const MisFootNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 10.5, height: 1.4, color: AppColors.muted),
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
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
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

  Color _rowBg(MisMatrixRow r, int i) {
    if (r.bgColor != null) return r.bgColor!;
    switch (r.kind) {
      case MisRowKind.total:
        return const Color(0xFFF4B084);
      case MisRowKind.category:
        return AppColors.surfaceAlt;
      case MisRowKind.child:
        return AppColors.surface;
      case MisRowKind.accent:
        return AppColors.danger.withValues(alpha: 0.04);
      case MisRowKind.normal:
        return i.isOdd ? AppColors.surfaceAlt : AppColors.surface;
    }
  }

  Widget _headerCell(String text, int flex, Color color, {bool left = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        color: color,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: left ? TextAlign.left : TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color.computeLuminance() < 0.4 ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _valueCell(MisCell c, int flex, FontWeight rowWeight, Color bg) {
    return Expanded(
      flex: flex,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(
          c.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: c.weight ?? rowWeight,
            color: c.muted ? AppColors.muted : (c.color ?? AppColors.inkSoft),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headColor = headerColor ?? AppColors.primary;
    final groupColor = groupHeaderColor ?? headerColor ?? AppColors.primaryDark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.hairline)),
        child: Column(
          children: [
            if (_grouped)
              Row(
                children: [
                  _headerCell('', stubFlex, groupColor),
                  for (final g in groups!)
                    _headerCell(g.label, cellFlex * g.span, groupColor),
                ],
              ),
            Row(
              children: [
                _headerCell(stubHeader, stubFlex, headColor, left: true),
                for (final h in headers) _headerCell(h, cellFlex, headColor),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              Row(
                children: [
                  Expanded(
                    flex: stubFlex,
                    child: Container(
                      color: _rowBg(rows[i], i),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      child: Text(
                        rows[i].lead.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: rows[i].kind == MisRowKind.total
                              ? FontWeight.w800
                              : FontWeight.w700,
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
                          ? FontWeight.w800
                          : FontWeight.w500,
                      _rowBg(rows[i], i),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
