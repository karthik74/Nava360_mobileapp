import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
import 'rent_models.dart';
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
  RentBranch? _loaded; // preserves orgBranchId / gstLockedUntil on edit
  double? _gstRate; // null = system default (18%)
  double? _tdsRate; // null = system default (10% once rent >= 50,000)
  RentRateOptions _rateOptions = RentRateOptions.fallback;

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
    ref.read(rentRepositoryProvider).getRateOptions().then((o) {
      if (mounted) setState(() => _rateOptions = o);
    }).catchError((_) {});
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
        _loaded = b;
        _gstRate = b.gstRatePercent == 18 ? null : b.gstRatePercent;
        _tdsRate = b.tdsRatePercent == 10 ? null : b.tdsRatePercent;
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
          orgBranchId: _loaded?.orgBranchId,
          gstLockedUntil: _loaded?.gstLockedUntil,
          gstRatePercent: _gstApplicable == true ? _gstRate : null,
          tdsRatePercent: _tdsRate,
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
          gstRatePercent: _gstApplicable == true ? _gstRate : null,
          tdsRatePercent: _tdsRate,
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

  String _fmtRate(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: _isEdit ? 'Edit branch' : 'New rent branch',
        subtitle: 'Rent management · landlord record',
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
                  child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create branch')),
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
                      const ProSectionHeader(title: 'Branch'),
                      const SizedBox(height: 12),
                      ProField(
                        label: 'Branch name',
                        required: true,
                        child: TextField(controller: _branchName, textCapitalization: TextCapitalization.words),
                      ),
                      const SizedBox(height: 14),
                      ProField(label: 'Branch code', child: TextField(controller: _branchCode)),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Owner / landlord name',
                        child: TextField(controller: _ownerName, textCapitalization: TextCapitalization.words),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Start date',
                        child: _dateField(
                          _startDate == null ? 'Not set' : df.format(_startDate!),
                          _pickStartDate,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'Address',
                        child: TextField(controller: _address, minLines: 2, maxLines: 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProSectionHeader(title: 'Rent'),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ProField(
                              label: 'Monthly rent',
                              child: TextField(
                                controller: _rent,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: AppText.number.copyWith(fontSize: 15, color: AppColors.ink),
                                decoration: const InputDecoration(prefixText: '₹ '),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ProField(
                              label: 'Rent advance',
                              child: TextField(
                                controller: _rentAdvance,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: AppText.number.copyWith(fontSize: 15, color: AppColors.ink),
                                decoration: const InputDecoration(prefixText: '₹ '),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ProField(
                        label: 'GST applicable',
                        child: DropdownButtonFormField<bool?>(
                          value: _gstApplicable,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Not determined')),
                            DropdownMenuItem(value: true, child: Text('Yes')),
                            DropdownMenuItem(value: false, child: Text('No')),
                          ],
                          onChanged: (v) => setState(() {
                            _gstApplicable = v;
                            if (v != true) _gstRate = null; // no stale custom rate when GST isn't charged
                          }),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ProField(
                              label: 'GST rate',
                              child: DropdownButtonFormField<double?>(
                                value: _gstRate,
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('18% (default)')),
                                  for (final r in _rateOptions.gstRates.where((r) => r != 18))
                                    DropdownMenuItem(value: r, child: Text('${_fmtRate(r)}%')),
                                  if (_gstRate != null && _gstRate != 18 && !_rateOptions.gstRates.contains(_gstRate))
                                    DropdownMenuItem(value: _gstRate, child: Text('${_fmtRate(_gstRate!)}%')),
                                ],
                                onChanged: _gstApplicable == true ? (v) => setState(() => _gstRate = v) : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ProField(
                              label: 'TDS rate',
                              child: DropdownButtonFormField<double?>(
                                value: _tdsRate,
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('10% (default)')),
                                  for (final r in _rateOptions.tdsRates.where((r) => r != 10))
                                    DropdownMenuItem(value: r, child: Text(r == 0 ? 'Not applicable' : '${_fmtRate(r)}%')),
                                  if (_tdsRate != null && _tdsRate != 10 && !_rateOptions.tdsRates.contains(_tdsRate))
                                    DropdownMenuItem(value: _tdsRate, child: Text('${_fmtRate(_tdsRate!)}%')),
                                ],
                                onChanged: (v) => setState(() => _tdsRate = v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: SwitchListTile.adaptive(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    title: const Text('Active', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
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

  /// Tappable date box in the input style.
  Widget _dateField(String value, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          enabled: onTap != null,
          prefixIcon: Icon(Icons.calendar_today_rounded, size: 17, color: AppColors.primary),
          suffixIcon: const Icon(Icons.expand_more_rounded),
        ),
        child: Text(
          value,
          style: TextStyle(fontSize: 15, color: onTap == null ? AppColors.muted : AppColors.ink),
        ),
      ),
    );
  }
}
