import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
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
    final branches = branchesAsync.valueOrNull;

    Widget? bottomBar;
    // canReview implies editable (both need full access / a pending bill).
    if (branches != null && editable) {
      bottomBar = ProBottomBar(
        top: canReview && editable
            ? Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _review(approve: false),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.dangerTint,
                        foregroundColor: AppColors.danger,
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _review(approve: true),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              )
            : null,
        children: [
          FilledButton(
            onPressed: _saving || _uploading || branches.isEmpty ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save bill'),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: bill == null ? 'Utility bill' : 'Utility bill · ${bill.branchName}',
        subtitle: bill == null ? 'Rent management · file a bill' : 'Rent management · ${rentUtilityKindLabel(bill.kind)}',
      ),
      bottomNavigationBar: bottomBar,
      body: branchesAsync.when(
        data: (branches) {
          // A branch user's list only holds their own branch(es), so the first is theirs; an admin picks.
          _branchId ??= branches.isNotEmpty ? branches.first.id : null;
          final lockBranch = bill != null || !isFullAccess;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (bill != null) ...[
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ProIconWell(
                            icon: rentUtilityKindIcon(bill.kind),
                            color: bill.kind == RentUtilityKind.internet ? AppColors.info : const Color(0xFF9A5B00),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                bill.status == 'APPROVED'
                                    ? ProPill.ok('Approved')
                                    : bill.status == 'REJECTED'
                                        ? ProPill.bad('Rejected')
                                        : ProPill.neutral('Pending review'),
                                if (bill.paidAt != null)
                                  ProPill.ok('Paid${bill.paidUtr == null ? '' : ' · ${bill.paidUtr}'}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (bill.uploadedBy != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Filed by ${bill.uploadedBy}${bill.status != 'PENDING' && bill.approvedBy != null ? ' · reviewed by ${bill.approvedBy}' : ''}',
                          style: AppText.caption,
                        ),
                      ],
                      if (bill.status == 'REJECTED' && (bill.rejectionReason ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ProNote('Rejected: ${bill.rejectionReason}', tone: ProNoteTone.bad),
                      ],
                      if (!editable) ...[
                        const SizedBox(height: 10),
                        const ProNote('This bill has been reviewed — only a full-access admin can change it.'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else ...[
                const ProNote(
                  'Saving again for the same branch/kind/period updates the existing bill. It goes to an admin for approval.',
                  tone: ProNoteTone.info,
                ),
                const SizedBox(height: 14),
              ],
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Bill'),
                    const SizedBox(height: 12),
                    ProField(
                      label: 'Branch',
                      required: true,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: branches.any((b) => b.id == _branchId) ? _branchId : null,
                        items: [
                          for (final b in branches)
                            DropdownMenuItem(value: b.id, child: Text(b.branchName, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: lockBranch || !editable ? null : (v) => setState(() => _branchId = v),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ProField(
                            label: 'Kind',
                            required: true,
                            child: DropdownButtonFormField<String>(
                              value: _kind,
                              isExpanded: true,
                              items: [
                                for (final k in RentUtilityKind.values)
                                  DropdownMenuItem(value: k, child: Text(rentUtilityKindLabel(k))),
                              ],
                              onChanged: bill != null || !editable ? null : (v) => setState(() => _kind = v ?? _kind),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dateBox(isInternet ? 'From month' : 'Period', dfMonth.format(_period),
                              bill != null || !editable ? null : _pickPeriod,
                              required: true, icon: Icons.calendar_month_rounded),
                        ),
                      ],
                    ),
                    if (isInternet) ...[
                      const SizedBox(height: 14),
                      _dateBox('Bill covers up to (last month)', dfMonth.format(_periodEnd),
                          editable ? _pickPeriodEnd : null,
                          required: true,
                          icon: Icons.date_range_rounded,
                          helper: 'Internet bills can cover 3 or 6 months — pick the last month this bill covers.'),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ProField(
                            label: 'Amount',
                            child: TextField(
                              controller: _amount,
                              enabled: editable,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: AppText.number.copyWith(fontSize: 15, color: AppColors.ink),
                              decoration: const InputDecoration(prefixText: '₹ '),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ProField(
                            label: 'Bill number',
                            child: TextField(controller: _billNumber, enabled: editable),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _dateBox('Bill date', _billDate == null ? 'Not set' : dfDay.format(_billDate!), !editable
                              ? null
                              : () async {
                                  final d = await _pickDate(_billDate);
                                  if (d != null) setState(() => _billDate = d);
                                }),
                        ),
                        const SizedBox(width: 12),
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
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Bill copy and notes'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.hairlineSoft),
                      ),
                      child: Row(
                        children: [
                          ProIconWell(
                            icon: _documentName == null ? Icons.attach_file_rounded : Icons.description_outlined,
                            color: _documentName == null ? null : AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _uploading ? 'Uploading…' : (_documentName ?? 'No file attached'),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _documentName == null ? AppColors.muted : AppColors.ink),
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
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Notes',
                      child: TextField(controller: _notes, enabled: editable, minLines: 2, maxLines: 4),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                ProNote(_error!, tone: ProNoteTone.bad),
              ],
              if (canDelete) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete bill'),
                ),
              ],
              if (branches.isEmpty) ...[
                const SizedBox(height: 10),
                const ProNote('No rent branches configured yet — add one in the Branches tab first.',
                    tone: ProNoteTone.warn),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AppErrorPanel(message: '$e'),
          ),
        ),
      ),
    );
  }

  Widget _dateBox(String label, String value, VoidCallback? onTap,
      {bool required = false, IconData icon = Icons.calendar_today_rounded, String? helper}) {
    return ProField(
      label: label,
      required: required,
      helper: helper,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            enabled: onTap != null,
            prefixIcon: Icon(icon, size: 17, color: onTap == null ? AppColors.faint : AppColors.primary),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: onTap == null ? AppColors.muted : AppColors.ink),
          ),
        ),
      ),
    );
  }
}
