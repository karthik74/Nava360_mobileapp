import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mail_list_screen.dart' show mailBranchesProvider, mailComplaintDeptsProvider;
import 'mail_repository.dart';

/// Raise a new complaint. Pops `true` on save so the Complaints tab
/// refreshes. Mirrors `AdminMailPage.tsx`'s `ComplaintsTab` "Raise
/// complaint" modal. Complaints are create-only from here — status changes
/// and history live on [MailComplaintScreen] once raised.
class MailComplaintFormScreen extends ConsumerStatefulWidget {
  const MailComplaintFormScreen({super.key});

  @override
  ConsumerState<MailComplaintFormScreen> createState() => _MailComplaintFormScreenState();
}

class _MailComplaintFormScreenState extends ConsumerState<MailComplaintFormScreen> {
  final _subject = TextEditingController();
  final _content = TextEditingController();
  final _phone = TextEditingController();
  int? _branchId;
  int? _deptId;
  DateTime _date = DateTime.now();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _content.dispose();
    _phone.dispose();
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
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'Subject is required.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(mailRepositoryProvider).raiseComplaint(
            branchId: _branchId!,
            date: _date,
            deptId: _deptId,
            subject: _subject.text.trim(),
            content: _content.text.trim().isEmpty ? null : _content.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Complaint raised')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final branchesAsync = ref.watch(mailBranchesProvider);
    final deptsAsync = ref.watch(mailComplaintDeptsProvider(true));
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Raise Complaint'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _label('Branch *'),
            branchesAsync.when(
              data: (branches) => DropdownButtonFormField<int>(
                value: _branchId,
                items: [for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.label))],
                onChanged: (v) => setState(() => _branchId = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
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
            _label('Department'),
            deptsAsync.when(
              data: (depts) => DropdownButtonFormField<int?>(
                value: depts.any((d) => d.id == _deptId) ? _deptId : null,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Select department')),
                  for (final d in depts) DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() => _deptId = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
            const SizedBox(height: 10),
            _label('Subject *'),
            TextField(controller: _subject, textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 10),
            _label('Details'),
            TextField(controller: _content, minLines: 3, maxLines: 6),
            const SizedBox(height: 10),
            _label('Phone'),
            TextField(controller: _phone, keyboardType: TextInputType.phone),
            if (_error != null) ...[
              const SizedBox(height: 14),
              AppErrorPanel(message: _error!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Submitting…' : 'Raise complaint'),
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
