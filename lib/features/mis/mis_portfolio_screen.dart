// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Portfolio (route /mis/portfolio). POS by status/bucket for a month with
//  a region → division → area → branch drill-down. Ports PortfolioScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

const _products = [('', 'All'), ('igl', 'IGL'), ('fig', 'FIG'), ('il', 'IL')];
const _status = [
  ('regular', 'Regular'),
  ('sma0', 'SMA-0'),
  ('sma1', 'SMA-1'),
  ('pnpa', 'SMA-2'),
  ('npa', 'NPA'),
  ('total', 'Grand Total'),
];
const _levelLabel = {
  'region': 'Region',
  'division': 'Division',
  'area': 'Area',
  'branch': 'Branch',
  'officer': 'Officer',
};

class MisPortfolioScreen extends ConsumerStatefulWidget {
  const MisPortfolioScreen({super.key});

  @override
  ConsumerState<MisPortfolioScreen> createState() =>
      _MisPortfolioScreenState();
}

class _MisPortfolioScreenState extends ConsumerState<MisPortfolioScreen> {
  String? _month;
  String _product = '';
  bool _table = false;
  String? _region, _division, _area, _branch;
  // An opened field officer (leaf). `_empRow` carries that FO's bucket-wise
  // portfolio, since `/portfolio/summary` cannot scope to an individual officer.
  String? _emp, _empName;
  PortfolioUnitRow? _empRow;

  void _drill(PortfolioUnitRow r) {
    setState(() {
      if (_region == null) {
        _region = r.unit;
      } else if (_division == null) {
        _division = r.unit;
      } else if (_area == null) {
        _area = r.unit;
      } else if (_branch == null) {
        _branch = r.unit;
      } else {
        // Officer level — open the FO's own bucket-wise detail.
        _emp = r.empId ?? r.unit;
        _empName = r.unit;
        _empRow = r;
      }
    });
  }

  void _resetTo(String? level) {
    setState(() {
      _emp = _empName = null;
      _empRow = null;
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
        case 'branch':
          break; // keep the branch; only the opened officer is cleared
      }
    });
  }

  List<MisCrumb> _crumbs() => [
        MisCrumb('All regions', onTap: () => _resetTo(null)),
        if (_region != null) MisCrumb(_region!, onTap: () => _resetTo('region')),
        if (_division != null)
          MisCrumb(_division!, onTap: () => _resetTo('division')),
        if (_area != null) MisCrumb(_area!, onTap: () => _resetTo('area')),
        if (_branch != null)
          MisCrumb(_branch!,
              onTap: _emp != null ? () => _resetTo('branch') : null),
        if (_emp != null) MisCrumb(_empName ?? _emp!),
      ];

  @override
  Widget build(BuildContext context) {
    final monthsAsync = ref.watch(misPortfolioMonthsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Portfolio')),
      body: monthsAsync.when(
        loading: () => const AppLoadingBlock(height: 240),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misPortfolioMonthsProvider),
          ),
        ),
        data: (months) {
          final active = _month ?? (months.isNotEmpty ? months.first : null);
          return _body(months, active);
        },
      ),
    );
  }

  Widget _body(List<String> months, String? activeMonth) {
    final q = PortfolioQuery(
      month: activeMonth,
      product: _product,
      region: _region,
      division: _division,
      area: _area,
      branch: _branch,
    );
    final summaryAsync = ref.watch(misPortfolioSummaryProvider(q));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(misPortfolioSummaryProvider(q));
        ref.invalidate(misPortfolioUnitsProvider(q));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
        children: [
          Row(
            children: [
              Expanded(
                child: MisMonthPicker(
                  value: activeMonth,
                  available: months,
                  onChanged: (v) => setState(() => _month = v),
                ),
              ),
              const SizedBox(width: 10),
              MisViewToggle(
                  table: _table, onChanged: (t) => setState(() => _table = t)),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: MisSegmented<String>(
              options: _products,
              value: _product,
              onChanged: (v) => setState(() => _product = v),
            ),
          ),
          const SizedBox(height: 12),
          MisBreadcrumb(crumbs: _crumbs()),
          const SizedBox(height: 14),
          if (_empRow != null)
            // An opened field officer is a leaf: show that FO's bucket-wise
            // portfolio (built from the drill row) and no further drill grid.
            _summary(_empRow!.toSummary())
          else ...[
            summaryAsync.when(
              loading: () => const AppLoadingBlock(height: 200),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(misPortfolioSummaryProvider(q)),
              ),
              data: (s) => _summary(s),
            ),
            const SizedBox(height: 18),
            MisSectionTitle('By ${_levelLabel[q.level]!.toLowerCase()}'),
            _grid(q),
          ],
        ],
      ),
    );
  }

  Widget _summary(PortfolioSummary s) {
    double amt(String k) => s.amt(k);
    final total = amt('total');
    // ignore: unused_local_variable  (used by the hidden Total Account card)
    final totalAcc = amt('total_acc');
    double bucketAcc(String k) => amt('${k}_acc');
    final bucketAccTotal =
        ['regular', 'sma0', 'sma1', 'pnpa', 'npa'].fold<double>(
            0, (sum, k) => sum + bucketAcc(k));
    // Used only by the (currently hidden) Active Accounts card:
    // final activeAcc = ['regular', 'sma0', 'sma1', 'pnpa']
    //     .fold<double>(0, (sum, k) => sum + bucketAcc(k));
    // final npaAcc = bucketAcc('npa');
    final hasAcc = bucketAccTotal > 0;

    String pctContrib(double v) =>
        total > 0 ? '${(v / total * 100).toStringAsFixed(2)}%' : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Snapshot cards — all hidden for now (commented per request).
        // Uncomment the whole grid to restore.
        // MisSnapshotGrid(cards: [
        //   MisSnapshotCard(
        //       accent: 'emerald',
        //       icon: Icons.tag_rounded,
        //       label: 'Total Account',
        //       value: misNum(totalAcc)),
        //   // Active Accounts card:
        //   // MisSnapshotCard(
        //   //     accent: 'sky',
        //   //     icon: Icons.show_chart_rounded,
        //   //     label: 'Active Accounts',
        //   //     value: hasAcc ? misNum(activeAcc) : '—',
        //   //     sub: hasAcc ? 'NPA ${misNum(npaAcc)}' : 'no PAR data'),
        //   MisSnapshotCard(
        //       accent: 'indigo',
        //       icon: Icons.account_balance_wallet_rounded,
        //       label: 'POS (Amount)',
        //       value: misRupees(total)),
        // ]),
        const SizedBox(height: 18),
        const MisSectionTitle('Bucket-wise Portfolio'),
        MisTable<(String, String)>(
          columns: [
            MisColumn('Bucket', (r) {
              final k = r.$1;
              return Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: MisPalette.risk(k), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(r.$2,
                      style: TextStyle(
                          fontWeight: k == 'total'
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: AppColors.ink)),
                ],
              );
            }),
            MisColumn('Accounts', (r) {
              final acc = r.$1 == 'total' ? bucketAccTotal : bucketAcc(r.$1);
              return Text(hasAcc ? misNum(acc) : '—');
            }, right: true),
            MisColumn(
                'POS', (r) => Text(misRupees(amt(r.$1))),
                right: true),
            MisColumn('% Contrib', (r) {
              final pct = r.$1 == 'total' ? '100%' : pctContrib(amt(r.$1));
              return Text(pct,
                  style: TextStyle(
                      color: MisPalette.risk(r.$1),
                      fontWeight: FontWeight.w700));
            }, right: true),
          ],
          rows: _status,
        ),
      ],
    );
  }

  Widget _grid(PortfolioQuery q) {
    final unitsAsync = ref.watch(misPortfolioUnitsProvider(q));
    // region → division → area → branch → officer. Every level is tappable:
    // tapping an officer opens that FO's bucket-wise detail (see _drill).
    final isEmp = q.level == 'officer';
    return unitsAsync.when(
      loading: () => const AppLoadingBlock(height: 160),
      error: (e, _) => AppErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(misPortfolioUnitsProvider(q)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const MisInlineEmpty('No portfolio at this level.');
        }
        if (_table) {
          return MisTable<PortfolioUnitRow>(
            onRowTap: _drill,
            columns: [
              MisColumn(_levelLabel[q.level]!, (r) => Text(r.unit)),
              MisColumn(
                  'Active',
                  (r) => Text(r.totalAcc > 0 ? misNum(r.activeAcc) : '—'),
                  right: true),
              MisColumn('POS', (r) => Text(misRupees(r.total)), right: true),
              MisColumn('NPA', (r) => Text(misRupees(r.npa)), right: true),
            ],
            rows: rows,
          );
        }
        return Column(
          children: [
            for (final r in rows) ...[
              MisMetricColumnsCard(
                title: r.unit,
                subtitle: isEmp ? r.empId : null,
                badge: StatusPill(
                  label: 'NPA ${r.npaPct.toStringAsFixed(1)}%',
                  color: r.npaPct > 20 ? AppColors.danger : AppColors.muted,
                ),
                columns: [
                  if (r.totalAcc > 0) ('Active Acc', misNum(r.activeAcc)),
                  ('POS', misRupees(r.total)),
                  ('NPA', misRupees(r.npa)),
                ],
                onTap: () => _drill(r),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
