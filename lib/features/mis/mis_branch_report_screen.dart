// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Branch Report (route /mis/branch-report). The per-branch Report Card:
//  month-end portfolio, collection performance and the business projection —
//  one /branch-report call, entirely server-scoped (a BM/FO only ever gets
//  their own branch; requesting another returns 403). Ports
//  BranchReportScreen.tsx. Read-only: no figure on this screen can be edited.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_matrix_table.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

// This screen prints PLAIN Indian-grouped rupees (not crores) — it mirrors the
// circulated Report Card sheet, where figures are compared against the PDF
// digit for digit. "—" means not loaded; never a zero.
String _inr(double? v) => v == null ? '—' : misNum(v.round());
String _count(double? v) => v == null ? '—' : misNum(v.round());
String _pct1(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
String _pct2(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)}%';
String _ratio1(double? v) => v == null ? '—' : v.toStringAsFixed(1);

const _monShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class _ProjCol {
  final String label; // "Aug-26"
  final double? openAcc;
  final double openPos;
  final double? closureAcc;
  final double closurePos;
  final double dbAcc;
  final double dbAmt;
  final double? closeAcc;
  final double closePos;
  const _ProjCol({
    required this.label,
    this.openAcc,
    required this.openPos,
    this.closureAcc,
    required this.closurePos,
    required this.dbAcc,
    required this.dbAmt,
    this.closeAcc,
    required this.closePos,
  });
}

/// Months after the reporting month up to the fiscal-year end (Mar), max 12.
List<({String key, String label})> _projectionMonths(String fromMonth) {
  final y = int.tryParse(fromMonth.substring(0, 4)) ?? 0;
  final m = int.tryParse(fromMonth.substring(5, 7)) ?? 1;
  final out = <({String key, String label})>[];
  var yy = y;
  var mm = m + 1;
  if (mm > 12) {
    mm = 1;
    yy += 1;
  }
  final endYear = mm > 3 ? yy + 1 : yy;
  while ((yy < endYear || (yy == endYear && mm <= 3)) && out.length < 12) {
    out.add((
      key: '$yy-${mm.toString().padLeft(2, '0')}-01',
      label: '${_monShort[mm - 1]}-${yy.toString().substring(2)}',
    ));
    mm += 1;
    if (mm > 12) {
      mm = 1;
      yy += 1;
    }
  }
  return out;
}

/// Rolls the opening balances forward with the published assumption rates.
/// FIDELITY RULE (from the web port): accounts are rounded every month, rupees
/// are NOT — the rupee chain runs at full precision and is rounded once at
/// display. Rounding rupees per month drifts off the circulated PDF by the
/// third column.
List<_ProjCol> _buildProjection(BranchProjectionSeed seed) {
  final months = _projectionMonths(seed.fromMonth);
  double? openAcc = seed.openingAccounts;
  double openPos = seed.openingPos;
  return [
    for (final m in months)
      () {
        final closureAcc = openAcc == null
            ? null
            : (openAcc! * (seed.closureAccPct / 100)).roundToDouble();
        final closurePos = openPos * (seed.closurePosPct / 100);
        final closeAcc = openAcc == null || closureAcc == null
            ? null
            : openAcc! - closureAcc + seed.disbAccounts;
        final closePos = openPos - closurePos + seed.disbAmount;
        final col = _ProjCol(
          label: m.label,
          openAcc: openAcc,
          openPos: openPos,
          closureAcc: closureAcc,
          closurePos: closurePos,
          dbAcc: seed.disbAccounts,
          dbAmt: seed.disbAmount,
          closeAcc: closeAcc,
          closePos: closePos,
        );
        openAcc = closeAcc;
        openPos = closePos;
        return col;
      }(),
  ];
}

class MisBranchReportScreen extends ConsumerStatefulWidget {
  const MisBranchReportScreen({super.key});

  @override
  ConsumerState<MisBranchReportScreen> createState() =>
      _MisBranchReportScreenState();
}

class _MisBranchReportScreenState extends ConsumerState<MisBranchReportScreen> {
  String? _branch; // null → the server resolves the caller's own branch
  String? _month; // null → the branch's latest month

  @override
  Widget build(BuildContext context) {
    final q = BranchReportQuery(branch: _branch, month: _month);
    final async = ref.watch(misBranchReportProvider(q));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Branch Report')),
      body: async.when(
        loading: () => const AppLoadingBlock(height: 240),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misBranchReportProvider(q)),
          ),
        ),
        data: (data) => _body(data, q),
      ),
    );
  }

  Widget _body(BranchReportResponse data, BranchReportQuery q) {
    if (data.branches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: AppEmptyState(
          icon: Icons.apartment_rounded,
          message:
              "Your account isn't mapped to a branch yet, so there is no report card to show.",
        ),
      );
    }
    final branch = _branch ?? data.branch;
    final pf = data.portfolio;

    // FY picker options — derived from the months the server actually has.
    final fyOptions = <int>{
      for (final m in data.months) misFyStart(m),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final currentFy = data.month != null ? misFyStart(data.month!) : null;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(misBranchReportProvider(q)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
        children: [
          if (data.tier != 'all') ...[
            Align(alignment: Alignment.centerLeft, child: _scopeChip(data.tier)),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: MisDropdown<String>(
                  label: 'Branch',
                  value: branch ?? '',
                  items: [
                    for (final b in data.branches)
                      DropdownMenuItem(
                        value: b.branch,
                        child: Text(b.branch, overflow: TextOverflow.ellipsis),
                      ),
                    if (branch == null)
                      const DropdownMenuItem(value: '', child: Text('—')),
                  ],
                  // Changing branch clears the month so the server picks that
                  // branch's latest.
                  onChanged: data.branches.length <= 1
                      ? (_) {}
                      : (v) => setState(() {
                            _branch = (v == null || v.isEmpty) ? null : v;
                            _month = null;
                          }),
                ),
              ),
              if (fyOptions.length > 1) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: MisDropdown<int>(
                    label: 'Financial year',
                    value: currentFy ?? fyOptions.first,
                    items: [
                      for (final fy in fyOptions)
                        DropdownMenuItem(
                            value: fy, child: Text(misFyLabel(fy))),
                    ],
                    onChanged: (fy) {
                      if (fy == null) return;
                      // months are newest-first: the first hit is the FY's
                      // latest loaded month.
                      for (final m in data.months) {
                        if (misFyStart(m) == fy) {
                          setState(() => _month = m);
                          return;
                        }
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (pf == null)
            MisInlineEmpty(
                "${data.branch ?? 'This branch'} has no month-end POS loaded, so the report card can't be drawn.")
          else ...[
            _titleCard(data),
            const SizedBox(height: 16),
            MisSectionTitle(
                'Portfolio — as on ${pf.label} ${pf.month.length >= 4 ? pf.month.substring(0, 4) : ''}'),
            _portfolioTable(pf),
            const SizedBox(height: 18),
            MisSectionTitle(
                'Collection Performance — last ${data.performance.length} month${data.performance.length == 1 ? '' : 's'}'),
            _performanceTable(data.performance),
            if (data.projection != null) ...[
              const SizedBox(height: 18),
              const MisSectionTitle('Business Projection'),
              _assumptions(data),
              const SizedBox(height: 10),
              _projectionTable(data.projection!),
            ],
            const SizedBox(height: 18),
            _important(data),
          ],
        ],
      ),
    );
  }

  Widget _scopeChip(String tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, size: 11, color: AppColors.warning),
          const SizedBox(width: 5),
          Text(
            '${misTierLabel(tier)} view',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleCard(BranchReportResponse data) {
    return GlassCard(
      child: Row(
        children: [
          // AppColors.primary is runtime-brandable, so this Icon can't be const.
          Icon(Icons.apartment_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BRANCH REPORT CARD',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.branch ?? '—',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('BM: ${data.bmName ?? '—'}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft)),
              Text("FO's: ${data.foCount > 0 ? data.foCount : '—'}",
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _portfolioTable(BranchPortfolio pf) {
    MisCell acc(BrPortfolioCell c) => c.accounts == null
        ? const MisCell.dash()
        : MisCell(_count(c.accounts), weight: FontWeight.w700);
    MisCell amt(BrPortfolioCell c) => MisCell(_inr(c.amount));
    return MisMatrixTable(
      stubHeader: '',
      groups: const [
        MisGroup('Total POS', 2),
        MisGroup('Regular', 2),
        MisGroup('1-90 Days', 2),
        MisGroup('NPA', 2),
        MisGroup('Per FO', 2),
      ],
      headers: const [
        'Acc', 'Amount', 'Acc', 'Amount', 'Acc', 'Amount', 'Acc', 'Amount',
        'Reg.Cust', 'OD.Cust',
      ],
      stubWidth: 64,
      cellWidth: 92,
      rows: [
        MisMatrixRow(
          lead: const MisLead('TOTAL'),
          kind: MisRowKind.total,
          cells: [
            acc(pf.total),
            amt(pf.total),
            acc(pf.regular),
            amt(pf.regular),
            acc(pf.od1To90),
            amt(pf.od1To90),
            acc(pf.npa),
            amt(pf.npa),
            pf.regCustPerFo == null
                ? const MisCell.dash()
                : MisCell(_ratio1(pf.regCustPerFo)),
            pf.odCustPerFo == null
                ? const MisCell.dash()
                : MisCell(_ratio1(pf.odCustPerFo)),
          ],
        ),
      ],
    );
  }

  Widget _performanceTable(List<BranchPerformance> perf) {
    String header(BranchPerformance p) {
      // A part month is flagged in its header — it reads low otherwise.
      if (p.lastDate != null && !p.monthComplete && p.lastDate!.length >= 10) {
        return '${p.label} (to ${p.lastDate!.substring(8, 10)}/${p.lastDate!.substring(5, 7)})';
      }
      return p.label;
    }

    MisMatrixRow row(String name, MisCell Function(BranchPerformance) cell) =>
        MisMatrixRow(
            lead: MisLead(name), cells: [for (final p in perf) cell(p)]);

    return MisMatrixTable(
      stubHeader: 'Metric',
      headers: [for (final p in perf) header(p)],
      stubWidth: 128,
      cellWidth: 104,
      rows: [
        row('FTOD', (p) => MisCell(_count(p.ftod))),
        row('Regular Collection %',
            (p) => MisCell(_pct1(p.regularCollectionPct))),
        row('NPA %', (p) => MisCell(_pct2(p.npaPct))),
        row('NPA Coll. Amount', (p) => MisCell(_inr(p.npaCollectionAmount))),
        row('NPA Collection %', (p) => MisCell(_pct2(p.npaCollectionPct))),
      ],
    );
  }

  Widget _assumptions(BranchReportResponse data) {
    final seed = data.projection!;
    Widget field(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
          ],
        );
    return GlassCard(
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          field('Closure A/c', '${seed.closureAccPct}% of opening'),
          field('Closure POS', '${seed.closurePosPct}% of opening'),
          field('DB A/c', '${_count(seed.disbAccounts)} / month'),
          field('DB Amt', '₹${_inr(seed.disbAmount)} / month'),
          field(
            'Disbursement basis',
            seed.disbBasisMonths > 0
                ? '${data.branch ?? 'branch'} average, last ${seed.disbBasisMonths} month(s)'
                : 'no disbursement history',
          ),
        ],
      ),
    );
  }

  Widget _projectionTable(BranchProjectionSeed seed) {
    final cols = _buildProjection(seed);
    if (cols.isEmpty) {
      return const MisInlineEmpty('No projection window for this month.');
    }
    MisMatrixRow row(String name, MisCell Function(_ProjCol) cell) =>
        MisMatrixRow(
            lead: MisLead(name), cells: [for (final c in cols) cell(c)]);
    MisCell accCell(double? v) =>
        v == null ? const MisCell.dash() : MisCell(_count(v));
    return MisMatrixTable(
      stubHeader: 'Projection',
      headers: [for (final c in cols) c.label],
      stubWidth: 148,
      cellWidth: 104,
      rows: [
        row('a) Opening Active A/c', (c) => accCell(c.openAcc)),
        row('b) Opening POS', (c) => MisCell(_inr(c.openPos))),
        row('c) Closure A/c', (c) => accCell(c.closureAcc)),
        row('d) Closure POS', (c) => MisCell(_inr(c.closurePos))),
        row('e) DB A/c', (c) => MisCell(_count(c.dbAcc))),
        row('f) DB Amt', (c) => MisCell(_inr(c.dbAmt))),
        row('g) Closing Active A/c', (c) => accCell(c.closeAcc)),
        row('h) Closing POS',
            (c) => MisCell(_inr(c.closePos), weight: FontWeight.w700)),
      ],
    );
  }

  Widget _important(BranchReportResponse data) {
    final pf = data.portfolio!;
    final partMonth = data.performance
        .any((p) => p.lastDate != null && !p.monthComplete);
    final lines = <String>[
      if (!pf.hasBucketAccounts)
        '${pf.label} has no PAR bucket split — Regular / 1-90 / NPA accounts and both per-FO ratios are blank.',
      if (partMonth) 'A column headed with a date is a part month and reads low.',
      '— means not loaded. Never a zero.',
      '1-90 Days = SMA-0 + SMA-1 + PNPA. Regular + 1-90 + NPA = Total.',
      'Accounts come from the PAR; amounts from month-end POS.',
      'Collection rows are read at each month\'s last collection date.',
      'FTOD = month-end demand − collection.',
      'NPA % = NPA POS ÷ Total POS. NPA Collection % = recovery ÷ NPA POS.',
      'Projection is a plan, not recorded data.',
      'Read only. No figure on this screen can be edited.',
      if (data.tier != 'all') 'Figures are limited to your access level.',
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'IMPORTANT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle,
                        size: 5, color: AppColors.muted),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(l,
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: AppColors.inkSoft)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
