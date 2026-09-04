// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Branch Report (route /mis/branch-report). The per-branch Report Card:
//  month-end portfolio, collection performance and the business projection —
//  one /branch-report call, entirely server-scoped (a BM/FO only ever gets
//  their own branch; requesting another returns 403). Ports
//  BranchReportScreen.tsx. Read-only: no figure on this screen can be edited.
//
//  Every figure, including the BUSINESS Projection, is a PURE READ from the
//  server — nothing here is computed, rolled forward, or blended with any
//  live data (see BranchProjectionMonth in mis_models.dart). Image/CSV
//  export mirror the web's downloadImage/downloadCsv exactly.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_export.dart';
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

// The circulated PDF is a single sheet of navy-banded tables (BranchReport.css
// on web) — reproduced here rather than restyled as generic MIS cards, so a
// figure can be checked against the file it came from without re-reading the
// layout first. Fixed regardless of the app's (per-company) brand colour —
// the navy IS the report card's identity.
const Color _brcNavy = Color(0xFF2F5597); // section bands + column headers
const Color _brcNavyDeep = Color(0xFF1F3864); // the title bar

class MisBranchReportScreen extends ConsumerStatefulWidget {
  const MisBranchReportScreen({super.key});

  @override
  ConsumerState<MisBranchReportScreen> createState() =>
      _MisBranchReportScreenState();
}

class _MisBranchReportScreenState extends ConsumerState<MisBranchReportScreen> {
  String? _branch; // null → the server resolves the caller's own branch
  String? _month; // null → the branch's latest month

  // The report card ("brc-sheet" on web) is the capture target for the Image
  // export — title bar through the Projection table, not the pickers or the
  // IMPORTANT notes below it.
  final GlobalKey _sheetKey = GlobalKey();
  bool _shooting = false;
  bool _exportingCsv = false;

  @override
  Widget build(BuildContext context) {
    final q = BranchReportQuery(branch: _branch, month: _month);
    final async = ref.watch(misBranchReportProvider(q));
    final data = async.valueOrNull;
    final canExport = data?.portfolio != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Branch Report'),
        actions: [
          IconButton(
            tooltip: 'Download the report card as a PNG, exactly as shown',
            onPressed: !canExport || _shooting ? null : () => _downloadImage(data!),
            icon: _shooting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed:
                !canExport || _exportingCsv ? null : () => _downloadCsv(data!),
            icon: _exportingCsv
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
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

  // ── PNG of the sheet, exactly as rendered ──────────────────────────────────
  Future<void> _downloadImage(BranchReportResponse data) async {
    if (_shooting) return;
    setState(() => _shooting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _sheetKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      if (!mounted) return;
      await misSaveImage(
        context,
        'Report Card - ${data.branch ?? 'branch'}.png',
        bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not create the report image: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  // ── CSV of exactly what is on screen — mirrors downloadCsv() on the web ────
  Future<void> _downloadCsv(BranchReportResponse data) async {
    final pf = data.portfolio;
    if (pf == null || _exportingCsv) return;
    setState(() => _exportingCsv = true);
    try {
      String r1(double? v) => v == null ? '' : v.toStringAsFixed(1);
      String r2(double? v) => v == null ? '' : v.toStringAsFixed(2);
      final perf = data.performance;
      final proj = data.projection;
      final rows = <List<Object?>>[
        [
          'BRANCH REPORT CARD',
          data.branch,
          'BM: ${data.bmName ?? '—'}',
          "FO's: ${data.foCount}",
        ],
        [],
        ['Portfolio', 'as on ${pf.label}'],
        [
          '', 'Total POS', '', 'Regular', '', '1-90 Days', '', 'NPA',
          '', 'Reg.Cust/FO', 'OD.Cust/FO',
        ],
        [
          '', 'Accounts', 'Amount', 'Accounts', 'Amount', 'Accounts',
          'Amount', 'Accounts', 'Amount', '', '',
        ],
        [
          'TOTAL',
          pf.total.accounts, pf.total.amount,
          pf.regular.accounts, pf.regular.amount,
          pf.od1To90.accounts, pf.od1To90.amount,
          pf.npa.accounts, pf.npa.amount,
          r1(pf.regCustPerFo), r1(pf.odCustPerFo),
        ],
        [],
        ['Collection Performance', for (final p in perf) p.label],
        ['FTOD', for (final p in perf) p.ftod ?? ''],
        [
          'Regular Collection %',
          for (final p in perf) r2(p.regularCollectionPct),
        ],
        ['NPA %', for (final p in perf) r2(p.npaPct)],
        ['NPA Coll. Amount', for (final p in perf) p.npaCollectionAmount ?? ''],
        ['NPA Collection %', for (final p in perf) r2(p.npaCollectionPct)],
        [],
        ['BUSINESS Projection', for (final c in proj) c.label],
        ['a) Opening Active A/c', for (final c in proj) c.openingAcc ?? ''],
        ['b) Opening POS', for (final c in proj) c.openingPos ?? ''],
        ['c) Closure A/c', for (final c in proj) c.closureAcc ?? ''],
        ['d) Closure POS', for (final c in proj) c.closurePos ?? ''],
        ['e) DB A/c', for (final c in proj) c.dbAcc ?? ''],
        ['f) DB Amt', for (final c in proj) c.dbAmt ?? ''],
        ['g) Closing Active A/c', for (final c in proj) c.closingAcc ?? ''],
        ['h) Closing POS', for (final c in proj) c.closingPos ?? ''],
      ];
      final csv = misCsvDocument(rows);
      if (!mounted) return;
      await misSaveCsv(context, 'Report Card - ${data.branch}.csv', csv);
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
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
            Builder(builder: (context) {
              // The screen itself stays portrait — only the report card
              // renders as landscape, rotated in place and anchored to the
              // left edge (not centred), so its tables get a wide-format
              // layout without the device actually turning. quarterTurns: 3
              // (not 1) so the Column's first child — the title bar — lands
              // on the LEFT edge of the rotated card, not the right.
              //
              // Pre-rotation width = the portrait screen's HEIGHT (matching
              // what an actual landscape screen's width would have offered
              // the tables) and pre-rotation height = the portrait screen's
              // OWN width (so after the 90° turn the card's rendered width
              // lands back exactly at the phone's real width). That's still
              // just a viewport, not a hard cap on the content — the scroll
              // view lets the full report scroll vertically inside it so
              // nothing is ever clipped, however long the branch's data.
              // (No horizontal scroll needed alongside it: every table's
              // columns are laid out with flex, so they already always fit
              // this exact width — nesting one here would give the inner
              // view an unbounded height and crash the whole card.)
              final size = MediaQuery.of(context).size;
              return RepaintBoundary(
                key: _sheetKey,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SizedBox(
                      width: size.height,
                      height: size.width,
                      child: SingleChildScrollView(
                        child: Container(
                          // The capture target needs an opaque background —
                          // a RepaintBoundary paints transparent otherwise,
                          // which comes out as a black PNG.
                          color: AppColors.bg,
                          child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _titleBar(data),
                        _band('Portfolio',
                            note:
                                'as on ${pf.label} ${pf.month.length >= 4 ? pf.month.substring(0, 4) : ''}'),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: _portfolioTable(pf),
                        ),
                        _band('Collection Performance',
                            note:
                                'last ${data.performance.length} month${data.performance.length == 1 ? '' : 's'}'),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: _performanceTable(data.performance),
                        ),
                        if (data.projection.isNotEmpty) ...[
                          _band('BUSINESS', center: 'Projection'),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: _projectionTable(data.projection),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
              ),
                ),
              ),
              );
            }),
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

  /// The sheet's title bar — "BRANCH REPORT CARD · <BRANCH> · BM / FO's",
  /// navy-deep on white, matching `.brc-title` on web exactly. Phones are
  /// narrow, so it stacks (mirrors the web's own <720px layout).
  Widget _titleBar(BranchReportResponse data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: _brcNavyDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.apartment_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              const Text(
                'BRANCH REPORT CARD',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (data.branch ?? '—').toUpperCase(),
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            "BM: ${data.bmName ?? '—'}   ·   FO's: ${data.foCount > 0 ? data.foCount : '—'}",
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white70),
          ),
        ],
      ),
    );
  }

  /// One section band — "Portfolio", "Collection Performance", "BUSINESS" —
  /// navy full width with white bold text, matching `.brc-band` on web. Either
  /// a right-aligned [note] (Portfolio/Collection Performance) or a
  /// [center]-aligned caption (BUSINESS · Projection).
  Widget _band(String title, {String? note, String? center}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: _brcNavy,
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.white),
          ),
          if (center != null)
            Expanded(
              child: Text(
                center,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white),
              ),
            ),
          if (note != null) ...[
            const Spacer(),
            Text(
              note,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _portfolioTable(BranchPortfolio pf) {
    MisCell acc(BrPortfolioCell c) => c.accounts == null
        ? const MisCell.dash()
        : MisCell(_count(c.accounts), weight: FontWeight.w700);
    MisCell amt(BrPortfolioCell c) => MisCell(_inr(c.amount));
    return MisFlexMatrixTable(
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
      stubFlex: 2,
      cellFlex: 2,
      headerColor: _brcNavy,
      groupHeaderColor: _brcNavy,
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

    return MisFlexMatrixTable(
      stubHeader: 'Metric',
      headers: [for (final p in perf) header(p)],
      stubFlex: 4,
      cellFlex: 3,
      headerColor: _brcNavy,
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

  // Every column here is a pure read from the server (BranchProjectionMonth)
  // — no roll-forward arithmetic, same as the web port's projection table.
  Widget _projectionTable(List<BranchProjectionMonth> cols) {
    if (cols.isEmpty) {
      return const MisInlineEmpty('No projection window for this month.');
    }
    MisMatrixRow row(
            String name, MisCell Function(BranchProjectionMonth) cell) =>
        MisMatrixRow(
            lead: MisLead(name), cells: [for (final c in cols) cell(c)]);
    MisCell accCell(double? v) =>
        v == null ? const MisCell.dash() : MisCell(_count(v));
    MisCell amtCell(double? v) =>
        v == null ? const MisCell.dash() : MisCell(_inr(v));
    return MisFlexMatrixTable(
      stubHeader: 'Projection',
      headers: [for (final c in cols) c.label],
      stubFlex: 5,
      cellFlex: 3,
      headerColor: _brcNavy,
      rows: [
        row('a) Opening Active A/c', (c) => accCell(c.openingAcc)),
        row('b) Opening POS', (c) => amtCell(c.openingPos)),
        row('c) Closure A/c', (c) => accCell(c.closureAcc)),
        row('d) Closure POS', (c) => amtCell(c.closurePos)),
        row('e) DB A/c', (c) => accCell(c.dbAcc)),
        row('f) DB Amt', (c) => amtCell(c.dbAmt)),
        row('g) Closing Active A/c', (c) => accCell(c.closingAcc)),
        row('h) Closing POS',
            (c) => c.closingPos == null
                ? const MisCell.dash()
                : MisCell(_inr(c.closingPos), weight: FontWeight.w700)),
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
