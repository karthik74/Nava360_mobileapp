import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'requisition_models.dart';
import 'requisition_repository.dart';

/// Form to raise a new job requisition. Pops with `true` on success so the
/// caller can refresh the list.
class CreateRequisitionScreen extends ConsumerStatefulWidget {
  const CreateRequisitionScreen({super.key});

  @override
  ConsumerState<CreateRequisitionScreen> createState() =>
      _CreateRequisitionScreenState();
}

class _CreateRequisitionScreenState
    extends ConsumerState<CreateRequisitionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _positions = TextEditingController(text: '1');
  final _jobDescription = TextEditingController();
  final _requiredSkills = TextEditingController();
  final _notes = TextEditingController();

  String? _department; // selected department label (from master lookup)
  String? _designation; // selected designation label (from master lookup)
  ExperienceLevel? _experience;
  RequisitionPriority _priority = RequisitionPriority.medium;
  DateTime? _targetDate;
  int? _branchId;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _positions.dispose();
    _jobDescription.dispose();
    _requiredSkills.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final payload = NewRequisition(
        title: _title.text,
        department: _department,
        designation: _designation,
        branchId: _branchId,
        numberOfPositions: int.tryParse(_positions.text.trim()) ?? 1,
        jobDescription: _jobDescription.text,
        requiredSkills: _requiredSkills.text,
        experienceLevel: _experience,
        priority: _priority,
        targetDate: _targetDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_targetDate!),
        notes: _notes.text,
      );
      await ref.read(requisitionRepositoryProvider).create(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Requisition created (draft).')),
        );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  BranchOption? _selectedBranch(List<BranchOption> branches) {
    for (final b in branches) {
      if (b.id == _branchId) return b;
    }
    return null;
  }

  /// Opens a searchable branch picker. Returns the chosen branch id, or null
  /// if dismissed. Matches on branch label, code, and region/division/area.
  Future<int?> _openBranchSearch(List<BranchOption> branches) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? branches
                : branches
                    .where((b) =>
                        b.label.toLowerCase().contains(q) ||
                        (b.code?.toLowerCase().contains(q) ?? false) ||
                        b.hierarchy.toLowerCase().contains(q))
                    .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          onChanged: (v) => setSheet(() => query = v),
                          decoration: const InputDecoration(
                            hintText: 'Search branch, area, region…',
                            prefixIcon: Icon(Icons.search_rounded, size: 20),
                          ),
                        ),
                      ),
                      Flexible(
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No branches match your search.',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, indent: 16, endIndent: 16),
                                itemBuilder: (_, i) {
                                  final b = filtered[i];
                                  final selected = b.id == _branchId;
                                  return ListTile(
                                    title: Text(
                                      (b.code == null || b.code!.isEmpty)
                                          ? b.label
                                          : '${b.label} (${b.code})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: b.hierarchy.isEmpty
                                        ? null
                                        : Text(b.hierarchy,
                                            style: const TextStyle(
                                                fontSize: 11.5)),
                                    trailing: selected
                                        ? Icon(Icons.check_rounded,
                                            color: AppColors.primary)
                                        : null,
                                    onTap: () => Navigator.pop(ctx, b.id),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBranchCard(AsyncValue<List<BranchOption>> async) {
    return GlassCard(
      child: async.when(
        loading: () => const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading branches…',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
        error: (_, __) => const Text(
          'Could not load branches. Check your connection and reopen this '
          'screen.',
          style: TextStyle(color: AppColors.danger, fontSize: 12.5),
        ),
        data: (branches) {
          if (branches.isEmpty) {
            return Row(
              children: const [
                Icon(Icons.location_off_outlined,
                    size: 18, color: AppColors.muted),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No branches available for your access.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                ),
              ],
            );
          }
          return FormField<int>(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (_) => _branchId == null ? 'Please select a branch' : null,
            builder: (field) {
              final selected = _selectedBranch(branches);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    onTap: () async {
                      final picked = await _openBranchSearch(branches);
                      if (picked != null) {
                        setState(() => _branchId = picked);
                        field.didChange(picked);
                      }
                    },
                    child: InputDecorator(
                      isEmpty: selected == null,
                      decoration: InputDecoration(
                        labelText: 'Branch *',
                        prefixIcon:
                            const Icon(Icons.location_on_outlined, size: 20),
                        suffixIcon:
                            const Icon(Icons.arrow_drop_down_rounded),
                        errorText: field.errorText,
                      ),
                      child: selected == null
                          ? null
                          : Text(
                              (selected.code == null || selected.code!.isEmpty)
                                  ? selected.label
                                  : '${selected.label} (${selected.code})',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                  if (selected != null && selected.hierarchy.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.account_tree_outlined,
                            size: 14, color: AppColors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selected.hierarchy,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkSoft,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// A dropdown fed by a master-data lookup (department / designation). Handles
  /// loading / error / empty states gracefully and keeps the current value even
  /// if it isn't in the active list (so editing never loses a stored value).
  Widget _lookupDropdown({
    required AsyncValue<List<LookupOption>> async,
    required String label,
    required IconData icon,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return async.when(
      loading: () => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
        child: Row(
          children: const [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Loading…',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      ),
      error: (_, __) => TextFormField(
        initialValue: value,
        textCapitalization: TextCapitalization.words,
        inputFormatters: const [TitleCaseTextFormatter()],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          helperText: 'Could not load options — type a value',
        ),
        onChanged: onChanged,
      ),
      data: (options) {
        final labels = <String>{
          for (final o in options) o.label,
          if (value != null && value.isNotEmpty) value,
        }.toList();
        return DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20),
          ),
          items: [
            for (final l in labels)
              DropdownMenuItem(value: l, child: Text(l)),
          ],
          onChanged: onChanged,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(scopedBranchesProvider);
    final departmentsAsync = ref.watch(departmentOptionsProvider);
    final designationsAsync = ref.watch(designationOptionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New requisition')),
      body: GlassBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppPageHeader(
                    title: 'Raise a requisition',
                    subtitle: 'It will be created as a draft for approval',
                  ),
                  const SizedBox(height: 18),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _title,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Job title *',
                            prefixIcon: Icon(Icons.work_outline_rounded,
                                size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Title is required'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _lookupDropdown(
                          async: departmentsAsync,
                          label: 'Department',
                          icon: Icons.apartment_rounded,
                          value: _department,
                          onChanged: (v) => setState(() => _department = v),
                        ),
                        const SizedBox(height: 14),
                        _lookupDropdown(
                          async: designationsAsync,
                          label: 'Designation',
                          icon: Icons.badge_outlined,
                          value: _designation,
                          onChanged: (v) => setState(() => _designation = v),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _positions,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Number of positions',
                            prefixIcon: Icon(Icons.groups_outlined, size: 20),
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n < 1 || n > 100) {
                              return 'Enter a number between 1 and 100';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildBranchCard(branchesAsync),
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<ExperienceLevel>(
                          value: _experience,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Experience level',
                            prefixIcon:
                                Icon(Icons.trending_up_rounded, size: 20),
                          ),
                          items: [
                            for (final e in ExperienceLevel.values)
                              DropdownMenuItem(value: e, child: Text(e.label)),
                          ],
                          onChanged: (v) => setState(() => _experience = v),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<RequisitionPriority>(
                          value: _priority,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                            prefixIcon: Icon(Icons.flag_outlined, size: 20),
                          ),
                          items: [
                            for (final p in RequisitionPriority.values)
                              DropdownMenuItem(value: p, child: Text(p.label)),
                          ],
                          onChanged: (v) => setState(
                              () => _priority = v ?? RequisitionPriority.medium),
                        ),
                        const SizedBox(height: 14),
                        InkWell(
                          onTap: _pickTargetDate,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Target date',
                              prefixIcon:
                                  Icon(Icons.event_outlined, size: 20),
                            ),
                            child: Text(
                              _targetDate == null
                                  ? 'Not set'
                                  : DateFormat('d MMM yyyy')
                                      .format(_targetDate!),
                              style: TextStyle(
                                fontSize: 14,
                                color: _targetDate == null
                                    ? AppColors.muted
                                    : AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _jobDescription,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Job description',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _requiredSkills,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Required skills',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _notes,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AppErrorPanel(message: _error!),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_loading ? 'Creating…' : 'Create requisition'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
