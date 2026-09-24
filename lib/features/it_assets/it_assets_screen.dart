import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/report_download.dart';
import '../auth/auth_controller.dart';
import 'it_asset_models.dart';
import 'it_asset_repository.dart';

final myItAssetEntriesProvider = FutureProvider.autoDispose<List<ItAssetFormEntry>>((ref) {
  return ref.watch(itAssetRepositoryProvider).myEntries();
});

/// Admin Tools · IT Assets — "My Forms": the periodic asset-count forms
/// assigned to the signed-in employee. Fill-only; building/assigning the
/// form itself is done by an admin on the web.
class ItAssetsScreen extends ConsumerWidget {
  const ItAssetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(myItAssetEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('IT Assets'), actions: [
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
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myItAssetEntriesProvider),
        child: entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Failed to load: $err')),
            ],
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No IT Asset forms assigned to you yet.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final e = entries[index];
                return Card(
                  child: ListTile(
                    title: Text('${e.templateName} — ${e.period}'),
                    subtitle: Text(_subtitle(e)),
                    trailing: Icon(
                      e.isSubmitted ? Icons.check_circle : Icons.pending_actions,
                      color: e.isSubmitted ? Colors.green : Colors.orange,
                    ),
                    onTap: () async {
                      final saved = await context.push<bool>('/admin/it-assets/${e.id}/fill', extra: e);
                      if (saved == true) ref.invalidate(myItAssetEntriesProvider);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _subtitle(ItAssetFormEntry e) {
    if (e.isSubmitted) {
      final at = e.submittedAt;
      return 'Submitted${at != null ? ' ${DateFormat('d MMM yyyy, HH:mm').format(at)}' : ''}';
    }
    final due = e.dueDate;
    return due != null ? 'Due ${DateFormat('d MMM yyyy').format(due)}' : 'Not submitted yet';
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

  Widget _dateTile(String label, DateTime v, ValueChanged<DateTime> set) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Text(DateFormat('d MMM yyyy').format(v)),
        onTap: () async {
          final p = await _pick(v);
          if (p != null) setState(() => set(p));
        },
      );

  void _download() {
    final id = _templateId;
    if (id == null) return;
    if (_range && _to.isBefore(_from)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date is before start date')));
      return;
    }
    final repo = ref.read(itAssetRepositoryProvider);
    final name = _range
        ? 'it-assets-report-${_iso.format(_from)}-to-${_iso.format(_to)}.xlsx'
        : 'it-assets-report-${_iso.format(_date)}.xlsx';
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
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('IT Assets report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Failed to load forms: $_error')
          else if (t == null)
            const Center(child: CircularProgressIndicator())
          else if (t.isEmpty)
            const Text('No forms available.')
          else ...[
            DropdownButtonFormField<int>(
              value: _templateId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Form'),
              items: [for (final x in t) DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _templateId = v),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Day')),
                ButtonSegment(value: true, label: Text('Date range')),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
            if (!_range)
              _dateTile('Date', _date, (v) => _date = v)
            else ...[
              _dateTile('From', _from, (v) => _from = v),
              _dateTile('To', _to, (v) => _to = v),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _templateId == null ? null : _download,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download report'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
