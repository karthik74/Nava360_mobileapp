// ─────────────────────────────────────────────────────────────────────────────
//  Intra-day presentation widgets for the Hourly screen. Ports SnapshotClock,
//  Sparkline and HourlyHeatTable from the web MIS module.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'mis_charts.dart';
import 'mis_format.dart';
import 'mis_hourly_series.dart';

/// "Live snapshot" badge for the Hourly hero (drawn for the deep brand
/// surface). The hero is the snapshot's HOUR
/// SLOT (e.g. 6 PM) — the hour the data represents — on an odometer reel that
/// rolls up from 0 and lands on the current hour. The date is omitted (it's
/// already in the picker). Re-key on the hour so the roll replays whenever a
/// fresh snapshot loads. Ports SnapshotClock.tsx.
class MisSnapshotClock extends StatefulWidget {
  const MisSnapshotClock({
    super.key,
    required this.periodHour,
    this.asOf,
    this.live = true,
  });

  /// The snapshot's hour slot, 0–23.
  final int periodHour;

  /// Capture time as the API reported it, e.g. "2026-07-16 04:22:58".
  final String? asOf;

  /// False when replaying an archived hour (the ?hour= switcher): the chip
  /// reads REPLAY in amber with a static dot, and the meta line says
  /// "Snapshot replay". Ports SnapshotClock's live/replay variants.
  final bool live;

  @override
  State<MisSnapshotClock> createState() => _MisSnapshotClockState();
}

class _MisSnapshotClockState extends State<MisSnapshotClock>
    with TickerProviderStateMixin {
  static const double _cell = 34; // height of one reel cell

  late final AnimationController _roll;
  late final AnimationController _pulse;
  late final Animation<double> _offset;

  int get _hero =>
      widget.periodHour % 12 == 0 ? 12 : widget.periodHour % 12;
  String get _ampm => widget.periodHour < 12 ? 'AM' : 'PM';

  /// "2026-08-19 05:39:36" → "19 Aug 2026 · 5:39 AM" — the capture DATE and
  /// TIME spelled out, formatted the way the Collection screen prints its
  /// dates, instead of the raw database timestamp.
  String? get _asOfPretty {
    final raw = widget.asOf;
    if (raw == null || raw.isEmpty) return null;
    final date = misPrettyDate(raw);
    final t = raw.length > 10
        ? RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw.substring(10))
        : null;
    if (t == null) return date;
    final h = int.tryParse(t.group(1)!) ?? 0;
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$date · $hh:${t.group(2)} ${h < 12 ? 'AM' : 'PM'}';
  }

  @override
  void initState() {
    super.initState();
    _roll = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 420 + _hero * 55),
    );
    _offset = Tween<double>(begin: 0, end: _hero * _cell)
        .animate(CurvedAnimation(parent: _roll, curve: Curves.easeOutCubic));
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _roll.forward();
  }

  @override
  void dispose() {
    _roll.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label:
          '${widget.live ? 'Live' : 'Replayed'} hourly snapshot for $_hero $_ampm',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            _liveChip(),
            const SizedBox(width: 12),
            // The odometer reel: a strip of 0..hero scrolled up behind a
            // one-cell window, so it rolls through every number on the way.
            //
            // OverflowBox is what makes the strip legal: the window is one cell
            // tall, but the strip is (hero + 1) cells, so without lifting the
            // height constraint the Column overflows its parent instead of
            // being clipped by it.
            ClipRect(
              child: SizedBox(
                height: _cell,
                width: _hero >= 10 ? 30 : 18,
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: AnimatedBuilder(
                    animation: _offset,
                    builder: (context, _) => Transform.translate(
                      offset: Offset(0, -_offset.value),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var n = 0; n <= _hero; n++)
                            SizedBox(
                              height: _cell,
                              child: Center(
                                child: Text(
                                  '$n',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    height: 1,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _ampm,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.live ? 'Hourly snapshot' : 'Snapshot replay',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (_asOfPretty != null)
                    Text(
                      'as of $_asOfPretty',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveChip() {
    final color = widget.live ? AppColors.live : const Color(0xFFF2B347);
    final fg = widget.live ? const Color(0xFFCDEE9E) : const Color(0xFFFFD690);
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The dot pulses only when live — a replay is a still photograph.
          if (widget.live)
            FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0.25).animate(_pulse),
              child: dot,
            )
          else
            dot,
          const SizedBox(width: 5),
          Text(
            widget.live ? 'Live' : 'Replay',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny inline sparkline — an intra-day trend at a glance. A soft gradient fill
/// under a polyline, with a dot on the peak. Ports Sparkline.tsx.
class MisSparkline extends StatelessWidget {
  const MisSparkline({
    super.key,
    required this.values,
    this.color = MisPalette.seriesCollection,
    this.height = 34,
    this.strokeWidth = 1.8,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: MisPalette.resolve(color),
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const pad = 2.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    if (w <= 0 || h <= 0) return;

    var max = 1.0;
    for (final v in values) {
      if (v > max) max = v;
    }
    final n = values.length;
    double x(int i) => pad + (n == 1 ? w / 2 : (i / (n - 1)) * w);
    double y(double v) => pad + h - (v / max) * h;

    final line = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < n; i++) {
      line.lineTo(x(i), y(values[i]));
    }

    // Gradient fill under the line, fading to nothing at the baseline.
    final area = Path.from(line)
      ..lineTo(x(n - 1), size.height - pad)
      ..lineTo(x(0), size.height - pad)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    var peak = 0;
    for (var i = 1; i < n; i++) {
      if (values[i] > values[peak]) peak = i;
    }
    canvas.drawCircle(
        Offset(x(peak), y(values[peak])), 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      !_sameValues(old.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Compact KPI chip for the intra-day summary strip.
class MisHourKpi extends StatelessWidget {
  const MisHourKpi({
    super.key,
    required this.label,
    required this.value,
    this.sub,
  });

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                letterSpacing: -0.4,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (sub != null && sub!.isNotEmpty)
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

/// One row of the intra-day heat table.
class MisHeatRow {
  final String unit;
  final String? sub;
  final double demand;
  final double collected;
  final Map<int, double> byHour;
  final VoidCallback? onTap;

  const MisHeatRow({
    required this.unit,
    this.sub,
    this.demand = 0,
    this.collected = 0,
    this.byHour = const {},
    this.onTap,
  });
}

/// Intra-day heat table — units (rows) × hours (columns), each cell tinted by
/// how much was collected in that hour. Makes "when did collection happen, and
/// where" readable at a glance. The unit column is pinned; the hour columns
/// scroll horizontally. Ports HourlyHeatTable.tsx.
class MisHourlyHeatTable extends StatefulWidget {
  const MisHourlyHeatTable({
    super.key,
    required this.unitHeader,
    required this.hours,
    required this.rows,
  });

  final String unitHeader;
  final List<MisHourPoint> hours;
  final List<MisHeatRow> rows;

  @override
  State<MisHourlyHeatTable> createState() => _MisHourlyHeatTableState();
}

class _MisHourlyHeatTableState extends State<MisHourlyHeatTable> {
  static const double _unitW = 138;
  static const double _hourW = 58;
  static const double _rowH = 44;
  static const double _headH = 34;

  /// Heat tint — the brand colour, so the grid follows the deployment.
  static Color get _teal => AppColors.primary;

  /// Heat scale is global across every hour cell, so intensity is comparable
  /// across the whole grid (one busy branch-hour reads as the hottest cell).
  double get _scale {
    var max = 0.0;
    for (final r in widget.rows) {
      for (final h in widget.hours) {
        final v = r.byHour[h.hour] ?? 0;
        if (v > max) max = v;
      }
    }
    return max > 0 ? max : 1;
  }

  Color _heatBg(double t) =>
      t <= 0 ? Colors.transparent : _teal.withValues(alpha: 0.08 + 0.78 * t);

  Color _heatText(double t) => t > 0.62 ? Colors.white : AppColors.ink;

  Color _bandColor(int index) => AppColors.surface;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final hours = widget.hours;
    final scale = _scale;
    final showTotal = rows.length > 1;

    final totalDemand = rows.fold<double>(0, (s, r) => s + r.demand);
    final totalCollected = rows.fold<double>(0, (s, r) => s + r.collected);
    final totalByHour = <int, double>{
      for (final h in hours)
        h.hour: rows.fold<double>(0, (s, r) => s + (r.byHour[h.hour] ?? 0)),
    };

    // The pinned unit column and the scrolling hour grid are two parallel
    // Columns of identical row heights — one scroll view, so nothing can drift
    // out of sync (a controller shared across scroll views would throw).
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _unitW,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                children: [
                  _unitCell(
                    widget.unitHeader,
                    background: AppColors.surfaceAlt,
                    color: AppColors.muted,
                    header: true,
                  ),
                  for (var i = 0; i < rows.length; i++)
                    _unitCell(
                      rows[i].unit,
                      sub: _ratio(rows[i].collected, rows[i].demand),
                      background: _bandColor(i),
                      onTap: rows[i].onTap,
                    ),
                  if (showTotal)
                    _unitCell(
                      'Total',
                      sub: _ratio(totalCollected, totalDemand),
                      background: AppColors.surfaceAlt,
                      topBorder: true,
                      bold: true,
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
                    _hourBand(
                      background: AppColors.surfaceAlt,
                      header: true,
                      cells: [
                        for (final h in hours)
                          _plainCell(h.label,
                              color: AppColors.muted,
                              weight: FontWeight.w600,
                              size: 11),
                      ],
                    ),
                    for (var i = 0; i < rows.length; i++)
                      _hourBand(
                        background: _bandColor(i),
                        onTap: rows[i].onTap,
                        cells: [
                          for (final h in hours)
                            _heatCell(rows[i].byHour[h.hour] ?? 0, scale),
                        ],
                      ),
                    if (showTotal)
                      _hourBand(
                        background: AppColors.surfaceAlt,
                        topBorder: true,
                        cells: [
                          for (final h in hours)
                            _plainCell(
                              (totalByHour[h.hour] ?? 0) > 0
                                  ? misNum(totalByHour[h.hour])
                                  : '·',
                              weight: FontWeight.w600,
                            ),
                        ],
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

  String _ratio(double collected, double demand) =>
      '${misNum(collected)} / ${misNum(demand)} · ${misPct(collected, demand)}';

  Widget _unitCell(
    String text, {
    String? sub,
    Color color = AppColors.ink,
    required Color background,
    bool topBorder = false,
    bool bold = false,
    bool header = false,
    VoidCallback? onTap,
  }) {
    final cell = Container(
      height: header ? _headH : _rowH,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: topBorder
              ? const BorderSide(color: AppColors.hairline)
              : BorderSide.none,
          bottom: const BorderSide(color: AppColors.hairlineSoft),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: header ? 11 : 12.5,
                    fontWeight: header || bold
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: Color(0xFFB3C0C3)),
        ],
      ),
    );
    if (onTap == null) return cell;
    return InkWell(onTap: onTap, child: cell);
  }

  Widget _hourBand({
    required List<Widget> cells,
    required Color background,
    bool topBorder = false,
    bool header = false,
    VoidCallback? onTap,
  }) {
    final band = Container(
      height: header ? _headH : _rowH,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: topBorder
              ? const BorderSide(color: AppColors.hairline)
              : BorderSide.none,
          bottom: const BorderSide(color: AppColors.hairlineSoft),
        ),
      ),
      child: Row(children: cells),
    );
    if (onTap == null) return band;
    return InkWell(onTap: onTap, child: band);
  }

  Widget _plainCell(String text,
      {Color color = AppColors.ink,
      FontWeight weight = FontWeight.w500,
      double size = 12}) {
    return SizedBox(
      width: _hourW,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _heatCell(double v, double scale) {
    final t = (v / scale).clamp(0.0, 1.0);
    return Container(
      width: _hourW,
      height: _rowH - 1,
      alignment: Alignment.center,
      color: _heatBg(t),
      child: Text(
        v > 0 ? misNum(v) : '·',
        style: TextStyle(
          fontSize: 12,
          fontWeight: t > 0.62 ? FontWeight.w600 : FontWeight.w500,
          color: _heatText(t),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
