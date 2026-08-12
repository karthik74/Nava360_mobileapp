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

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Customer details'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exporting ? null : () => _export(async.valueOrNull),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => ref.invalidate(misClientsProvider(q)),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
          children: [
            _header(async.valueOrNull),
            const SizedBox(height: 12),
            _searchBar(),
            const SizedBox(height: 10),
            _sortBar(),
            const SizedBox(height: 12),
            async.when(
              loading: () => const AppLoadingBlock(height: 220),
              error: (e, _) => _errorOrNotice(e),
              data: (res) => _results(res),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ClientsListResponse? res) {
    final bits = <String>[
      widget.scopeLabel,
      if (res != null && res.asOn.label.isNotEmpty) res.asOn.label,
      if (widget.bucketAccounts != null && widget.bucketAccounts! > 0)
        '${misNum(widget.bucketAccounts)} accounts in this bucket',
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: MisPalette.risk(widget.bucketKey),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Client details — ${widget.bucketLabel}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            bits.join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applySearch(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              hintText: 'Client ID, name, mobile, account, group or officer…',
              hintStyle: const TextStyle(fontSize: 12.5),
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _clearSearch,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _applySearch, child: const Text('Search')),
      ],
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
      return GlassCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 20, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                notice,
                style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ),
          ],
        ),
      );
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
      return MisInlineEmpty(
        _query.isNotEmpty
            ? 'No client matches “$_query” in this bucket.'
            : 'No clients in this bucket.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pager(total, totalPages, from, to),
        const SizedBox(height: 12),
        for (final r in res.rows) ...[
          _clientCard(r),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        _pager(total, totalPages, from, to),
      ],
    );
  }

  Widget _pager(int total, int totalPages, int from, int to) {
    final first = _pageIndex == 0;
    final last = totalPages == 0 || _pageIndex >= totalPages - 1;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed:
                  first ? null : () => setState(() => _pageIndex -= 1),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous page',
            ),
            IconButton(
              onPressed: last ? null : () => setState(() => _pageIndex += 1),
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next page',
            ),
            Expanded(
              child: Text(
                total > 0
                    ? '${misNum(from)}–${misNum(to)} of ${misNum(total)}'
                        ' · page ${_pageIndex + 1} of $totalPages'
                    : 'No rows',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ),
            const Text('Rows',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            const SizedBox(width: 6),
            DropdownButton<int>(
              value: _size,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
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
        ),
      ],
    );
  }

  Widget _clientCard(ClientRow r) {
    final bucket = r.bucket ?? widget.bucketKey;
    return _MisTapCard(
      onTap: () => _openDetail(r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: MisPalette.risk(bucket.toLowerCase()),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.clientName ?? r.clientId ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (r.mobile != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Call ${r.mobile}',
                  onPressed: () => _call(r.mobile!),
                  icon: const Icon(Icons.call_rounded,
                      size: 18, color: AppColors.success),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (r.clientId != null) r.clientId,
              if (r.accountId != null) 'A/c ${r.accountId}',
              if (r.productName != null) r.productName,
            ].whereType<String>().join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          if (r.branchName != null || r.officerName != null) ...[
            const SizedBox(height: 1),
            Text(
              [r.branchName, r.officerName].whereType<String>().join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metric('Principal O/S', r.principalOs, true)),
              Expanded(child: _metric('Total Arrear', r.totalArrear, true)),
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
        ],
      ),
    );
  }

  Widget _metric(String label, double? value, bool money, {Color? tone}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        const SizedBox(height: 1),
        Text(
          value == null ? '—' : (money ? misRupees(value) : misNum(value)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (ctx, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                r.clientName ?? r.clientId ?? 'Client',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              for (final c in _allColumns)
                if (r.raw.containsKey(c.$1))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            c.$2,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _display(r, c.$1),
                            style: const TextStyle(
                              fontSize: 13.5,
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

/// A tappable card matching the MIS card styling.
class _MisTapCard extends StatelessWidget {
  const _MisTapCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = GlassCard(
      padding: const EdgeInsets.all(13),
      shadow: AppShadows.soft,
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
