import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mail_list_screen.dart' show mailBranchesProvider, mailRecordsProvider;
import 'mail_models.dart';
import 'mail_repository.dart';

/// Create or edit a mail-register entry. Pass an existing [recordId] to
/// edit; omit it to create a new one. Pops `true` on save/delete so the
/// list refreshes. Mirrors `AdminMailPage.tsx`'s `RecordsTab` create/edit
/// modal, and Purchase Orders/Rent Management's form-screen structure.
class MailRecordFormScreen extends ConsumerStatefulWidget {
  const MailRecordFormScreen({super.key, this.recordId});
  final int? recordId;

  @override
  ConsumerState<MailRecordFormScreen> createState() => _MailRecordFormScreenState();
}

class _MailRecordFormScreenState extends ConsumerState<MailRecordFormScreen> {
  late final TextEditingController _department;
  late final TextEditingController _documents;
  late final TextEditingController _docketNumber;
  late final TextEditingController _courierStatus;
  late final TextEditingController _particular;
  late final TextEditingController _details;
  late final TextEditingController _employeeId;

  String _mailType = MailType.inward;
  DateTime _date = DateTime.now();
  int? _branchId;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.recordId != null;

  @override
  void initState() {
    super.initState();
    _department = TextEditingController();
    _documents = TextEditingController();
    _docketNumber = TextEditingController();
    _courierStatus = TextEditingController();
    _particular = TextEditingController();
    _details = TextEditingController();
    _employeeId = TextEditingController();
    if (widget.recordId != null) _load(widget.recordId!);
  }

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    try {
      // There is no `GET /records/{id}` endpoint — the web lists and finds
      // within the page, same source of truth this screen uses.
      final rows = await ref.read(mailRepositoryProvider).listRecords(size: 200);
      final r = rows.firstWhere((e) => e.id == id, orElse: () => throw Exception('Record not found'));
      if (!mounted) return;
      setState(() {
        _mailType = r.mailType;
        _date = r.date ?? DateTime.now();
        _branchId = r.branchId;
        _employeeId.text = r.employeeId?.toString() ?? '';
        _department.text = r.department ?? '';
        _documents.text = r.documents ?? '';
        _docketNumber.text = r.docketNumber ?? '';
        _courierStatus.text = r.courierStatus ?? '';
        _particular.text = r.particular ?? '';
        _details.text = r.details ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _department.dispose();
    _documents.dispose();
    _docketNumber.dispose();
    _courierStatus.dispose();
    _particular.dispose();
    _details.dispose();
    _employeeId.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_branchId == null) {
      setState(() => _error = 'Select a branch.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(mailRepositoryProvider);
    final body = repo.recordBody(
      mailType: _mailType,
      date: _date,
      branchId: _branchId!,
      employeeId: int.tryParse(_employeeId.text.trim()),
      department: _emptyToNull(_department.text),
      documents: _emptyToNull(_documents.text),
      docketNumber: _emptyToNull(_docketNumber.text),
      courierStatus: _emptyToNull(_courierStatus.text),
      particular: _emptyToNull(_particular.text),
      details: _emptyToNull(_details.text),
    );
    try {
      if (_isEdit) {
        await repo.updateRecord(widget.recordId!, body);
      } else {
        await repo.createRecord(body);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? 'Mail record saved' : 'Mail record created')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.recordId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete mail record?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(mailRepositoryProvider).deleteRecord(widget.recordId!);
      ref.invalidate(mailRecordsProvider(null));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final branchesAsync = ref.watch(mailBranchesProvider);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Mail Record' : 'New Mail Record'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          actions: [
            if (_isEdit)
              IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                tooltip: 'Delete',
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _label('Type *'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: MailType.inward, label: Text('Inward')),
                        ButtonSegment(value: MailType.outward, label: Text('Outward')),
                      ],
                      selected: {_mailType},
                      onSelectionChanged: (s) => setState(() => _mailType = s.first),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _label('Date *'),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(df.format(_date), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _label('Branch *'),
                  branchesAsync.when(
                    data: (branches) => DropdownButtonFormField<int>(
                      value: branches.any((b) => b.id == _branchId) ? _branchId : null,
                      items: [
                        for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.label)),
                      ],
                      onChanged: (v) => setState(() => _branchId = v),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                  const SizedBox(height: 10),
                  _label('Employee ID'),
                  TextField(
                    controller: _employeeId,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Optional'),
                  ),
                  const SizedBox(height: 10),
                  _label('Department'),
                  TextField(controller: _department),
                  const SizedBox(height: 10),
                  _label('Docket number'),
                  TextField(controller: _docketNumber),
                  const SizedBox(height: 10),
                  _label('Documents'),
                  TextField(controller: _documents),
                  const SizedBox(height: 10),
                  _label('Courier status'),
                  TextField(controller: _courierStatus),
                  const SizedBox(height: 10),
                  _label('Particular'),
                  TextField(controller: _particular),
                  const SizedBox(height: 10),
                  _label('Details'),
                  TextField(controller: _details, minLines: 2, maxLines: 5),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AppErrorPanel(message: _error!),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create entry')),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );
}
