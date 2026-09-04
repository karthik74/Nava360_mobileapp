// Shared MIS chart colours + compact chart widgets (fl_chart). Ports the web
// palette (src/mis/gwm/components/charts/palette.ts) so a bucket's colour on the
// donut matches its dot in the tables.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'mis_format.dart';

class MisPalette {
  MisPalette._();

  static const primary = Color(0xFF2563EB);
  static const teal = Color(0xFF14B8A6);
  static const info = Color(0xFF06B6D4);
  static const purple = Color(0xFF8B5CF6);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const pink = Color(0xFFEC4899);
  static const lime = Color(0xFF84CC16);

  /// demand / target / period A vs collection / achieved / period B.
  static const seriesDemand = primary;
  static const seriesCollection = teal;

  static const List<Color> categorical = [
    primary, teal, warning, purple, info, pink, lime, danger,
  ];

  /// DPD bucket / POS-status colour (regular = healthy teal, npa = red).
  static Color risk(String name) {
    switch (name) {
      case 'regular':
        return teal;
      case 'on_date':
        return info;
      case '1_30':
        return lime;
      case '31_60':
        return warning;
      case '61_90':
        return purple;
      case 'pnpa':
        return pink;
      case 'npa':
        return danger;
      case 'sma0':
        return lime;
      case 'sma1':
        return warning;
      case 'total':
        return primary;
      default:
        return const Color(0xFF94A3B8);
    }
  }

  /// Disbursement product colour (1 IGL · 2 FIG · 3 IL).
  static Color product(int id) {
    switch (id) {
      case 1:
        return const Color(0xFF6366F1);
      case 2:
        return const Color(0xFF10B981);
      case 3:
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }
}

class MisSlice {
  final String name;
  final double value;
  final Color color;
  const MisSlice(this.name, this.value, this.color);
}

/// Donut with a value/percent legend list beside it. Mirrors DonutChartCard.
class MisDonutChart extends StatelessWidget {
  const MisDonutChart({super.key, required this.data, this.money = false});
  final List<MisSlice> data;
  final bool money;

  String _fmt(double v) => money ? misRupees(v) : misNum(v);

  @override
  Widget build(BuildContext context) {
    final slices = data.where((s) => s.value > 0).toList();
    if (slices.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text('No data', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }
    final total = slices.fold<double>(0, (a, b) => a + b.value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 38,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.value,
                    color: s.color,
                    radius: 22,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSoft),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmt(s.value),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        total > 0
                            ? '${(s.value / total * 100).toStringAsFixed(0)}%'
                            : '—',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class MisBar {
  final String label;
  final double value;
  const MisBar(this.label, this.value);
}

/// One category of a grouped bar chart — a label plus one value per series.
class MisBarGroup {
  final String label;
  final List<double> values;
  const MisBarGroup(this.label, this.values);
}

// ── Always-on value labels ───────────────────────────────────────────────────
//
// Every MIS chart prints its figures on the chart itself rather than hiding them
// behind a tap. fl_chart's "permanent tooltip" draws a floating box per bar, and
// with more than a handful of bars those boxes overlap into an unreadable smear —
// so the labels are drawn here instead, over the chart, with the crowding handled
// explicitly:
//
//   1. horizontal, if every label fits inside its bar's slot;
//   2. otherwise every Nth label is dropped, so the ones that remain stay
//      legible and correctly positioned — never rotated, merged or overlapping
//      (vertical labels proved unreadable in the field).

/// One value to print, positioned in plot-relative fractions.
class MisPlotLabel {
  /// 0–1 across the plot area (0 = left edge of the plot, 1 = right edge).
  final double xFrac;

  /// 0–1 up the plot area (0 = baseline, 1 = top).
  final double yFrac;
  final String text;
  final Color color;
  const MisPlotLabel({
    required this.xFrac,
    required this.yFrac,
    required this.text,
    required this.color,
  });
}

/// Draws [labels] over a chart, choosing an orientation (and thinning) so no two
/// ever overlap. Sized to the same box as the chart it sits on; [leftPad] and
/// [bottomPad] must match the chart's reserved axis sizes so the plot rectangle
/// lines up exactly.
class MisValueLabels extends StatelessWidget {
  const MisValueLabels({
    super.key,
    required this.labels,
    required this.slotWidth,
    this.leftPad = 0,
    this.bottomPad = 0,
    this.fontSize = 9.5,
  });

  final List<MisPlotLabel> labels;

  /// Horizontal space one label may occupy before it would touch its neighbour.
  final double slotWidth;
  final double leftPad;
  final double bottomPad;
  final double fontSize;

  /// Rough advance width of a digit/character at [fontSize] for this font.
  static const double _charW = 0.58;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    var widest = 0.0;
    for (final l in labels) {
      final w = l.text.length * fontSize * _charW;
      if (w > widest) widest = w;
    }

    // Labels are ALWAYS horizontal — rotated (vertical) numbers proved
    // unreadable on the intra-day chart. When a label can't fit its bar's
    // slot, every `step`-th label is printed instead, so the ones that remain
    // stay legible — never rotated, merged or overlapping.
    final needed = widest + 2;
    final step = needed > slotWidth ? (needed / slotWidth).ceil() : 1;

    return LayoutBuilder(builder: (context, c) {
      final plotW = (c.maxWidth - leftPad).clamp(1.0, double.infinity);
      final plotH = (c.maxHeight - bottomPad).clamp(1.0, double.infinity);
      final labelH = fontSize + 2;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < labels.length; i++)
            if (i % step == 0) _one(labels[i], plotW, plotH, labelH),
        ],
      );
    });
  }

  Widget _one(
    MisPlotLabel l,
    double plotW,
    double plotH,
    double labelH,
  ) {
    final cx = leftPad + l.xFrac * plotW;
    // Sit just above the bar top; clamped so a full-height bar's label stays on
    // the canvas instead of being clipped off the top.
    final topOfBar = (1 - l.yFrac.clamp(0.0, 1.0)) * plotH;
    final top = (topOfBar - labelH - 3).clamp(0.0, plotH);

    final text = Text(
      l.text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: l.color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return Positioned(
      left: cx - 60,
      top: top,
      width: 120,
      child: Align(alignment: Alignment.bottomCenter, child: text),
    );
  }
}

/// Grouped bar chart — several series side by side per category (e.g. Demand vs
/// Collection per branch). Ports BarChartCard's multi-series form.
class MisGroupedBarChart extends StatelessWidget {
  const MisGroupedBarChart({
    super.key,
    required this.groups,
    required this.seriesNames,
    required this.seriesColors,
    this.money = false,
    this.height = 230,
    this.valueFormatter,
  });

  final List<MisBarGroup> groups;
  final List<String> seriesNames;
  final List<Color> seriesColors;
  final bool money;
  final double height;

  /// Optional override for how a value is printed (bar labels AND axis
  /// ticks). Needed when a metric's own formatting rules (already-in-Crore
  /// values, a percentage, a plain count, …) don't match the built-in
  /// money/misNum choice below — e.g. the Branch Matrix, whose metric `type`
  /// can be 'cr' (already-in-Crore — misRupees() would wrongly re-divide it
  /// by 1e7 again), 'pct' or 'count'. Omitted, both places keep this widget's
  /// exact original behaviour.
  final String Function(double)? valueFormatter;

  static const double _leftPad = 42;
  static const double _bottomPad = 30;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No data', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }
    var maxV = 0.0;
    for (final g in groups) {
      for (final v in g.values) {
        if (v > maxV) maxV = v;
      }
    }
    // Headroom above the tallest bar so its printed value has somewhere to sit.
    final top = maxV <= 0 ? 1.0 : maxV * 1.28;
    final step = (groups.length / 6).ceil();
    // Bars thin out as categories pile up so a 30-branch drill stays readable.
    final barW = groups.length > 14
        ? 4.0
        : groups.length > 8
            ? 6.0
            : 10.0;
    const barsSpace = 2.0;
    final seriesCount =
        groups.isEmpty ? 1 : groups.first.values.length.clamp(1, 99);
    // Bar value labels: the caller's formatter when given, else the original
    // money/misNum choice — unchanged for every existing call site.
    String fmt(double v) =>
        valueFormatter != null ? valueFormatter!(v) : (money ? misRupees(v) : misNum(v));
    // Axis ticks: same override when given, else the original magnitude-based
    // formatting (which never depended on `money`) — also unchanged for
    // existing callers, but now consistent with the labels above when a
    // formatter IS supplied.
    String axisFmt(double v) => valueFormatter != null
        ? valueFormatter!(v)
        : (v.abs() >= 1000 ? misNum(v.round()) : v.toStringAsFixed(0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(builder: (context, c) {
            final plotW = (c.maxWidth - _leftPad).clamp(1.0, double.infinity);
            // Each rod gets its own label, so the crowding budget is per ROD,
            // not per category.
            final slot = plotW / (groups.length * seriesCount);
            // Mirrors fl_chart's own BarChartAlignment.spaceEvenly geometry
            // (BarChartDataExtension.calculateGroupsX): fixed-width groups
            // with an equal gap before/between/after them — NOT N equal
            // slices of the plot, which only coincides with this when the
            // groups are negligibly thin next to the plot width.
            final groupWidthPx =
                seriesCount * barW + (seriesCount - 1) * barsSpace;
            final eachSpace =
                (plotW - groups.length * groupWidthPx) / (groups.length + 1);
            double groupCenterPx(int i) =>
                (i + 1) * eachSpace + (i + 0.5) * groupWidthPx;
            return Stack(
              children: [
                Positioned.fill(
                  child: BarChart(
                    BarChartData(
                      maxY: top,
                      minY: 0,
                      barGroups: [
                        for (var i = 0; i < groups.length; i++)
                          BarChartGroupData(
                            x: i,
                            barsSpace: barsSpace,
                            barRods: [
                              for (var s = 0;
                                  s < groups[i].values.length;
                                  s++)
                                BarChartRodData(
                                  toY: groups[i].values[s],
                                  color:
                                      seriesColors[s % seriesColors.length],
                                  width: barW,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3)),
                                ),
                            ],
                          ),
                      ],
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _leftPad,
                            getTitlesWidget: (v, _) => Text(
                              axisFmt(v),
                              style: const TextStyle(
                                  fontSize: 9, color: AppColors.muted),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _bottomPad,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= groups.length) {
                                return const SizedBox.shrink();
                              }
                              if (groups.length > 7 && i % step != 0) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  groups[i].label.length > 8
                                      ? '${groups[i].label.substring(0, 8)}…'
                                      : groups[i].label,
                                  style: const TextStyle(
                                      fontSize: 8.5, color: AppColors.muted),
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: top / 4,
                        getDrawingHorizontalLine: (_) => const FlLine(
                            color: AppColors.hairline, strokeWidth: 0.6),
                      ),
                      borderData: FlBorderData(show: false),
                      // Values are printed on the chart — nothing to reveal.
                      barTouchData: BarTouchData(enabled: false),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: MisValueLabels(
                    leftPad: _leftPad,
                    bottomPad: _bottomPad,
                    slotWidth: slot,
                    labels: [
                      for (var i = 0; i < groups.length; i++)
                        for (var s = 0; s < groups[i].values.length; s++)
                          MisPlotLabel(
                            // Centre of category i (matching fl_chart's own
                            // BarChartAlignment.spaceEvenly geometry exactly —
                            // NOT a naive (i+0.5)/groups.length slice, which
                            // only approximates spaceEvenly when the groups
                            // are negligibly thin next to the plot width; with
                            // few groups (e.g. a handful of branches after an
                            // Area drill) the fixed-width groups vs. the
                            // variable gaps between them diverge from that
                            // approximation enough to visibly mis-place the
                            // label over the wrong bar. See
                            // BarChartDataExtension.calculateGroupsX in the
                            // fl_chart package for the formula mirrored here),
                            // offset to rod s within it.
                            xFrac: (groupCenterPx(i) +
                                    ((s - (groups[i].values.length - 1) / 2) *
                                        (barW + barsSpace))) /
                                plotW,
                            yFrac: groups[i].values[s] / top,
                            text: fmt(groups[i].values[s]),
                            color: seriesColors[s % seriesColors.length],
                          ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          children: [
            for (var s = 0; s < seriesNames.length; s++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: seriesColors[s % seriesColors.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(seriesNames[s],
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Compact single-series vertical bar chart (e.g. daily disbursement by day).
class MisBarChart extends StatelessWidget {
  const MisBarChart({
    super.key,
    required this.bars,
    this.color = MisPalette.warning,
    this.money = false,
    this.height = 190,
    this.showValues = false,
  });
  final List<MisBar> bars;
  final Color color;
  final bool money;
  final double height;

  /// Retained for call-site compatibility. Values are ALWAYS printed now, so
  /// this no longer gates anything.
  final bool showValues;

  static const double _leftPad = 38;
  static const double _bottomPad = 26;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No data', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }
    final maxV = bars.map((b) => b.value).fold<double>(0, (a, b) => b > a ? b : a);
    // Headroom above the tallest bar so its printed value has somewhere to sit.
    final top = maxV <= 0 ? 1.0 : maxV * 1.28;
    final step = (bars.length / 6).ceil();
    String fmt(double v) => money ? misRupees(v) : misNum(v);

    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        final plotW = (c.maxWidth - _leftPad).clamp(1.0, double.infinity);
        final slot = plotW / bars.length;
        return Stack(
          children: [
            Positioned.fill(
              child: BarChart(
                BarChartData(
                  maxY: top,
                  minY: 0,
                  barGroups: [
                    for (var i = 0; i < bars.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: bars[i].value,
                            color: color,
                            width: bars.length > 12 ? 6 : 12,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _leftPad,
                        getTitlesWidget: (v, _) => Text(
                          v.abs() >= 1000
                              ? misNum(v.round())
                              : v.toStringAsFixed(0),
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.muted),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _bottomPad,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= bars.length) {
                            return const SizedBox.shrink();
                          }
                          if (bars.length > 7 && i % step != 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(bars[i].label,
                                style: const TextStyle(
                                    fontSize: 9, color: AppColors.muted)),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: top / 4,
                    getDrawingHorizontalLine: (_) => const FlLine(
                        color: AppColors.hairline, strokeWidth: 0.6),
                  ),
                  borderData: FlBorderData(show: false),
                  // Values are printed on the chart, so there is nothing left
                  // for a tooltip to reveal.
                  barTouchData: BarTouchData(enabled: false),
                ),
              ),
            ),
            Positioned.fill(
              child: MisValueLabels(
                leftPad: _leftPad,
                bottomPad: _bottomPad,
                slotWidth: slot,
                labels: [
                  for (var i = 0; i < bars.length; i++)
                    MisPlotLabel(
                      xFrac: (i + 0.5) / bars.length,
                      yFrac: bars[i].value / top,
                      text: fmt(bars[i].value),
                      color: AppColors.ink,
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
