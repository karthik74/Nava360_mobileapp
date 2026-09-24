import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../files/file_repository.dart';
import 'rent_list_screen.dart' show rentBranchesProvider;
import 'rent_models.dart';
import 'rent_repository.dart';
import 'rent_status_ui.dart';

/// File, review or edit a utility bill (electricity/internet) for a branch.
/// Mirrors the web "Add / update bill" dialog:
///  * a branch user files a bill for their own branch and can edit it while it is still Pending;
///  * a full-access admin (DATA_SCOPE_ALL) can file for any branch, edit any bill, approve / reject a
///    pending one, and delete;
///  * internet bills can cover several months (pick the last month covered — 3 / 6 months etc.);
///  * the bill itself can be attached as a photo or file.
/// Pops `true` on any change so the list refreshes.
class RentUtilityBillFormScreen extends ConsumerStatefulWidget {
  const RentUtilityBillFormScreen({super.key, this.bill});

  /// The bill being viewed / edited; null when filing a new one.
  final RentUtilityBill? bill;

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
  late DateTime _periodEnd;
  DateTime? _billDate;
  DateTime? _dueDate;
  int? _documentAssetId;
  String? _documentName;

  bool _saving = false;
  bool _uploading = false;
  String? _error;

  RentUtilityBill? get _bill => widget.bill;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final b = widget.bill;
    _period = b != null ? (DateTime.tryParse(b.period) ?? DateTime(now.year, now.month, 1)) : DateTime(now.year, now.month, 1);
    _periodEnd = b?.periodEnd ?? _period;
    if (b != null) {
      _branchId = b.branchId;
      _kind = b.kind;
      _amount.text = b.amount == null ? '' : '${b.amount}';
      _billNumber.text = b.billNumber ?? '';
      _notes.text = b.notes ?? '';
      _billDate = b.billDate;
      _dueDate = b.dueDate;
      _documentAssetId = b.documentAssetId;
      _documentName = b.documentName;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _billNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickMonth(DateTime initial, {DateTime? first}) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(2015),
      lastDate: DateTime(2035),
      initialDatePickerMode: DatePickerMode.year,
    );
  }

  Future<void> _pickPeriod() async {
    final d = await _pickMonth(_period);
    if (d == null) return;
    setState(() {
      _period = DateTime(d.year, d.month, 1);
      if (_periodEnd.isBefore(_period)) _periodEnd = _period;
    });
  }

  Future<void> _pickPeriodEnd() async {
    final d = await _pickMonth(_periodEnd.isBefore(_period) ? _period : _periodEnd, first: _period);
    if (d != null) setState(() => _periodEnd = DateTime(d.year, d.month, 1));
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
  }

  Future<void> _attach({required bool camera}) async {
    String? path;
    String? name;
    if (camera) {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      path = picked?.path;
      name = picked?.name;
    } else {
      final picked = await FilePicker.platform.pickFiles();
      path = picked?.files.single.path;
      name = picked?.files.single.name;
    }
    if (path == null) return;
    setState(() => _uploading = true);
    try {
      final uploaded = await ref.read(fileRepositoryProvider).upload(path, filename: name);
      if (!mounted) return;
      setState(() {
        _documentAssetId = uploaded.id;
        _documentName = uploaded.name;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
            periodEnd: _kind == RentUtilityKind.internet ? _periodEnd : null,
            kind: _kind,
            amount: _amount.text.trim().isEmpty ? null : double.tryParse(_amount.text),
            billNumber: _billNumber.text.trim().isEmpty ? null : _billNumber.text.trim(),
            billDate: _billDate,
            dueDate: _dueDate,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            documentAssetId: _documentAssetId,
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

  Future<void> _review({required bool approve}) async {
    final bill = _bill;
    if (bill == null) return;
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject bill'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Reason for rejecting'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Reject')),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(rentRepositoryProvider);
      if (approve) {
        await repo.approveUtilityBill(bill.id);
      } else {
        await repo.rejectUtilityBill(bill.id, reason!);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final bill = _bill;
    if (bill == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete bill?'),
        content: const Text('This bill will be removed.'),
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
    if (ok != true) return;
    try {
      await ref.read(rentRepositoryProvider).deleteUtilityBill(bill.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dfMonth = DateFormat('MMMM yyyy');
    final dfDay = DateFormat('d MMM yyyy');
    final branchesAsync = ref.watch(rentBranchesProvider);
    final user = ref.watch(authUserProvider);
    final isFullAccess = user?.hasPermission('DATA_SCOPE_ALL') ?? false;
    final bill = _bill;
    // A branch user can file a new bill or edit their own while it is still pending; once reviewed only a
    // full-access admin may change it.
    final editable = isFullAccess || bill == null || bill.status == 'PENDING';
    final canReview = isFullAccess && bill != null && bill.status == 'PENDING';
    final canDelete = bill != null && (isFullAccess || bill.status == 'PENDING');
    final isInternet = _kind == RentUtilityKind.internet;

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(bill == null ? 'Utility Bill' : 'Utility Bill · ${bill.branchName}'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: branchesAsync.when(
          data: (branches) {
            // A branch user's list only holds their own branch(es), so the first is theirs; an admin picks.
            _branchId ??= branches.isNotEmpty ? branches.first.id : null;
            final lockBranch = bill != null || !isFullAccess;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (bill != null) ...[
                  Row(
                    children: [
                      StatusPill(
                        label: bill.status == 'APPROVED' ? 'Approved' : (bill.status == 'REJECTED' ? 'Rejected' : 'Pending review'),
                        color: bill.status == 'REJECTED'
                            ? AppColors.danger
                            : bill.status == 'APPROVED'
                                ? AppColors.success
                                : AppColors.muted,
                      ),
                      if (bill.paidAt != null) ...[
                        const SizedBox(width: 8),
                        StatusPill(label: 'Paid${bill.paidUtr == null ? '' : ' · ${bill.paidUtr}'}', color: AppColors.success),
                      ],
                    ],
                  ),
                  if (bill.status == 'REJECTED' && (bill.rejectionReason ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Rejected: ${bill.rejectionReason}', style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                  ],
                  if (bill.uploadedBy != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Filed by ${bill.uploadedBy}${bill.status != 'PENDING' && bill.approvedBy != null ? ' · reviewed by ${bill.approvedBy}' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                  if (!editable) ...[
                    const SizedBox(height: 6),
                    const Text('This bill has been reviewed — only a full-access admin can change it.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ],
                  const SizedBox(height: 12),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Saving again for the same branch/kind/period updates the existing bill. It goes to an admin for approval.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                _label('Branch *'),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: branches.any((b) => b.id == _branchId) ? _branchId : null,
                  items: [
                    for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.branchName, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: lockBranch || !editable ? null : (v) => setState(() => _branchId = v),
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
                            onChanged: bill != null || !editable ? null : (v) => setState(() => _kind = v ?? _kind),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _dateBox(isInternet ? 'From month *' : 'Period *', dfMonth.format(_period), bill != null || !editable ? null : _pickPeriod)),
                  ],
                ),
                if (isInternet) ...[
                  const SizedBox(height: 10),
                  _dateBox('Bill covers up to (last month) *', dfMonth.format(_periodEnd), editable ? _pickPeriodEnd : null),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Internet bills can cover 3 or 6 months — pick the last month this bill covers.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ),
                ],
                const SizedBox(height: 10),
                _label('Amount'),
                TextField(
                  controller: _amount,
                  enabled: editable,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(prefixText: '₹ '),
                ),
                const SizedBox(height: 10),
                _label('Bill number'),
                TextField(controller: _billNumber, enabled: editable),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _dateBox('Bill date', _billDate == null ? 'Not set' : dfDay.format(_billDate!), !editable
                          ? null
                          : () async {
                              final d = await _pickDate(_billDate);
                              if (d != null) setState(() => _billDate = d);
                            }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateBox('Due date', _dueDate == null ? 'Not set' : dfDay.format(_dueDate!), !editable
                          ? null
                          : () async {
                              final d = await _pickDate(_dueDate);
                              if (d != null) setState(() => _dueDate = d);
                            }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _label('Bill copy'),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _uploading ? 'Uploading…' : (_documentName ?? 'No file attached'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: _documentName == null ? AppColors.muted : AppColors.ink),
                      ),
                    ),
                    if (editable) ...[
                      IconButton(
                        tooltip: 'Take a photo',
                        onPressed: _uploading ? null : () => _attach(camera: true),
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                      IconButton(
                        tooltip: 'Choose a file',
                        onPressed: _uploading ? null : () => _attach(camera: false),
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                _label('Notes'),
                TextField(controller: _notes, enabled: editable, minLines: 2, maxLines: 4),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AppErrorPanel(message: _error!),
                ],
                const SizedBox(height: 20),
                if (editable)
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _saving || _uploading || branches.isEmpty ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save bill'),
                    ),
                  ),
                if (canReview) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => _review(approve: false),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _saving ? null : () => _review(approve: true),
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (canDelete) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _saving ? null : _delete,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Delete bill'),
                  ),
                ],
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

  Widget _dateBox(String label, String value, VoidCallback? onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onTap == null ? AppColors.muted : AppColors.ink)),
          ),
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );
}
