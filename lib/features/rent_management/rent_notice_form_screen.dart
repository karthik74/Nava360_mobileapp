import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'rent_list_screen.dart' show rentBranchesProvider;
import 'rent_repository.dart';

/// Issue a rent notice against a branch. Pops `true` on save so the list
/// refreshes. Mirrors `AdminRentPage.tsx`'s `NoticesTab` "Issue notice"
/// modal, and Purchase Orders' form-screen structure.
class RentNoticeFormScreen extends ConsumerStatefulWidget {
  const RentNoticeFormScreen({super.key});

  @override
  ConsumerState<RentNoticeFormScreen> createState() => _RentNoticeFormScreenState();
}

class _RentNoticeFormScreenState extends ConsumerState<RentNoticeFormScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  int? _branchId;
  DateTime _issuedOn = DateTime.now();
  bool _holdRent = false;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickIssuedOn() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _issuedOn,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _issuedOn = d);
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
      await ref.read(rentRepositoryProvider).issueNotice(
            branchId: _branchId!,
            subject: _subject.text.trim(),
            body: _body.text.trim().isEmpty ? null : _body.text.trim(),
            issuedOn: _issuedOn,
            holdRent: _holdRent,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice issued')));
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
    final branchesAsync = ref.watch(rentBranchesProvider);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Issue Notice'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: branchesAsync.when(
          data: (branches) {
            _branchId ??= branches.isNotEmpty ? branches.first.id : null;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _label('Branch *'),
                DropdownButtonFormField<int>(
                  value: _branchId,
                  items: [
                    for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.branchName)),
                  ],
                  onChanged: (v) => setState(() => _branchId = v),
                ),
                const SizedBox(height: 10),
                _label('Subject *'),
                TextField(controller: _subject, textCapitalization: TextCapitalization.sentences),
                const SizedBox(height: 10),
                _label('Body'),
                TextField(controller: _body, minLines: 3, maxLines: 6),
                const SizedBox(height: 10),
                _label('Issued on *'),
                InkWell(
                  onTap: _pickIssuedOn,
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
                        Text(df.format(_issuedOn),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _holdRent,
                  onChanged: (v) => setState(() => _holdRent = v),
                  title: const Text("Place this branch's current month rent on hold",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AppErrorPanel(message: _error!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _saving || branches.isEmpty ? null : _save,
                    child: Text(_saving ? 'Issuing…' : 'Issue notice'),
                  ),
                ),
                if (branches.isEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('No rent branches configured yet — add one in the Branches tab first.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
                const SizedBox(height: 24),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: AppErrorPanel(message: '$e')),
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
