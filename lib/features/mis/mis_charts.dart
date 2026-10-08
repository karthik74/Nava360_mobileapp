// Shared MIS chart colours + compact chart widgets (fl_chart). Ports the web
// palette (src/mis/gwm/components/charts/palette.ts) so a bucket's colour on the
// donut matches its dot in the tables — restyled to the Pro palette: the brand
// colour for the headline series, a soft tint of it for the comparison series,
// hairline grid lines and small muted axis text.

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
  ///
  /// These stay `const` (call sites use them in const lists); the chart widgets
  /// map them onto the runtime brand palette through [resolve] when painting.
  static const seriesDemand = primary;
  static const seriesCollection = teal;

  static const List<Color> categorical = [
    primary, teal, warning, purple, info, pink, lime, danger,
  ];

  /// Soft tint of the brand colour — the comparison (secondary) series.
  static Color get soft => Color.lerp(AppColors.primary, Colors.white, 0.7)!;

  static Color _tint(double t) =>
      Color.lerp(AppColors.primary, Colors.white, t)!;

  /// Maps the legacy series constants onto the Pro chart palette at paint time:
  /// [seriesCollection] (the headline series) becomes the brand colour and
  /// [seriesDemand] (its comparison) a soft tint of it. Any other colour passes
  /// through unchanged.
  static Color resolve(Color c) {
    if (c == seriesCollection) return AppColors.primary;
    if (c == seriesDemand) return soft;
    return c;
  }

  /// DPD bucket / POS-status colour: healthy buckets in brand tints, then
  /// amber → orange → red as the delinquency deepens.
  static Color risk(String name) {
    switch (name) {
      case 'regular':
        return _tint(0.22);
      case 'on_date':
        return const Color(0xFF43585D);
      case '1_30':
        return _tint(0.55);
      case '31_60':
        return const Color(0xFFF2B347);
      case '61_90':
        return const Color(0xFFE8793A);
      case 'pnpa':
        return const Color(0xFFE5484D);
      case 'npa':
        return const Color(0xFFA3211B);
      case 'sma0':
        return _tint(0.55);
      case 'sma1':
        return const Color(0xFFF2B347);
      case 'total':
        return AppColors.primary;
      default:
        return AppColors.faint;
    }
  }

  /// Disbursement product colour (1 IGL · 2 FIG · 3 IL).
  static Color product(int id) {
    switch (id) {
      case 1:
        return AppColors.primary;
      case 2:
        return _tint(0.45);
      case 3:
        return const Color(0xFF43585D);
      default:
        return AppColors.faint;
    }
  }
}

/// Axis tick / category text: Geist 11, muted.
const TextStyle _axisStyle = TextStyle(
  fontSize: 11,
  color: AppColors.muted,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Hairline horizontal grid line.
FlLine _gridLine(double _) =>
    const FlLine(color: AppColors.hairlineSoft, strokeWidth: 1);

/// Printed value colour for a series: the series colour itself when it reads
/// on white, else muted (the soft comparison tint is too pale for text).
Color _labelInk(Color c) =>
    c.computeLuminance() > 0.45 ? AppColors.muted : c;

class _NoData extends StatelessWidget {
  const _NoData({this.height});
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: const Center(
          child: Text('No data', style: AppText.caption),
        ),
      );
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
    if (slices.isEmpty) return const _NoData(height: 60);
    final total = slices.fold<double>(0, (a, b) => a + b.value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 124,
          height: 124,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              startDegreeOffset: -90,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.value,
                    color: s.color,
                    radius: 18,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.inkSoft),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmt(s.value),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          total > 0
                              ? '${(s.value / total * 100).toStringAsFixed(0)}%'
                              : '—',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
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
        fontWeight: FontWeight.w600,
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

/// Small square swatch + name legend under a multi-series chart.
class _Legend extends StatelessWidget {
  const _Legend({required this.names, required this.colors});
  final List<String> names;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (var s = 0; s < names.length; s++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors[s % colors.length],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(names[s],
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted)),
            ],
          ),
      ],
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

  static const double _leftPad = 48;
  static const double _bottomPad = 30;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return _NoData(height: height);
    var maxV = 0.0;
    for (final g in groups) {
      for (final v in g.values) {
        if (v > maxV) maxV = v;
      }
    }
    // The legacy series constants map onto the brand palette here.
    final colors = [for (final c in seriesColors) MisPalette.resolve(c)];
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
                                  color: colors[s % colors.length],
                                  width: barW,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                      bottom: Radius.circular(1)),
                                ),
                            ],
                          ),
                      ],
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _leftPad,
                            getTitlesWidget: (v, _) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                axisFmt(v),
                                maxLines: 1,
                                textAlign: TextAlign.right,
                                style: _axisStyle,
                              ),
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
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  groups[i].label.length > 8
                                      ? '${groups[i].label.substring(0, 8)}…'
                                      : groups[i].label,
                                  maxLines: 1,
                                  style: _axisStyle,
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
                        getDrawingHorizontalLine: _gridLine,
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
                    fontSize: 10,
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
                            color: _labelInk(colors[s % colors.length]),
                          ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 10),
        _Legend(names: seriesNames, colors: colors),
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

  static const double _leftPad = 46;
  static const double _bottomPad = 28;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return _NoData(height: height);
    // A single series is the headline series: the default (legacy amber) and
    // the series constants all paint in the brand colour.
    final barColor =
        color == MisPalette.warning ? AppColors.primary : MisPalette.resolve(color);
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
        final barW = bars.length > 12 ? 6.0 : 12.0;
        // fl_chart's BarChartAlignment.spaceEvenly geometry (equal gaps
        // before/between/after fixed-width bars), so each printed value sits
        // exactly over its bar.
        final eachSpace = (plotW - bars.length * barW) / (bars.length + 1);
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
                            color: barColor,
                            width: barW,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                                bottom: Radius.circular(1)),
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _leftPad,
                        getTitlesWidget: (v, _) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            v.abs() >= 1000
                                ? misNum(v.round())
                                : v.toStringAsFixed(0),
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            style: _axisStyle,
                          ),
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
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(bars[i].label,
                                maxLines: 1, style: _axisStyle),
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
                    getDrawingHorizontalLine: _gridLine,
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
                fontSize: 10,
                labels: [
                  for (var i = 0; i < bars.length; i++)
                    MisPlotLabel(
                      xFrac: ((i + 1) * eachSpace + (i + 0.5) * barW) / plotW,
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
