// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Portfolio (route /mis/portfolio). POS by status/bucket for a month with
//  a region → division → area → branch drill-down. Ports PortfolioScreen.tsx.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_charts.dart';
import 'mis_clients_screen.dart';
import 'mis_collection_widgets.dart';
import 'mis_format.dart';
import 'mis_matrix_table.dart';
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
    // The hero reads the same summary the bucket table shows (an opened
    // officer's comes from the drill row).
    final heroSummary =
        _empRow != null ? _empRow!.toSummary() : summaryAsync.valueOrNull;

    return ProPage(
      onRefresh: () async {
        ref.invalidate(misPortfolioSummaryProvider(q));
        ref.invalidate(misPortfolioUnitsProvider(q));
      },
      hero: ProHero(
        titleWidget: MisDeepTitle(title: 'Portfolio', crumbs: _crumbs()),
        // No cards/table toggle, matching the web: the drill is always the
        // table, so units line up for comparison down a column.
        overlap: MisLiftedField(
          child: MisMonthPicker(
            value: activeMonth,
            available: months,
            onChanged: (v) => setState(() => _month = v),
          ),
        ),
        children: [
          MisDeepSegmented<String>(
            options: _products,
            value: _product,
            onChanged: (v) => setState(() => _product = v),
          ),
          _heroFigures(heroSummary),
        ],
      ),
      children: [
        if (_empRow != null)
          // An opened field officer is a leaf: show that FO's bucket-wise
          // portfolio (built from the drill row) and no further drill grid.
          _summary(_empRow!.toSummary(), activeMonth)
        else ...[
          summaryAsync.when(
            loading: () => const AppLoadingBlock(height: 200),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(misPortfolioSummaryProvider(q)),
            ),
            data: (s) => _summary(s, activeMonth),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              ProSectionHeader(
                title: 'By ${_levelLabel[q.level]!.toLowerCase()}',
                subtitle: 'Tap a row to drill down. Swipe the table for '
                    'every band.',
              ),
              const SizedBox(height: 10),
              _grid(q),
            ],
          ),
        ],
      ],
    );
  }

  /// Grand-total POS, accounts and the bucket share bar for the hero — the
  /// same figures as the bucket table's Grand Total row. "—" while loading.
  Widget _heroFigures(PortfolioSummary? s) {
    double amt(String k) => s?.amt(k) ?? 0;
    const buckets = ['regular', 'sma0', 'sma1', 'pnpa', 'npa'];
    final total = amt('total');
    final accTotal =
        buckets.fold<double>(0, (sum, k) => sum + amt('${k}_acc'));
    final hasAcc = accTotal > 0;
    String pct(double v) =>
        total > 0 ? '${(v / total * 100).toStringAsFixed(1)}%' : '-';
    final shares = [
      for (final st in _status)
        if (st.$1 != 'total' && amt(st.$1) > 0)
          (key: st.$1, label: st.$2, value: amt(st.$1)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MisDeepLabel(
          _empName != null ? 'Portfolio — $_empName' : 'Bucket-wise portfolio',
        ),
        const SizedBox(height: 8),
        ProHeroStats(stats: [
          ProStat(
            label: 'Grand total POS',
            value: s == null ? '—' : misRupees(total),
            sub: 'All buckets',
            dot: const Color(0xFF8FD0DB),
          ),
          ProStat(
            label: 'Accounts',
            value: s == null ? '—' : (hasAcc ? misNum(accTotal) : '—'),
            sub: s == null
                ? null
                : (hasAcc ? 'NPA ${pct(amt('npa'))} of POS' : 'no PAR data'),
            dot: AppColors.live,
          ),
        ]),
        if (shares.isNotEmpty) ...[
          const SizedBox(height: 14),
          ProStackBar(
            height: 8,
            parts: [
              for (final b in shares)
                MapEntry(b.value, MisPalette.risk(b.key)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final b in shares)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: MisPalette.risk(b.key),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${b.label} ',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70),
                    ),
                    Text(
                      pct(b.value),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Breadcrumb-style label for the open scope, reused by the client-details
  /// screen so the export filename and header say what was actually listed.
  String get _scopeLabel {
    final parts = [_region, _division, _area, _branch, _empName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' › ');
    return parts.isEmpty ? 'All regions' : parts;
  }

  /// Open the client-level detail behind one DPD bucket, for the current scope.
  void _openClients(
    String bucketKey,
    String bucketLabel,
    String? activeMonth,
    double? accounts,
  ) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MisClientsScreen(
        bucketKey: bucketKey,
        bucketLabel: bucketLabel,
        scopeLabel: _scopeLabel,
        bucketAccounts: accounts,
        baseQuery: ClientsQuery(
          // /clients takes YYYY-MM; the picker's months are period dates
          // (YYYY-MM-01), so trim to the month.
          month: (activeMonth != null && activeMonth.length >= 7)
              ? activeMonth.substring(0, 7)
              : activeMonth,
          product: _product,
          region: _region,
          division: _division,
          area: _area,
          branch: _branch,
          // The report's OfficerID is a source-system code, passed through as-is.
          officer: _emp,
        ),
      ),
    ));
  }

  Widget _summary(PortfolioSummary s, String? activeMonth) {
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        ProSectionHeader(
          title: _empName != null
              ? 'Bucket-wise portfolio — $_empName'
              : 'Bucket-wise portfolio',
          subtitle: activeMonth == null ? null : misMonthLabel(activeMonth),
        ),
        const SizedBox(height: 10),
        MisMatrixTable(
          stubHeader: 'Bucket',
          headers: const ['Accounts', 'POS (amount)', '% contrib'],
          rows: [
            for (final st in _status)
              MisMatrixRow(
                kind: st.$1 == 'total' ? MisRowKind.total : MisRowKind.normal,
                lead: MisLead(st.$2, chip: MisPalette.risk(st.$1)),
                cells: [
                  MisCell(hasAcc
                      ? misNum(st.$1 == 'total'
                          ? bucketAccTotal
                          : bucketAcc(st.$1))
                      : '—'),
                  MisCell(misRupees(amt(st.$1))),
                  MisCell(
                    st.$1 == 'total' ? '100%' : pctContrib(amt(st.$1)),
                    color: st.$1 == 'total' ? null : MisPalette.risk(st.$1),
                    weight: FontWeight.w600,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 22),
        // Every bucket — Grand Total included — carries a "Customer details"
        // button that opens the individual clients (loan accounts) in it, for
        // whatever scope is currently open. Mirrors the web's per-row button;
        // on a phone they sit under the table so the table stays readable.
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProSectionHeader(
                title: 'Customer details',
                subtitle: 'Open the customer list for a bucket',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final st in _status)
                    _BucketChip(
                      label: st.$2,
                      color: MisPalette.risk(st.$1),
                      onTap: () => _openClients(
                        st.$1,
                        st.$2,
                        activeMonth,
                        hasAcc
                            ? (st.$1 == 'total'
                                ? bucketAccTotal
                                : bucketAcc(st.$1))
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
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
          return const ProEmpty(
            icon: Icons.table_rows_outlined,
            title: 'No portfolio at this level.',
          );
        }
        // Per-bucket account counts come from the PAR load and only exist for
        // months whose PAR was ingested. When the whole grid has none, show "—"
        // rather than a column of zeros that reads as "no loans".
        final hasAcc = rows.any((r) => r.totalAcc > 0);

        // Three POS bands plus the total, each showing Accounts and POS side by
        // side. 1-90 DPD = SMA-0 + SMA-1 + SMA-2/PNPA, so Reg.POS + 1-90 + NPA
        // reconstitute the book and Total is the backend's own figure.
        double regAcc(PortfolioUnitRow r) => r.regularAcc;
        double dpdAcc(PortfolioUnitRow r) =>
            r.sma0Acc + r.sma1Acc + r.pnpaAcc;
        double dpdPos(PortfolioUnitRow r) =>
            (r.pos['sma0'] ?? 0) + (r.pos['sma1'] ?? 0) + (r.pos['pnpa'] ?? 0);

        var tRegA = 0.0, tRegP = 0.0, tDpdA = 0.0, tDpdP = 0.0;
        var tNpaA = 0.0, tNpaP = 0.0, tTotP = 0.0;
        for (final r in rows) {
          tRegA += regAcc(r);
          tRegP += r.pos['regular'] ?? 0;
          tDpdA += dpdAcc(r);
          tDpdP += dpdPos(r);
          tNpaA += r.npaAcc;
          tNpaP += r.npa;
          tTotP += r.total;
        }

        List<MisCell> bandCells(
          double ra, double rp, double da, double dp,
          double na, double np, double tp,
        ) =>
            [
              MisCell(hasAcc ? misNum(ra) : '—'),
              MisCell(misRupees(rp), color: AppColors.ink),
              MisCell(hasAcc ? misNum(da) : '—'),
              MisCell(misRupees(dp), color: AppColors.ink),
              MisCell(hasAcc ? misNum(na) : '—'),
              MisCell(misRupees(np), color: AppColors.ink),
              MisCell(hasAcc ? misNum(ra + da + na) : '—'),
              MisCell(misRupees(tp), weight: FontWeight.w600),
            ];

        return MisMatrixTable(
          stubHeader: _levelLabel[q.level]!,
          groups: const [
            MisGroup('Reg.POS', 2),
            MisGroup('1-90 DPD', 2),
            MisGroup('NPA', 2),
            MisGroup('Total', 2),
          ],
          headers: const [
            'Accounts', 'POS',
            'Accounts', 'POS',
            'Accounts', 'POS',
            'Accounts', 'POS',
          ],
          rows: [
            for (final r in rows)
              MisMatrixRow(
                lead: MisLead(r.unit, note: isEmp ? r.empId : null),
                onTap: () => _drill(r),
                cells: bandCells(
                  regAcc(r), r.pos['regular'] ?? 0,
                  dpdAcc(r), dpdPos(r),
                  r.npaAcc, r.npa,
                  r.total,
                ),
              ),
            MisMatrixRow(
              kind: MisRowKind.total,
              lead: const MisLead('Total'),
              cells: bandCells(
                  tRegA, tRegP, tDpdA, tDpdP, tNpaA, tNpaP, tTotP),
            ),
          ],
        );
      },
    );
  }
}

/// "Customer details" link for one bucket: a white pill with the bucket's
/// colour on the icon.
class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const StadiumBorder(side: BorderSide(color: Color(0xFFDBE3E5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
