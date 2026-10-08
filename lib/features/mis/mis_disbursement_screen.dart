// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Disbursement (route /mis/disbursement). Monthly + daily disbursement
//  counts/amounts, by-product breakdown, per-day trend, and a region → division
//  → area → branch → officer drill-down with click-to-call. Ports
//  DisbursementScreen.tsx (Overview + Daily tabs).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart';
import 'mis_collection_widgets.dart';
import 'mis_format.dart';
import 'mis_matrix_table.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

const _products = [('', 'All'), ('igl', 'IGL'), ('fig', 'FIG'), ('il', 'IL')];
const _productName = {1: 'IGL', 2: 'FIG', 3: 'IL'};
const _levelLabel = {
  'region': 'Region',
  'division': 'Division',
  'area': 'Area',
  'branch': 'Branch',
  'employee': 'Officer',
};

String? _callHref(String? m) {
  final digits = (m ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length >= 10 ? 'tel:${digits.substring(digits.length - 10)}' : null;
}

Future<void> _call(String? mobile) async {
  final href = _callHref(mobile);
  if (href != null) {
    await launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
  }
}

class MisDisbursementScreen extends ConsumerStatefulWidget {
  const MisDisbursementScreen({super.key});

  @override
  ConsumerState<MisDisbursementScreen> createState() =>
      _MisDisbursementScreenState();
}

class _MisDisbursementScreenState extends ConsumerState<MisDisbursementScreen> {
  String? _month;
  String _product = '';
  bool _money = true; // amount | count
  bool _daily = false; // Overview | Daily tab
  String? _region, _division, _area, _branch;

  // Daily-tab state
  String? _date;
  String _range = 'ftd'; // ftd | mtd

  String get _level => _branch != null
      ? 'employee'
      : _area != null
          ? 'branch'
          : _division != null
              ? 'area'
              : _region != null
                  ? 'division'
                  : 'region';

  bool get _canDrill => _level != 'employee';

  void _drillUnit(String unit) {
    setState(() {
      if (_region == null) {
        _region = unit;
      } else if (_division == null) {
        _division = unit;
      } else if (_area == null) {
        _area = unit;
      } else {
        _branch ??= unit;
      }
    });
  }

  void _resetTo(String? level) {
    setState(() {
      switch (level) {
        case null:
          _region = _division = _area = _branch = null;
          break;
        case 'region':
          _division = _area = _branch = null;
          break;
        case 'division':
          _area = _branch = null;
          break;
        case 'area':
          _branch = null;
          break;
      }
    });
  }

  List<MisCrumb> _crumbs() => [
        MisCrumb('All regions', onTap: () => _resetTo(null)),
        if (_region != null) MisCrumb(_region!, onTap: () => _resetTo('region')),
        if (_division != null)
          MisCrumb(_division!, onTap: () => _resetTo('division')),
        if (_area != null) MisCrumb(_area!, onTap: () => _resetTo('area')),
        if (_branch != null) MisCrumb(_branch!),
      ];

  String get _metricLabel => _money ? 'Amount' : 'Accounts';
  String get _rangeLabel => _range == 'mtd' ? 'Month-to-date' : 'For the day';

  DisbQuery _overviewQuery(String? activeMonth) => DisbQuery(
        month: activeMonth,
        product: _product,
        region: _region,
        division: _division,
        area: _area,
        branch: _branch,
      );

  DisbDailyQuery _dailyQuery(String active) => DisbDailyQuery(
        date: active,
        range: _range,
        product: _product,
        region: _region,
        division: _division,
        area: _area,
        branch: _branch,
      );

  @override
  Widget build(BuildContext context) {
    final monthsAsync = ref.watch(misDisbMonthsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('MIS')),
      body: monthsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AppLoadingBlock(height: 240),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misDisbMonthsProvider),
          ),
        ),
        data: (months) {
          final active = _month ?? (months.isNotEmpty ? months.first : null);
          return _scaffold(months, active);
        },
      ),
    );
  }

  Widget _scaffold(List<String> months, String? activeMonth) {
    // The hero's headline figures read the SAME summary provider (same family
    // key) the tab body uses, so they cost no extra request.
    final dailyDates = _daily
        ? (ref.watch(misDisbDailyDatesProvider).valueOrNull ?? const <String>[])
        : const <String>[];
    final activeDate =
        dailyDates.isEmpty ? null : (_date ?? dailyDates.first);
    final DisbSummary? summary = _daily
        ? (activeDate == null
            ? null
            : ref.watch(misDisbDailySummaryProvider(_dailyQuery(activeDate)))
                .valueOrNull)
        : ref.watch(misDisbSummaryProvider(_overviewQuery(activeMonth)))
            .valueOrNull;

    return ProPage(
      hero: ProHero(
        titleWidget: MisDeepTitle(title: 'Disbursement', crumbs: _crumbs()),
        children: [
          // Tab + (overview only) month picker. Like the web there is no
          // cards/table toggle: the drill is always the table, because Accounts,
          // Amount and ATS only mean something read side by side.
          MisDeepSegmented<bool>(
            options: const [(false, 'Overview'), (true, 'Daily')],
            value: _daily,
            onChanged: (v) => setState(() => _daily = v),
          ),
          if (!_daily)
            MisMonthPicker(
              value: activeMonth,
              available: months,
              onChanged: (v) => setState(() => _month = v),
            )
          else if (activeDate != null)
            _dailyDateRow(dailyDates, activeDate),
          // Product + metric toggles
          Row(
            children: [
              Expanded(
                flex: 13,
                child: MisDeepSegmented<String>(
                  options: _products,
                  value: _product,
                  onChanged: (v) => setState(() => _product = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 11,
                child: MisDeepSegmented<bool>(
                  options: const [(true, 'Amount'), (false, 'Accounts')],
                  value: _money,
                  onChanged: (v) => setState(() => _money = v),
                ),
              ),
            ],
          ),
          _heroFigures(summary, _daily ? activeDate : activeMonth),
        ],
      ),
      children: [
        if (_daily) _dailyTab() else _overviewTab(activeMonth),
      ],
    );
  }

  /// Previous / next day with data, the date picker and the FTD/MTD range.
  Widget _dailyDateRow(List<String> dates, String active) {
    final idx = dates.indexOf(active);
    final older = idx < dates.length - 1;
    final newer = idx > 0;
    return Row(
      children: [
        Opacity(
          opacity: older ? 1 : 0.4,
          child: ProHeroIconButton(
            icon: Icons.chevron_left_rounded,
            iconSize: 22,
            tooltip: 'Previous day',
            onTap: older ? () => setState(() => _date = dates[idx + 1]) : null,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: MisDatePicker(
            value: active,
            available: dates,
            onChanged: (v) => setState(() => _date = v),
          ),
        ),
        const SizedBox(width: 6),
        Opacity(
          opacity: newer ? 1 : 0.4,
          child: ProHeroIconButton(
            icon: Icons.chevron_right_rounded,
            iconSize: 22,
            tooltip: 'Next day',
            onTap: newer ? () => setState(() => _date = dates[idx - 1]) : null,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 96,
          child: MisDeepSegmented<String>(
            options: const [('ftd', 'FTD'), ('mtd', 'MTD')],
            value: _range,
            onChanged: (v) => setState(() => _range = v),
          ),
        ),
      ],
    );
  }

  /// Amount (large), Accounts and ATS for the open tab. "—" while loading.
  Widget _heroFigures(DisbSummary? s, String? period) {
    final periodLabel = period == null ? null : misPrettyDate(period);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MisDeepLabel(
          _daily ? 'Amount · $_rangeLabel' : 'Amount',
          trailing: periodLabel,
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            s == null ? '—' : misRupees(s.totalAmount),
            style: const TextStyle(
              fontSize: 34,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ProHeroStats(stats: [
          ProStat(
            label: _daily ? 'Accounts · $_rangeLabel' : 'Accounts',
            value: s == null ? '—' : misNum(s.totalCount),
            sub: periodLabel,
            dot: const Color(0xFF6CBCCB),
          ),
          ProStat(
            label: _daily ? 'Avg ticket size' : 'ATS',
            value: s == null ? '—' : misRupees(s.ats),
            sub: 'Amount ÷ accounts',
            dot: AppColors.live,
          ),
        ]),
      ],
    );
  }

  // ── Overview tab ────────────────────────────────────────────────────────────

  Widget _overviewTab(String? activeMonth) {
    final q = _overviewQuery(activeMonth);
    final summaryAsync = ref.watch(misDisbSummaryProvider(q));
    final productAsync = ref.watch(misDisbByProductProvider(q));
    final trendAsync = ref.watch(misDisbDailyTrendProvider(DisbTrendQuery(
      month: activeMonth != null && activeMonth.length >= 7
          ? activeMonth.substring(0, 7)
          : null,
      product: _product,
    )));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The figures themselves sit in the hero; a failed summary still says so.
        if (summaryAsync.hasError) ...[
          AppErrorPanel(
            message: summaryAsync.error.toString(),
            onRetry: () => ref.invalidate(misDisbSummaryProvider(q)),
          ),
          const SizedBox(height: 14),
        ],
        productAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (products) => _productBreakdown(products),
        ),
        trendAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (trend) {
            final bars = [
              for (final r in trend)
                MisBar(misPrettyDate(r.disbDate).substring(0, 6),
                    _money ? r.amount : r.count),
            ];
            if (bars.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _chartCard('Daily $_metricLabel', null,
                  MisBarChart(
                      bars: bars, money: _money, color: AppColors.primary)),
            );
          },
        ),
        const SizedBox(height: 8),
        _gridHeader('By ${_levelLabel[_level]!.toLowerCase()}'),
        const SizedBox(height: 10),
        _unitGrid(ref.watch(misDisbUnitsProvider(q)),
            onRetry: () => ref.invalidate(misDisbUnitsProvider(q))),
      ],
    );
  }

  Widget _chartCard(String title, String? subtitle, Widget chart) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          chart,
        ],
      ),
    );
  }

  Widget _gridHeader(String title) => ProSectionHeader(
        title: title,
        subtitle: _canDrill ? 'Tap a row to drill down.' : null,
      );

  Widget _productBreakdown(List<DisbProductRow> products) {
    final rows = products
        .map((p) => (
              id: p.productId,
              name: _productName[p.productId] ?? 'Other',
              color: MisPalette.product(p.productId),
              count: p.count,
              amount: p.amount,
              ats: p.ats,
            ))
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    final donut = [
      for (final p in rows)
        MisSlice(p.name, _money ? p.amount : p.count, p.color),
    ];
    final total =
        rows.fold<double>(0, (s, p) => s + (_money ? p.amount : p.count));
    final maxV = rows.fold<double>(
        0, (m, p) => (_money ? p.amount : p.count) > m ? (_money ? p.amount : p.count) : m);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (donut.any((s) => s.value > 0)) ...[
            _chartCard('By product', _metricLabel,
                MisDonutChart(data: donut, money: _money)),
            const SizedBox(height: 14),
          ],
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Product breakdown'),
                const SizedBox(height: 14),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: rows[i].color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(rows[i].name,
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink)),
                      ),
                      Text('${misNum(rows[i].count)} · ',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      Text(misRupees(rows[i].amount),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ProBar(
                    value: maxV > 0
                        ? ((_money ? rows[i].amount : rows[i].count) / maxV)
                            .clamp(0.0, 1.0)
                        : 0,
                    color: rows[i].color,
                    height: 5,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${total > 0 ? ((_money ? rows[i].amount : rows[i].count) / total * 100).toStringAsFixed(1) : '0'}% of total · ATS ${misRupees(rows[i].ats)}',
                    textAlign: TextAlign.right,
                    style: AppText.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Daily tab ───────────────────────────────────────────────────────────────

  Widget _dailyTab() {
    final datesAsync = ref.watch(misDisbDailyDatesProvider);
    return datesAsync.when(
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(misDisbDailyDatesProvider),
      ),
      data: (dates) {
        if (dates.isEmpty) {
          return const ProEmpty(
            icon: Icons.event_busy_rounded,
            title: 'No daily disbursement data yet.',
          );
        }
        final active = _date ?? dates.first;
        final month = active.length >= 7 ? active.substring(0, 7) : null;
        final dq = _dailyQuery(active);
        final summaryAsync = ref.watch(misDisbDailySummaryProvider(dq));
        final trendAsync = ref.watch(misDisbDailyTrendProvider(
            DisbTrendQuery(month: month, product: _product)));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The figures sit in the hero; a failed summary still says so.
            if (summaryAsync.hasError) ...[
              AppErrorPanel(
                message: summaryAsync.error.toString(),
                onRetry: () => ref.invalidate(misDisbDailySummaryProvider(dq)),
              ),
              const SizedBox(height: 14),
            ],
            trendAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (trend) {
                final bars = [
                  for (final r in trend)
                    MisBar(misPrettyDate(r.disbDate).substring(0, 6),
                        _money ? r.amount : r.count),
                ];
                if (bars.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _chartCard('Daily disbursement', _metricLabel,
                      MisBarChart(
                          bars: bars,
                          money: _money,
                          color: AppColors.primary)),
                );
              },
            ),
            const SizedBox(height: 8),
            _gridHeader(
                'By ${_levelLabel[_level]!.toLowerCase()} · $_rangeLabel'),
            const SizedBox(height: 10),
            _unitGrid(ref.watch(misDisbDailyUnitsProvider(dq)),
                onRetry: () => ref.invalidate(misDisbDailyUnitsProvider(dq))),
          ],
        );
      },
    );
  }

  // ── Shared unit grid/table ──────────────────────────────────────────────────

  Widget _unitGrid(AsyncValue<List<DisbUnitRow>> async,
      {required VoidCallback onRetry}) {
    return async.when(
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) =>
          AppErrorPanel(message: e.toString(), onRetry: onRetry),
      data: (rows) {
        if (rows.isEmpty) {
          return const ProEmpty(
            icon: Icons.table_rows_outlined,
            title: 'No disbursement at this level.',
          );
        }
        final isEmp = _level == 'employee';

        // Unlike Collection, Accounts and Amount show TOGETHER — they are not
        // alternatives here: ATS (average ticket size) is amount ÷ accounts, so
        // comparing branches needs both in front of you for it to mean anything.
        // That is also why this screen carries no Accounts/Amount switch.
        final totCount = rows.fold<double>(0, (s, r) => s + r.count);
        final totAmount = rows.fold<double>(0, (s, r) => s + r.amount);
        // ATS is computed from the TOTALS, never averaged across rows — that
        // would weight a 3-account branch like a 300-account one.
        double ats(double amt, double cnt) => cnt > 0 ? amt / cnt : 0;
        String share(double v) => totAmount > 0
            ? '${(v / totAmount * 100).toStringAsFixed(1)}%'
            : '—';

        return MisMatrixTable(
          stubHeader: _levelLabel[_level]!,
          headers: [
            if (!isEmp) 'Manager',
            'Accounts',
            'Amount',
            'ATS',
            'Share',
          ],
          rows: [
            for (final r in rows)
              MisMatrixRow(
                lead: MisLead(
                  r.unit,
                  note: isEmp ? r.empId : null,
                  trailing: (isEmp && _callHref(r.mobile) != null)
                      ? IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _call(r.mobile),
                          icon: const Icon(Icons.phone_rounded,
                              size: 16, color: AppColors.success),
                          tooltip: 'Call ${r.unit}',
                        )
                      : null,
                ),
                onTap: _canDrill ? () => _drillUnit(r.unit) : null,
                cells: [
                  if (!isEmp)
                    MisCell(r.managerName ?? '—', muted: true),
                  MisCell(misNum(r.count)),
                  MisCell(misRupees(r.amount),
                      color: AppColors.success, weight: FontWeight.w600),
                  MisCell(misRupees(ats(r.amount, r.count))),
                  // Share is BY AMOUNT, disbursement's reporting unit. Accounts
                  // stay on the row, so a branch disbursing many small loans is
                  // visible as a low share against a high count.
                  MisCell(
                    share(r.amount),
                    weight: FontWeight.w600,
                    track: totAmount > 0
                        ? (r.amount / totAmount).clamp(0.0, 1.0)
                        : 0,
                    trackColor: AppColors.primary,
                  ),
                ],
              ),
            MisMatrixRow(
              kind: MisRowKind.total,
              lead: const MisLead('Total'),
              cells: [
                if (!isEmp) const MisCell(''),
                MisCell(misNum(totCount)),
                MisCell(misRupees(totAmount)),
                MisCell(misRupees(ats(totAmount, totCount))),
                const MisCell('100.0%'),
              ],
            ),
          ],
        );
      },
    );
  }
}
