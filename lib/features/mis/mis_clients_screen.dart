// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Customer details — the client-level detail behind ONE portfolio DPD
//  bucket, at whatever level the Portfolio screen is drilled to (region →
//  division → area → branch → field officer). Backed by `GET /clients/list`;
//  search, sorting and paging are all server-side. Ports PortfolioClientsPanel.
//
//  Row detail only exists for months with a loaded PAR snapshot. On an aggregate
//  month the API answers 409 and names the months that DO have detail — shown
//  here as a plain notice rather than an error.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_api_client.dart';
import 'mis_charts.dart';
import 'mis_export.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

/// Page sizes offered by the pager.
const List<int> _pageSizes = [25, 50, 100, 200];

/// `/clients/list` caps a request at 5000 rows and has no server-side export, so
/// an export pages through it and builds the CSV here. Bounded so a 118k-row NPA
/// bucket can't run away — the user is told when the cap truncates the file.
const int _exportChunk = 5000;
const int _exportMax = 50000;

/// The columns the API can sort on, under their exact source-workbook names.
const List<(String, String)> _sortOptions = [
  ('PrincipalOS', 'Principal O/S'),
  ('TotalArrear', 'Total Arrear'),
  ('LoanAmount', 'Loan Amount'),
  ('DueDays', 'Due Days'),
  ('DisbursementDate', 'Disbursed On'),
  ('Client Name', 'Client Name'),
  ('BranchName', 'Branch'),
  ('OfficerName', 'Officer'),
  ('AccountID', 'Account ID'),
];

/// Every column the report carries, in the workbook's order — used by the detail
/// sheet and as the CSV fallback header when the API doesn't send `headers`.
const List<(String, String)> _allColumns = [
  ('ClientID', 'Client ID'),
  ('Client Name', 'Client Name'),
  ('Mobile No', 'Mobile No'),
  ('AccountID', 'Account ID'),
  ('Product Name', 'Product'),
  ('BranchName', 'Branch'),
  ('OfficerName', 'Officer'),
  ('OfficerID', 'Officer ID'),
  ('GroupName', 'Group'),
  ('Region', 'Region'),
  ('Division', 'Division'),
  ('Area', 'Area'),
  ('DisbursementDate', 'Disbursed On'),
  ('LoanAmount', 'Loan Amount'),
  ('InstallmentAmount', 'Installment'),
  ('PrincipalOS', 'Principal O/S'),
  ('TotalArrear', 'Total Arrear'),
  ('DueDays', 'Due Days'),
  ('DPD Days', 'DPD'),
  ('LoanMaturityDate', 'Maturity'),
  ('Bucket', 'Bucket'),
];

/// Money columns render in Crore like the rest of MIS; date columns pretty-print.
const Set<String> _moneyColumns = {
  'LoanAmount',
  'InstallmentAmount',
  'PrincipalOS',
  'TotalArrear',
};
const Set<String> _dateColumns = {'DisbursementDate', 'LoanMaturityDate'};

String _display(ClientRow r, String key) {
  final raw = r.raw[key];
  if (raw == null || raw.toString().trim().isEmpty) return '—';
  if (_moneyColumns.contains(key)) {
    final v = r.number(key);
    return v == null ? raw.toString() : misRupees(v);
  }
  if (_dateColumns.contains(key)) return misPrettyDate(raw.toString());
  if (key == 'DueDays') {
    final v = r.number(key);
    return v == null ? raw.toString() : misNum(v);
  }
  return raw.toString();
}

class MisClientsScreen extends ConsumerStatefulWidget {
  const MisClientsScreen({
    super.key,
    required this.bucketKey,
    required this.bucketLabel,
    required this.scopeLabel,
    required this.baseQuery,
    this.bucketAccounts,
  });

  /// Screen bucket key — "total" lists every bucket in scope.
  final String bucketKey;
  final String bucketLabel;

  /// Human-readable scope ("TUMKUR › SIRA › …") shown under the title.
  final String scopeLabel;

  /// Month + product + open drill levels, forwarded to `/clients/list`.
  final ClientsQuery baseQuery;

  /// Account count for the bucket, when the month carried per-bucket counts.
  final double? bucketAccounts;

  @override
  ConsumerState<MisClientsScreen> createState() => _MisClientsScreenState();
}

class _MisClientsScreenState extends ConsumerState<MisClientsScreen> {
  final _searchCtrl = TextEditingController();

  String _query = ''; // what's been submitted (not what's typed)
  String? _sort;
  bool _ascending = false;
  int _pageIndex = 0;
  int _size = _pageSizes.first;
  bool _exporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  ClientsQuery get _query4Page => widget.baseQuery.copyWith(
        bucket: widget.bucketKey,
        query: _query,
        sort: _sort,
        clearSort: _sort == null,
        ascending: _ascending,
        limit: _size,
        offset: _pageIndex * _size,
      );

  void _applySearch() {
    setState(() {
      _query = _searchCtrl.text.trim();
      _pageIndex = 0;
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _pageIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query4Page;
    final async = ref.watch(misClientsProvider(q));
    final res = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MIS'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exporting ? null : () => _export(async.valueOrNull),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: ProPage(
        onRefresh: () async => ref.invalidate(misClientsProvider(q)),
        hero: _hero(res),
        children: [
          _sortBar(),
          async.when(
            loading: () => const AppLoadingBlock(height: 220),
            error: (e, _) => _errorOrNotice(e),
            data: (res) => _results(res),
          ),
        ],
      ),
    );
  }

  Widget _hero(ClientsListResponse? res) {
    final bits = <String>[
      widget.scopeLabel,
      if (res != null && res.asOn.label.isNotEmpty) res.asOn.label,
    ];
    final total = res?.total;
    final totalPages =
        (total != null && total > 0) ? (total / _size).ceil() : 0;
    final hasBucketAcc =
        widget.bucketAccounts != null && widget.bucketAccounts! > 0;
    return ProHero(
      kicker: 'Customer details',
      title: 'Client details — ${widget.bucketLabel}',
      overlap: _searchBar(),
      children: [
        ProLiveLine(
          text: bits.join(' · '),
          color: MisPalette.risk(widget.bucketKey),
        ),
        ProHeroStats(stats: [
          ProStat(
            label: 'Accounts',
            value: hasBucketAcc ? misNum(widget.bucketAccounts) : '—',
            sub: 'in this bucket',
            dot: MisPalette.risk(widget.bucketKey),
          ),
          ProStat(
            label: _query.isEmpty ? 'Clients' : 'Matches',
            value: total == null ? '—' : misNum(total),
            sub: _query.isEmpty ? 'listed' : '“$_query”',
            dot: const Color(0xFF7FD3E3),
          ),
          ProStat(
            label: 'Page',
            value: totalPages == 0 ? '—' : '${_pageIndex + 1}/$totalPages',
            sub: '$_size per page',
            dot: AppColors.live,
          ),
        ]),
      ],
    );
  }

  /// Raised search over the hero. Search is server-side, so it runs on submit
  /// (keyboard action or the Search button), not on every keystroke.
  Widget _searchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.lifted,
      ),
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applySearch(),
              style: const TextStyle(fontSize: 15, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: 'Client ID, name, mobile, account, group or officer…',
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 19),
                        onPressed: _clearSearch,
                      ),
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          FilledButton(
            onPressed: _applySearch,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11)),
            ),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _sortBar() {
    return Row(
      children: [
        Expanded(
          child: MisDropdown<String?>(
            value: _sort,
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Default order')),
              for (final o in _sortOptions)
                DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2)),
            ],
            onChanged: (v) => setState(() {
              _sort = v;
              _pageIndex = 0;
            }),
          ),
        ),
        const SizedBox(width: 8),
        // Direction only means something once a sort column is chosen.
        IconButton(
          tooltip: _ascending ? 'Ascending' : 'Descending',
          onPressed: _sort == null
              ? null
              : () => setState(() {
                    _ascending = !_ascending;
                    _pageIndex = 0;
                  }),
          icon: Icon(
            _ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 20,
          ),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
      ],
    );
  }

  /// 409 = this month is aggregate-only, so there are no client rows to show.
  /// 404 = no snapshot at all for the period. Both are informative, not
  /// failures, so they render as a notice instead of an error panel.
  Widget _errorOrNotice(Object e) {
    final notice = _noticeFor(e);
    if (notice != null) {
      return ProNote(notice, tone: ProNoteTone.info);
    }
    return AppErrorPanel(
      message: e.toString(),
      onRetry: () => ref.invalidate(misClientsProvider(_query4Page)),
    );
  }

  String? _noticeFor(Object e) {
    if (e is! MisApiException) return null;
    if (e.statusCode == 404) {
      return 'No client snapshot exists for the selected period.';
    }
    if (e.statusCode != 409) return null;
    final months = e.payloadList('detail_months');
    final tail = months.isEmpty
        ? ''
        : ' Client detail is available for '
            '${months.map(misPrettyDate).join(', ')}.';
    return 'This month is served from the branch/officer portfolio aggregate, '
        'which has no client-level rows.$tail';
  }

  Widget _results(ClientsListResponse res) {
    final total = res.total;
    final totalPages = total > 0 ? (total / _size).ceil() : 0;
    final from = total == 0 ? 0 : _pageIndex * _size + 1;
    final to = ((_pageIndex + 1) * _size).clamp(0, total);

    if (res.rows.isEmpty) {
      return ProEmpty(
        icon: Icons.person_search_outlined,
        title: 'No clients found',
        message: _query.isNotEmpty
            ? 'No client matches “$_query” in this bucket.'
            : 'No clients in this bucket.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pager(total, totalPages, from, to),
        const SizedBox(height: 10),
        ProListGroup(
          dividerIndent: 0,
          children: [for (final r in res.rows) _clientCard(r)],
        ),
        const SizedBox(height: 10),
        _pager(total, totalPages, from, to),
      ],
    );
  }

  Widget _pager(int total, int totalPages, int from, int to) {
    final first = _pageIndex == 0;
    final last = totalPages == 0 || _pageIndex >= totalPages - 1;
    Widget pageBtn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(icon,
                    size: 20,
                    color: onTap == null ? AppColors.faint : AppColors.ink),
              ),
            ),
          ),
        );
    return Row(
      children: [
        pageBtn(Icons.chevron_left_rounded, 'Previous page',
            first ? null : () => setState(() => _pageIndex -= 1)),
        const SizedBox(width: 6),
        pageBtn(Icons.chevron_right_rounded, 'Next page',
            last ? null : () => setState(() => _pageIndex += 1)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            total > 0
                ? '${misNum(from)}–${misNum(to)} of ${misNum(total)}'
                    ' · page ${_pageIndex + 1} of $totalPages'
                : 'No rows',
            style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
        const Text('Rows',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: _size,
          isDense: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink),
          items: [
            for (final s in _pageSizes)
              DropdownMenuItem(value: s, child: Text('$s')),
          ],
          onChanged: (v) => setState(() {
            _size = v ?? _pageSizes.first;
            _pageIndex = 0;
          }),
        ),
      ],
    );
  }

  Widget _clientCard(ClientRow r) {
    final bucket = r.bucket ?? widget.bucketKey;
    final tone = MisPalette.risk(bucket.toLowerCase());
    final ids = [
      if (r.clientId != null) r.clientId,
      if (r.accountId != null) 'A/c ${r.accountId}',
      if (r.productName != null) r.productName,
    ].whereType<String>().join(' · ');
    final where =
        [r.branchName, r.officerName].whereType<String>().join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProIconWell(icon: Icons.person_outline_rounded, color: tone),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.clientName ?? r.clientId ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.15,
                            color: AppColors.ink,
                          ),
                        ),
                        if (ids.isNotEmpty)
                          Text(
                            ids,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        if (where.isNotEmpty)
                          Text(
                            where,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                      ],
                    ),
                  ),
                  if (r.mobile != null)
                    Tooltip(
                      message: 'Call ${r.mobile}',
                      child: Material(
                        color: AppColors.successTint,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _call(r.mobile!),
                          child: const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(Icons.call_rounded,
                                size: 18, color: AppColors.success),
                          ),
                        ),
                      ),
                    )
                  else
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: Color(0xFFB3C0C3)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: _metric('Principal O/S', r.principalOs, true)),
                    Expanded(
                        child: _metric('Total Arrear', r.totalArrear, true)),
                    Expanded(
                      child: _metric(
                        'Due Days',
                        r.dueDays,
                        false,
                        tone: (r.dueDays ?? 0) > 0 ? AppColors.danger : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, double? value, bool money, {Color? tone}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        const SizedBox(height: 1),
        Text(
          value == null ? '—' : (money ? misRupees(value) : misNum(value)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: tone ?? AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Future<void> _call(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Every column of one row — the mobile equivalent of the web's wide table.
  void _openDetail(ClientRow r) {
    final cols = [
      for (final c in _allColumns)
        if (r.raw.containsKey(c.$1)) c,
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (ctx, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6D3D6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ProIconWell(
                    icon: Icons.person_outline_rounded,
                    color: MisPalette.risk(
                        (r.bucket ?? widget.bucketKey).toLowerCase()),
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.clientName ?? r.clientId ?? 'Client',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(widget.bucketLabel, style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < cols.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : const Border(
                            top: BorderSide(color: AppColors.hairlineSoft)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          cols[i].$2,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _display(r, cols[i].$1),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.ink,
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
      ),
    );
  }

  /// Page through `/clients/list` and build the CSV here — the API has no export
  /// endpoint. Bounded at [_exportMax]; a truncated file is never silent.
  Future<void> _export(ClientsListResponse? current) async {
    final total = current?.total ?? 0;
    final messenger = ScaffoldMessenger.of(context);
    if (total == 0) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Nothing to export.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _exporting = true);
    try {
      final repo = ref.read(misRepositoryProvider);
      final base = _query4Page;
      final cap = total < _exportMax ? total : _exportMax;
      final collected = <ClientRow>[];
      var headers = current?.headers ?? const <String>[];

      for (var offset = 0; offset < cap; offset += _exportChunk) {
        final remaining = cap - offset;
        final chunk = await repo.clientsList(base.copyWith(
          limit: remaining < _exportChunk ? remaining : _exportChunk,
          offset: offset,
        ));
        if (headers.isEmpty) headers = chunk.headers;
        collected.addAll(chunk.rows);
        if (chunk.rows.isEmpty) break;
      }

      final cols = headers.isNotEmpty
          ? headers
          : [for (final c in _allColumns) c.$1];
      final csv = misCsvDocument([
        cols,
        for (final r in collected) [for (final c in cols) r.raw[c]],
      ]);

      if (!mounted) return;
      final name =
          'clients-${misSlug('${widget.bucketLabel}-${widget.scopeLabel}')}.csv';
      final saved = await misSaveCsv(context, name, csv);

      // Never let a cap pass silently — the file would look complete but isn't.
      if (saved && total > _exportMax && mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Exported the first ${misNum(_exportMax)} of ${misNum(total)} rows. '
            'Narrow the search or drill further for the rest.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
