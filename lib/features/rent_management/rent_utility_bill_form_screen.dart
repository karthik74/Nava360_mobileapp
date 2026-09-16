import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'rent_list_screen.dart' show rentBranchesProvider;
import 'rent_models.dart';
import 'rent_repository.dart';
import 'rent_status_ui.dart';

/// Add or update a utility bill (electricity/internet) for a branch/period.
/// Saving again for the same branch/kind/period upserts the existing bill
/// (server-side) — mirrors `AdminRentPage.tsx`'s `UtilityTab` "Add / update
/// bill" modal, and Purchase Orders' form-screen structure. Pops `true` on
/// save so the list refreshes.
class RentUtilityBillFormScreen extends ConsumerStatefulWidget {
  const RentUtilityBillFormScreen({super.key, this.initialPeriod});

  /// Period ("yyyy-MM-01") to pre-select, defaulting to the current month.
  final String? initialPeriod;

  @override
  ConsumerState<RentUtilityBillFormScreen> createState() => _RentUtilityBillFormScreenState();
}

class _RentUtilityBillFormScreenState extends ConsumerState<RentUtilityBillFormScreen> {
  final _amount = TextEditingController();
  final _billNumber = TextEditingController();
  final _notes = TextEditingController();

  int? _branchId;
  String _kind = RentUtilityKind.electricity;
  late DateTime _period;
  DateTime? _billDate;
  DateTime? _dueDate;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = widget.initialPeriod != null
        ? (DateTime.tryParse(widget.initialPeriod!) ?? DateTime(now.year, now.month, 1))
        : DateTime(now.year, now.month, 1);
  }

  @override
  void dispose() {
    _amount.dispose();
    _billNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPeriod() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _period,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (d != null) setState(() => _period = DateTime(d.year, d.month, 1));
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_branchId == null) {
      setState(() => _error = 'Select a branch.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(rentRepositoryProvider).upsertUtilityBill(
            branchId: _branchId!,
            period: isoPeriod(_period),
            kind: _kind,
            amount: _amount.text.trim().isEmpty ? null : double.tryParse(_amount.text),
            billNumber: _billNumber.text.trim().isEmpty ? null : _billNumber.text.trim(),
            billDate: _billDate,
            dueDate: _dueDate,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utility bill saved')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dfMonth = DateFormat('MMMM yyyy');
    final dfDay = DateFormat('d MMM yyyy');
    final branchesAsync = ref.watch(rentBranchesProvider);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Utility Bill'),
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
                const Text(
                  'Saving again for the same branch/kind/period updates the existing bill.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                _label('Branch *'),
                DropdownButtonFormField<int>(
                  value: _branchId,
                  items: [
                    for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.branchName)),
                  ],
                  onChanged: (v) => setState(() => _branchId = v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Kind *'),
                          DropdownButtonFormField<String>(
                            value: _kind,
                            items: [
                              for (final k in RentUtilityKind.values)
                                DropdownMenuItem(value: k, child: Text(rentUtilityKindLabel(k))),
                            ],
                            onChanged: (v) => setState(() => _kind = v ?? _kind),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Period *'),
                          InkWell(
                            onTap: _pickPeriod,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(AppRadii.md),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              child: Text(dfMonth.format(_period),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _label('Amount'),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(prefixText: '₹ '),
                ),
                const SizedBox(height: 10),
                _label('Bill number'),
                TextField(controller: _billNumber),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Bill date'),
                          InkWell(
                            onTap: () async {
                              final d = await _pickDate(_billDate);
                              if (d != null) setState(() => _billDate = d);
                            },
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(AppRadii.md),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              child: Text(_billDate == null ? 'Not set' : dfDay.format(_billDate!),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Due date'),
                          InkWell(
                            onTap: () async {
                              final d = await _pickDate(_dueDate);
                              if (d != null) setState(() => _dueDate = d);
                            },
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(AppRadii.md),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              child: Text(_dueDate == null ? 'Not set' : dfDay.format(_dueDate!),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _label('Notes'),
                TextField(controller: _notes, minLines: 2, maxLines: 4),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AppErrorPanel(message: _error!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _saving || branches.isEmpty ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save bill'),
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
