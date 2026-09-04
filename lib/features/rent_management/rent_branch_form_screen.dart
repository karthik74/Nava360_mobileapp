import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'rent_repository.dart';

/// Create or edit a rent branch (landlord record). Pass an existing
/// [branchId] to edit; omit it to create a new branch. Pops `true` on
/// save/delete so the list refreshes. Mirrors `AdminRentPage.tsx`'s
/// `BranchesTab` create/edit modal, and Purchase Orders' form-screen
/// structure (header fields + validation + save button).
class RentBranchFormScreen extends ConsumerStatefulWidget {
  const RentBranchFormScreen({super.key, this.branchId});
  final int? branchId;

  @override
  ConsumerState<RentBranchFormScreen> createState() => _RentBranchFormScreenState();
}

class _RentBranchFormScreenState extends ConsumerState<RentBranchFormScreen> {
  late final TextEditingController _branchName;
  late final TextEditingController _branchCode;
  late final TextEditingController _ownerName;
  late final TextEditingController _address;
  late final TextEditingController _rent;
  late final TextEditingController _rentAdvance;

  DateTime? _startDate;
  bool? _gstApplicable;
  bool _active = true;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.branchId != null;

  @override
  void initState() {
    super.initState();
    _branchName = TextEditingController();
    _branchCode = TextEditingController();
    _ownerName = TextEditingController();
    _address = TextEditingController();
    _rent = TextEditingController();
    _rentAdvance = TextEditingController();
    if (widget.branchId != null) _load(widget.branchId!);
  }

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    try {
      final branches = await ref.read(rentRepositoryProvider).listBranches();
      final b = branches.firstWhere((e) => e.id == id, orElse: () => throw Exception('Branch not found'));
      if (!mounted) return;
      setState(() {
        _branchName.text = b.branchName;
        _branchCode.text = b.branchCode ?? '';
        _ownerName.text = b.ownerName ?? '';
        _address.text = b.address ?? '';
        _rent.text = b.rent == null ? '' : b.rent!.toStringAsFixed(2);
        _rentAdvance.text = b.rentAdvance == null ? '' : b.rentAdvance!.toStringAsFixed(2);
        _startDate = b.startDate;
        _gstApplicable = b.gstApplicable;
        _active = b.active;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _branchName.dispose();
    _branchCode.dispose();
    _ownerName.dispose();
    _address.dispose();
    _rent.dispose();
    _rentAdvance.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _startDate = d);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final name = _branchName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Branch name is required.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(rentRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateBranch(
          widget.branchId!,
          branchName: name,
          branchCode: _emptyToNull(_branchCode.text),
          ownerName: _emptyToNull(_ownerName.text),
          address: _emptyToNull(_address.text),
          rent: double.tryParse(_rent.text),
          rentAdvance: double.tryParse(_rentAdvance.text),
          startDate: _startDate,
          gstApplicable: _gstApplicable,
          active: _active,
        );
      } else {
        await repo.createBranch(
          branchName: name,
          branchCode: _emptyToNull(_branchCode.text),
          ownerName: _emptyToNull(_ownerName.text),
          address: _emptyToNull(_address.text),
          rent: double.tryParse(_rent.text),
          rentAdvance: double.tryParse(_rentAdvance.text),
          startDate: _startDate,
          gstApplicable: _gstApplicable,
          active: _active,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? 'Branch saved' : 'Branch created')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.branchId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete branch?'),
        content: Text('Delete branch "${_branchName.text}"?'),
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
      await ref.read(rentRepositoryProvider).deleteBranch(widget.branchId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Branch' : 'New Rent Branch'),
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
                  _label('Branch name *'),
                  TextField(controller: _branchName, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),
                  _label('Branch code'),
                  TextField(controller: _branchCode),
                  const SizedBox(height: 10),
                  _label('Owner / landlord name'),
                  TextField(controller: _ownerName, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),
                  _label('Start date'),
                  InkWell(
                    onTap: _pickStartDate,
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
                          Text(
                            _startDate == null ? 'Not set' : df.format(_startDate!),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _label('Address'),
                  TextField(controller: _address, minLines: 2, maxLines: 4),
                  const SizedBox(height: 16),
                  const AppSectionHeader(title: 'Rent'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Monthly rent'),
                            TextField(
                              controller: _rent,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(prefixText: '₹ '),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Rent advance'),
                            TextField(
                              controller: _rentAdvance,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(prefixText: '₹ '),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _label('GST applicable'),
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<bool?>(
                      value: _gstApplicable,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Not determined')),
                        DropdownMenuItem(value: true, child: Text('Yes')),
                        DropdownMenuItem(value: false, child: Text('No')),
                      ],
                      onChanged: (v) => setState(() => _gstApplicable = v),
                    ),
                  ),
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
                      child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create branch')),
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
