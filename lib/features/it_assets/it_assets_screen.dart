import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/report_download.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'it_asset_models.dart';
import 'it_asset_repository.dart';

final myItAssetEntriesProvider = FutureProvider.autoDispose<List<ItAssetFormEntry>>((ref) {
  return ref.watch(itAssetRepositoryProvider).myEntries();
});

/// Pending entry whose due date has passed (presentation only).
bool _isOverdue(ItAssetFormEntry e) {
  if (e.isSubmitted || e.dueDate == null) return false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(e.dueDate!.year, e.dueDate!.month, e.dueDate!.day);
  return due.isBefore(today);
}

/// Admin Tools · IT Assets — "My Forms": the periodic asset-count forms
/// assigned to the signed-in employee. Fill-only; building/assigning the
/// form itself is done by an admin on the web.
class ItAssetsScreen extends ConsumerStatefulWidget {
  const ItAssetsScreen({super.key});

  @override
  ConsumerState<ItAssetsScreen> createState() => _ItAssetsScreenState();
}

class _ItAssetsScreenState extends ConsumerState<ItAssetsScreen> {
  /// 0 = all, 1 = pending, 2 = submitted.
  int _f = 0;

  String _subtitle(ItAssetFormEntry e) {
    if (e.isSubmitted) {
      final at = e.submittedAt;
      return 'Submitted${at != null ? ' ${DateFormat('d MMM yyyy, HH:mm').format(at)}' : ''}';
    }
    final due = e.dueDate;
    return due != null ? 'Due ${DateFormat('d MMM yyyy').format(due)}' : 'Not submitted yet';
  }

  Future<void> _open(ItAssetFormEntry e) async {
    final saved = await context.push<bool>('/admin/it-assets/${e.id}/fill', extra: e);
    if (saved == true) ref.invalidate(myItAssetEntriesProvider);
  }

  Widget _row(ItAssetFormEntry e) {
    final overdue = _isOverdue(e);
    return ProListRow(
      leading: ProIconWell(
        icon: e.isSubmitted ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
        color: e.isSubmitted
            ? AppColors.success
            : overdue
                ? AppColors.danger
                : AppColors.warning,
      ),
      title: e.templateName,
      subtitle: e.period,
      meta: _subtitle(e),
      pill: e.isSubmitted
          ? ProPill.ok('Submitted')
          : overdue
              ? ProPill.bad('Overdue')
              : ProPill.warn('Pending'),
      onTap: () => _open(e),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(myItAssetEntriesProvider);
    final entries = entriesAsync.valueOrNull;
    final all = entries ?? const <ItAssetFormEntry>[];
    final pending = all.where((e) => !e.isSubmitted).toList();
    final submitted = all.where((e) => e.isSubmitted).toList();
    final overdue = pending.where(_isOverdue).length;

    final children = <Widget>[
      const ProNote(
        'Your admin builds and assigns these forms on the web. You fill and submit them here.',
        tone: ProNoteTone.info,
      ),
      ...entriesAsync.when<List<Widget>>(
        loading: () => const [AppLoadingBlock(height: 140)],
        error: (err, _) => [
          AppErrorPanel(
            message: 'Failed to load: $err',
            onRetry: () => ref.invalidate(myItAssetEntriesProvider),
          ),
        ],
        data: (entries) {
          if (entries.isEmpty) {
            return const [
              ProEmpty(
                icon: Icons.laptop_mac_rounded,
                title: 'Nothing here',
                message: 'No IT Asset forms assigned to you yet.',
              ),
            ];
          }
          final showPending = _f != 2;
          final showSubmitted = _f != 1;
          return [
            ProChipBar(
              labels: const ['All', 'Pending', 'Submitted'],
              counts: [entries.length, pending.length, submitted.length],
              selected: _f,
              onSelected: (i) => setState(() => _f = i),
              bleed: 0,
            ),
            if (showPending && pending.isNotEmpty) ...[
              ProSectionHeader(title: 'To fill · ${pending.length}', small: true),
              ProListGroup(children: [for (final e in pending) _row(e)]),
            ],
            if (showSubmitted && submitted.isNotEmpty) ...[
              ProSectionHeader(title: 'Submitted · ${submitted.length}', small: true),
              ProListGroup(children: [for (final e in submitted) _row(e)]),
            ],
            if ((_f == 1 && pending.isEmpty) || (_f == 2 && submitted.isEmpty))
              ProEmpty(
                icon: Icons.laptop_mac_rounded,
                title: 'Nothing here',
                message: _f == 1 ? 'No forms waiting to be filled.' : 'No forms submitted yet.',
              ),
          ];
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('IT assets'), actions: [
        if (ref.watch(authUserProvider)?.hasPermission('ADMIN_IT_ASSET_REPORT_VIEW') ?? false)
          IconButton(
            tooltip: 'Download report',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _ReportSheet(parentContext: context),
            ),
          ),
      ]),
      body: ProPage(
        onRefresh: () async => ref.invalidate(myItAssetEntriesProvider),
        hero: ProHero(
          title: 'My forms',
          subtitle: entries == null
              ? 'Admin tools · IT asset counts'
              : 'Admin tools · ${all.length} ${all.length == 1 ? 'form' : 'forms'} assigned',
          children: [
            ProHeroStats(stats: [
              ProStat(
                label: 'To fill',
                value: entries == null ? '—' : '${pending.length}',
                sub: entries == null ? null : (pending.isEmpty ? 'All done' : 'Pending'),
                dot: const Color(0xFFF2B347),
                selected: _f == 1,
                onTap: entries == null ? null : () => setState(() => _f = _f == 1 ? 0 : 1),
              ),
              ProStat(
                label: 'Submitted',
                value: entries == null ? '—' : '${submitted.length}',
                sub: entries == null ? null : 'of ${all.length}',
                dot: AppColors.live,
                selected: _f == 2,
                onTap: entries == null ? null : () => setState(() => _f = _f == 2 ? 0 : 2),
              ),
              ProStat(
                label: 'Overdue',
                value: entries == null ? '—' : '$overdue',
                sub: entries == null ? null : (overdue == 0 ? 'On track' : 'Past due date'),
                dot: const Color(0xFFE5484D),
              ),
            ]),
          ],
        ),
        children: children,
      ),
    );
  }
}

/// Report download (mirrors the web Report tab): pick a form, a day or a date range.
class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.parentContext});
  final BuildContext parentContext;
  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  static final _iso = DateFormat('yyyy-MM-dd');
  List<({int id, String name})>? _templates;
  String? _error;
  int? _templateId;
  bool _range = false;
  DateTime _date = DateTime.now();
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    ref.read(itAssetRepositoryProvider).templates().then((t) {
      if (!mounted) return;
      setState(() {
        _templates = t;
        if (t.isNotEmpty) _templateId = t.first.id;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 366)),
      );

  Widget _dateTile(String label, DateTime v, ValueChanged<DateTime> set) => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: const BorderSide(color: Color(0xFFDBE3E5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final p = await _pick(v);
            if (p != null) setState(() => set(p));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 17, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppText.caption),
                      Text(
                        DateFormat('d MMM yyyy').format(v),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
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

  String get _fileName => _range
      ? 'it-assets-report-${_iso.format(_from)}-to-${_iso.format(_to)}.xlsx'
      : 'it-assets-report-${_iso.format(_date)}.xlsx';

  void _download() {
    final id = _templateId;
    if (id == null) return;
    if (_range && _to.isBefore(_from)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date is before start date')));
      return;
    }
    final repo = ref.read(itAssetRepositoryProvider);
    final name = _fileName;
    final messengerCtx = widget.parentContext;
    Navigator.of(context).pop();
    downloadExcelReport(
      messengerCtx,
      () => _range
          ? repo.exportReport(id, from: _iso.format(_from), to: _iso.format(_to))
          : repo.exportReport(id, date: _iso.format(_date)),
      name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _templates;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC6D3D6),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'IT assets report',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.35,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Material(
                      color: const Color(0xFFEEF3F4),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.close_rounded, size: 18, color: AppColors.ink),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  ProNote('Failed to load forms: $_error', tone: ProNoteTone.bad)
                else if (t == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (t.isEmpty)
                  const ProNote('No forms available.')
                else ...[
                  ProField(
                    label: 'Form',
                    child: DropdownButtonFormField<int>(
                      value: _templateId,
                      isExpanded: true,
                      items: [for (final x in t) DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _templateId = v),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ProField(
                    label: 'Period',
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Day')),
                          ButtonSegment(value: true, label: Text('Date range')),
                        ],
                        selected: {_range},
                        onSelectionChanged: (s) => setState(() => _range = s.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_range)
                    _dateTile('Date', _date, (v) => _date = v)
                  else
                    Row(
                      children: [
                        Expanded(child: _dateTile('From', _from, (v) => _from = v)),
                        const SizedBox(width: 10),
                        Expanded(child: _dateTile('To', _to, (v) => _to = v)),
                      ],
                    ),
                  const SizedBox(height: 12),
                  ProNote(_fileName, tone: ProNoteTone.info, icon: Icons.table_chart_outlined),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _templateId == null ? null : _download,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download report'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
