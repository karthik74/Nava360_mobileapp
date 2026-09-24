import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mail_list_screen.dart' show mailBranchesProvider;
import 'mail_models.dart';
import 'mail_repository.dart';

final _complaintFormDefaultsProvider = FutureProvider.autoDispose<MailComplaintFormDefaults>((ref) {
  return ref.watch(mailRepositoryProvider).complaintFormDefaults();
});

/// Raise a new complaint. Pops `true` on save so the Complaints tab refreshes. The raiser's name, branch, phone and
/// department are filled in from their own record and the department list comes from the HR departments — nothing
/// to retype. Status changes and history live on [MailComplaintScreen] once raised.
class MailComplaintFormScreen extends ConsumerStatefulWidget {
  const MailComplaintFormScreen({super.key});

  @override
  ConsumerState<MailComplaintFormScreen> createState() => _MailComplaintFormScreenState();
}

class _MailComplaintFormScreenState extends ConsumerState<MailComplaintFormScreen> {
  final _subject = TextEditingController();
  final _content = TextEditingController();
  final _phone = TextEditingController();
  int? _branchId; // only used when the raiser has no branch of their own
  String? _department;
  bool _departmentSeeded = false;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _content.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save(MailComplaintFormDefaults defaults) async {
    setState(() => _error = null);
    if (defaults.branchId == null && _branchId == null) {
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
            branchId: defaults.branchId == null ? _branchId : null,
            department: _department,
            subject: _subject.text.trim(),
            content: _content.text.trim().isEmpty ? null : _content.text.trim(),
            phone: defaults.phone == null && _phone.text.trim().isNotEmpty ? _phone.text.trim() : null,
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
    final defaultsAsync = ref.watch(_complaintFormDefaultsProvider);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Raise Complaint'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: defaultsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: AppErrorPanel(message: '$e', onRetry: () => ref.invalidate(_complaintFormDefaultsProvider)),
          ),
          data: (d) {
            if (!_departmentSeeded) {
              _department = d.department;
              _departmentSeeded = true;
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Raising as ${d.raisedByName ?? 'you'}'
                        '${d.employeeCode != null ? ' (${d.employeeCode})' : ''}'
                        '${d.phone != null ? ' · ${d.phone}' : ''}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [d.branchLabel, d.areaName, d.divisionName, d.regionName, d.stateName]
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(' › ')
                                .isEmpty
                            ? 'No branch on your profile'
                            : [d.branchLabel, d.areaName, d.divisionName, d.regionName, d.stateName]
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(' › '),
                        style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                if (d.branchId == null) ...[
                  const SizedBox(height: 10),
                  _label('Branch *'),
                  ref.watch(mailBranchesProvider).when(
                        data: (branches) => DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: _branchId,
                          items: [
                            for (final b in branches)
                              DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _branchId = v),
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                      ),
                ],
                const SizedBox(height: 10),
                _label('Department'),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: d.departments.contains(_department) ? _department : null,
                  items: [
                    DropdownMenuItem(
                        value: null,
                        child: Text(d.departments.isEmpty ? 'No departments set up' : 'Select department')),
                    for (final name in d.departments)
                      DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _department = v),
                ),
                const SizedBox(height: 10),
                _label('Subject *'),
                TextField(controller: _subject, textCapitalization: TextCapitalization.sentences),
                const SizedBox(height: 10),
                _label('Details'),
                TextField(controller: _content, minLines: 3, maxLines: 6),
                if (d.phone == null) ...[
                  const SizedBox(height: 10),
                  _label('Phone'),
                  TextField(controller: _phone, keyboardType: TextInputType.phone),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AppErrorPanel(message: _error!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(d),
                    child: Text(_saving ? 'Submitting…' : 'Raise complaint'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
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
