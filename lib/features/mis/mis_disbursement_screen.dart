// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Disbursement (route /mis/disbursement). Monthly + daily disbursement
//  counts/amounts, by-product breakdown, per-day trend, and a region → division
//  → area → branch → officer drill-down with click-to-call. Ports
//  DisbursementScreen.tsx (Overview + Daily tabs).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart';
import 'mis_format.dart';
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
  bool _table = false;
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

  @override
  Widget build(BuildContext context) {
    final monthsAsync = ref.watch(misDisbMonthsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Disbursement')),
      body: monthsAsync.when(
        loading: () => const AppLoadingBlock(height: 240),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
      children: [
        // Tab + (overview only) month picker + view toggle
        Row(
          children: [
            MisSegmented<bool>(
              options: const [(false, 'Overview'), (true, 'Daily')],
              value: _daily,
              onChanged: (v) => setState(() => _daily = v),
            ),
            const Spacer(),
            MisViewToggle(
                table: _table, onChanged: (t) => setState(() => _table = t)),
          ],
        ),
        const SizedBox(height: 12),
        if (!_daily)
          MisMonthPicker(
            value: activeMonth,
            available: months,
            onChanged: (v) => setState(() => _month = v),
          ),
        if (!_daily) const SizedBox(height: 12),
        // Metric + product toggles
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MisSegmented<bool>(
              options: const [(true, 'Amount'), (false, 'Accounts')],
              value: _money,
              onChanged: (v) => setState(() => _money = v),
            ),
            MisSegmented<String>(
              options: _products,
              value: _product,
              onChanged: (v) => setState(() => _product = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MisBreadcrumb(crumbs: _crumbs()),
        const SizedBox(height: 14),
        if (_daily) _dailyTab() else _overviewTab(activeMonth),
      ],
    );
  }

  // ── Overview tab ────────────────────────────────────────────────────────────

  Widget _overviewTab(String? activeMonth) {
    final q = DisbQuery(
      month: activeMonth,
      product: _product,
      region: _region,
      division: _division,
      area: _area,
      branch: _branch,
    );
    final summaryAsync = ref.watch(misDisbSummaryProvider(q));
    final productAsync = ref.watch(misDisbByProductProvider(q));
    final trendAsync = ref.watch(misDisbDailyTrendProvider(DisbTrendQuery(
      month: activeMonth != null && activeMonth.length >= 7
          ? activeMonth.substring(0, 7)
          : null,
      product: _product,
    )));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        summaryAsync.when(
          loading: () => const AppLoadingBlock(height: 120),
          error: (e, _) => AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misDisbSummaryProvider(q)),
          ),
          data: (s) => MisSnapshotGrid(cards: [
            MisSnapshotCard(
                accent: 'sky',
                icon: Icons.tag_rounded,
                label: 'Accounts',
                value: misNum(s.totalCount),
                sub: misPrettyDate(activeMonth)),
            MisSnapshotCard(
                accent: 'amber',
                icon: Icons.currency_rupee_rounded,
                label: 'Amount',
                value: misRupees(s.totalAmount),
                sub: misPrettyDate(activeMonth)),
            MisSnapshotCard(
                accent: 'indigo',
                icon: Icons.receipt_long_rounded,
                label: 'ATS',
                value: misRupees(s.ats)),
          ]),
        ),
        const SizedBox(height: 14),
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
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily $_metricLabel',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 12),
                    MisBarChart(bars: bars, money: _money),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        MisSectionTitle('By ${_levelLabel[_level]!.toLowerCase()}'),
        _unitGrid(ref.watch(misDisbUnitsProvider(q)),
            onRetry: () => ref.invalidate(misDisbUnitsProvider(q))),
      ],
    );
  }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (donut.any((s) => s.value > 0))
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('By product · $_metricLabel',
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 12),
                MisDonutChart(data: donut, money: _money),
              ],
            ),
          ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Product breakdown',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
              const SizedBox(height: 12),
              for (final p in rows) ...[
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: p.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink)),
                    ),
                    Text('${misNum(p.count)} · ',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.muted)),
                    Text(misRupees(p.amount),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: maxV > 0
                        ? ((_money ? p.amount : p.count) / maxV).clamp(0.0, 1.0)
                        : 0,
                    minHeight: 5,
                    backgroundColor: AppColors.hairline,
                    valueColor: AlwaysStoppedAnimation(p.color),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${total > 0 ? ((_money ? p.amount : p.count) / total * 100).toStringAsFixed(1) : '0'}% of total · ATS ${misRupees(p.ats)}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
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
          return const MisInlineEmpty('No daily disbursement data yet.');
        }
        final active = _date ?? dates.first;
        final idx = dates.indexOf(active);
        final month = active.length >= 7 ? active.substring(0, 7) : null;
        final dq = DisbDailyQuery(
          date: active,
          range: _range,
          product: _product,
          region: _region,
          division: _division,
          area: _area,
          branch: _branch,
        );
        final summaryAsync = ref.watch(misDisbDailySummaryProvider(dq));
        final trendAsync = ref.watch(misDisbDailyTrendProvider(
            DisbTrendQuery(month: month, product: _product)));
        final rangeLabel = _range == 'mtd' ? 'Month-to-date' : 'For the day';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: idx < dates.length - 1
                      ? () => setState(() => _date = dates[idx + 1])
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: MisDatePicker(
                    value: active,
                    available: dates,
                    onChanged: (v) => setState(() => _date = v),
                  ),
                ),
                IconButton(
                  onPressed:
                      idx > 0 ? () => setState(() => _date = dates[idx - 1]) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: MisSegmented<String>(
                options: const [('ftd', 'FTD'), ('mtd', 'MTD')],
                value: _range,
                onChanged: (v) => setState(() => _range = v),
              ),
            ),
            const SizedBox(height: 14),
            summaryAsync.when(
              loading: () => const AppLoadingBlock(height: 120),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(misDisbDailySummaryProvider(dq)),
              ),
              data: (s) => MisSnapshotGrid(cards: [
                MisSnapshotCard(
                    accent: 'sky',
                    icon: Icons.tag_rounded,
                    label: 'Accounts · $rangeLabel',
                    value: misNum(s.totalCount),
                    sub: misPrettyDate(active)),
                MisSnapshotCard(
                    accent: 'amber',
                    icon: Icons.currency_rupee_rounded,
                    label: 'Amount · $rangeLabel',
                    value: misRupees(s.totalAmount),
                    sub: misPrettyDate(active)),
                MisSnapshotCard(
                    accent: 'indigo',
                    icon: Icons.receipt_long_rounded,
                    label: 'Avg ticket size',
                    value: misRupees(s.ats)),
              ]),
            ),
            const SizedBox(height: 14),
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
                return GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Daily disbursement · $_metricLabel',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 12),
                      MisBarChart(bars: bars, money: _money),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            MisSectionTitle(
                'By ${_levelLabel[_level]!.toLowerCase()} · $rangeLabel'),
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
          return const MisInlineEmpty('No disbursement at this level.');
        }
        final isEmp = _level == 'employee';
        if (_table) {
          return MisTable<DisbUnitRow>(
            onRowTap: _canDrill ? (r) => _drillUnit(r.unit) : null,
            columns: [
              MisColumn(_levelLabel[_level]!, (r) => Text(r.unit)),
              MisColumn('Accounts', (r) => Text(misNum(r.count)), right: true),
              MisColumn('Amount', (r) => Text(misRupees(r.amount)),
                  right: true),
            ],
            rows: rows,
          );
        }
        return Column(
          children: [
            for (final r in rows) ...[
              MisMetricColumnsCard(
                accent: 'amber',
                title: r.unit,
                subtitle: isEmp ? r.empId : r.managerName,
                badge: (isEmp && _callHref(r.mobile) != null)
                    ? IconButton(
                        onPressed: () => _call(r.mobile),
                        icon: const Icon(Icons.phone_rounded,
                            size: 18, color: AppColors.success),
                        tooltip: 'Call ${r.unit}',
                      )
                    : null,
                columns: [
                  ('A/C', misNum(r.count)),
                  ('Amount', misRupees(r.amount)),
                ],
                onTap: _canDrill ? () => _drillUnit(r.unit) : null,
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
