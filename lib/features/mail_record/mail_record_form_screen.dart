import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
import 'mail_list_screen.dart' show mailBranchesProvider, mailMyBranchIdProvider, mailNewRecordTypeProvider, mailRecordsProvider;
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
  late final TextEditingController _otherParty;
  late final TextEditingController _amount;

  String _mailType = MailType.inward;
  DateTime _date = DateTime.now();
  int? _branchId;
  /// false = a listed branch; true = "Others" (vendor, head office, customer…) with a free-text name.
  bool _isOther = false;

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
    _otherParty = TextEditingController();
    _amount = TextEditingController();
    if (widget.recordId != null) {
      _load(widget.recordId!);
    } else {
      // Opened from the Outward / Inward tab: start on that type.
      final t = ref.read(mailNewRecordTypeProvider);
      if (t != null) {
        _mailType = t;
        Future.microtask(() => ref.read(mailNewRecordTypeProvider.notifier).state = null);
      }
      // A new entry starts on the signed-in user's own branch (still changeable).
      ref.read(mailMyBranchIdProvider.future).then((id) {
        if (mounted && id != null) setState(() => _branchId ??= id);
      });
    }
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
        _isOther = r.branchId == null;
        _otherParty.text = r.otherParty ?? '';
        _amount.text = r.amount == null ? '' : r.amount!.toString();
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
    _otherParty.dispose();
    _amount.dispose();
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
    final isOutward = _mailType == MailType.outward;
    if (!_isOther && _branchId == null) {
      setState(() => _error = 'Select a branch, or choose Others.');
      return;
    }
    if (_isOther && _otherParty.text.trim().isEmpty) {
      setState(() => _error = 'Enter who the mail is ${isOutward ? 'to' : 'from'}.');
      return;
    }
    final amountText = _amount.text.trim();
    final amount = amountText.isEmpty ? null : double.tryParse(amountText);
    if (isOutward && amountText.isNotEmpty && (amount == null || amount < 0)) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(mailRepositoryProvider);
    final body = repo.recordBody(
      mailType: _mailType,
      date: _date,
      branchId: _isOther ? null : _branchId,
      otherParty: _isOther ? _otherParty.text.trim() : null,
      amount: isOutward ? amount : null,
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
      ref.invalidate(mailRecordsProvider);
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
    final isOutward = _mailType == MailType.outward;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: _isEdit ? 'Edit mail record' : 'New mail record',
        subtitle: 'Mail record · ${isOutward ? 'outward' : 'inward'} register',
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              tooltip: 'Delete',
            ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: _loading
          ? null
          : ProBottomBar(
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create entry')),
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Entry'),
                      const SizedBox(height: 12),
                      ProField(
                        label: 'Type',
                        required: true,
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: MailType.inward,
                                  icon: Icon(Icons.south_west_rounded, size: 17),
                                  label: Text('Inward')),
                              ButtonSegment(
                                  value: MailType.outward,
                                  icon: Icon(Icons.north_east_rounded, size: 17),
                                  label: Text('Outward')),
                            ],
                            selected: {_mailType},
                            onSelectionChanged: (s) => setState(() => _mailType = s.first),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Date',
                        required: true,
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.calendar_today_rounded, size: 17, color: AppColors.primary),
                              suffixIcon: const Icon(Icons.expand_more_rounded),
                            ),
                            child: Text(df.format(_date),
                                style: const TextStyle(fontSize: 15, color: AppColors.ink)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: isOutward ? 'To' : 'From',
                        required: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(value: false, label: Text('Branch')),
                                ButtonSegment(value: true, label: Text('Others')),
                              ],
                              selected: {_isOther},
                              onSelectionChanged: (s) => setState(() => _isOther = s.first),
                            ),
                            const SizedBox(height: 10),
                            if (_isOther)
                              TextField(
                                controller: _otherParty,
                                maxLength: 200,
                                decoration: InputDecoration(
                                  hintText: isOutward
                                      ? 'Who is this mail going to? (vendor, head office, customer…)'
                                      : 'Who is this mail from? (vendor, head office, customer…)',
                                ),
                              )
                            else
                              branchesAsync.when(
                                data: (branches) => DropdownButtonFormField<int>(
                                  isExpanded: true,
                                  value: branches.any((b) => b.id == _branchId) ? _branchId : null,
                                  hint: const Text('Select a branch'),
                                  items: [
                                    for (final b in branches)
                                      DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) => setState(() => _branchId = v),
                                ),
                                loading: () => const LinearProgressIndicator(),
                                error: (e, _) =>
                                    Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Details'),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ProField(
                              label: 'Employee ID',
                              child: TextField(
                                controller: _employeeId,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: 'Optional'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ProField(label: 'Department', child: TextField(controller: _department)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ProField(label: 'Docket number', child: TextField(controller: _docketNumber)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ProField(label: 'Courier status', child: TextField(controller: _courierStatus)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ProField(label: 'Documents', child: TextField(controller: _documents)),
                      if (isOutward) ...[
                        const SizedBox(height: 14),
                        ProField(
                          label: 'Amount (₹)',
                          child: TextField(
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: AppText.number.copyWith(fontSize: 15, color: AppColors.ink),
                            decoration: const InputDecoration(hintText: 'Optional', prefixText: '₹ '),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ProField(label: 'Particular', child: TextField(controller: _particular)),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Details',
                        child: TextField(controller: _details, minLines: 2, maxLines: 5),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  ProNote(_error!, tone: ProNoteTone.bad),
                ],
              ],
            ),
    );
  }
}
