import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mail_repository.dart';

/// Create or edit a complaint department. Pass an existing [deptId] to
/// edit; omit it to create a new one. Pops `true` on save/delete so the
/// Departments tab refreshes. Mirrors `AdminMailPage.tsx`'s
/// `DepartmentsTab` create/edit modal.
class MailComplaintDepartmentFormScreen extends ConsumerStatefulWidget {
  const MailComplaintDepartmentFormScreen({super.key, this.deptId});
  final int? deptId;

  @override
  ConsumerState<MailComplaintDepartmentFormScreen> createState() =>
      _MailComplaintDepartmentFormScreenState();
}

class _MailComplaintDepartmentFormScreenState
    extends ConsumerState<MailComplaintDepartmentFormScreen> {
  final _deptKey = TextEditingController();
  final _name = TextEditingController();
  final _deptCode = TextEditingController();
  bool _active = true;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.deptId != null;

  @override
  void initState() {
    super.initState();
    if (widget.deptId != null) _load(widget.deptId!);
  }

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(mailRepositoryProvider).listComplaintDepartments();
      final d = rows.firstWhere((e) => e.id == id, orElse: () => throw Exception('Department not found'));
      if (!mounted) return;
      setState(() {
        _deptKey.text = d.deptKey;
        _name.text = d.name;
        _deptCode.text = d.deptCode ?? '';
        _active = d.active;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _deptKey.dispose();
    _name.dispose();
    _deptCode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_deptKey.text.trim().isEmpty) {
      setState(() => _error = 'Key is required.');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(mailRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateComplaintDepartment(
          widget.deptId!,
          deptKey: _deptKey.text.trim(),
          name: _name.text.trim(),
          deptCode: _emptyToNull(_deptCode.text),
          active: _active,
        );
      } else {
        await repo.createComplaintDepartment(
          deptKey: _deptKey.text.trim(),
          name: _name.text.trim(),
          deptCode: _emptyToNull(_deptCode.text),
          active: _active,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_isEdit ? 'Department saved' : 'Department created')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.deptId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete department?'),
        content: Text('Delete department "${_name.text}"?'),
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
      await ref.read(mailRepositoryProvider).deleteComplaintDepartment(widget.deptId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Department' : 'New Department'),
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
                  _label('Key *'),
                  TextField(controller: _deptKey, decoration: const InputDecoration(hintText: 'e.g. it_support')),
                  const SizedBox(height: 10),
                  _label('Name *'),
                  TextField(controller: _name, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),
                  _label('4-digit code'),
                  TextField(controller: _deptCode, maxLength: 4, keyboardType: TextInputType.number),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    title: const Text('Active', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AppErrorPanel(message: _error!),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create')),
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
