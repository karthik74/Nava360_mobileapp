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

/// Compact single-series vertical bar chart (e.g. daily disbursement by day).
class MisBarChart extends StatelessWidget {
  const MisBarChart({
    super.key,
    required this.bars,
    this.color = MisPalette.warning,
    this.money = false,
    this.height = 190,
  });
  final List<MisBar> bars;
  final Color color;
  final bool money;
  final double height;

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
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    final step = (bars.length / 6).ceil();

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: bars[i].value,
                  color: color,
                  width: bars.length > 12 ? 6 : 12,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ]),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (v, _) => Text(
                  v.abs() >= 1000 ? misNum(v.round()) : v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: AppColors.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= bars.length) return const SizedBox.shrink();
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
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.hairline, strokeWidth: 0.6),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                money ? misRupees(rod.toY) : misNum(rod.toY),
                const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
