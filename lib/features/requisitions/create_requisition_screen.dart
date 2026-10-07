import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC6D3D6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Select branch',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.35,
                              color: AppColors.ink,
                            ),
                          ),
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
                                    height: 1,
                                    indent: 62,
                                    endIndent: 16,
                                    color: AppColors.hairlineSoft),
                                itemBuilder: (_, i) {
                                  final b = filtered[i];
                                  final selected = b.id == _branchId;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: ProListRow(
                                      leading: ProIconWell(
                                        icon: Icons.apartment_rounded,
                                        color: selected ? AppColors.primary : null,
                                      ),
                                      title: (b.code == null || b.code!.isEmpty)
                                          ? b.label
                                          : '${b.label} (${b.code})',
                                      subtitle:
                                          b.hierarchy.isEmpty ? null : b.hierarchy,
                                      chevron: false,
                                      trailing: selected
                                          ? Icon(Icons.check_rounded,
                                              color: AppColors.primary)
                                          : null,
                                      onTap: () => Navigator.pop(ctx, b.id),
                                    ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Branch'),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Loading branches…',
                    style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
              ],
            ),
            error: (_, __) => const ProNote(
              'Could not load branches. Check your connection and reopen this '
              'screen.',
              tone: ProNoteTone.bad,
            ),
            data: (branches) {
              if (branches.isEmpty) {
                return const ProNote(
                  'No branches available for your access.',
                  icon: Icons.location_off_outlined,
                );
              }
              return FormField<int>(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (_) => _branchId == null ? 'Please select a branch' : null,
                builder: (field) {
                  final selected = _selectedBranch(branches);
                  return ProField(
                    label: 'Branch',
                    required: true,
                    child: Column(
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
                              hintText: 'Select branch',
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
                                      fontSize: 15,
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w500,
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
                                  size: 15, color: AppColors.muted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(selected.hierarchy, style: AppText.caption),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
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
    return ProField(
      label: label,
      child: async.when(
        loading: () => InputDecorator(
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Loading…',
                  style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
            ],
          ),
        ),
        error: (_, __) => TextFormField(
          initialValue: value,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [TitleCaseTextFormatter()],
          decoration: InputDecoration(
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
            hint: Text('Select ${label.toLowerCase()}'),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 20),
            ),
            items: [
              for (final l in labels)
                DropdownMenuItem(value: l, child: Text(l)),
            ],
            onChanged: onChanged,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(scopedBranchesProvider);
    final departmentsAsync = ref.watch(departmentOptionsProvider);
    final designationsAsync = ref.watch(designationOptionsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'New requisition',
        subtitle: 'Raise a requisition · created as a draft for approval',
      ),
      // A Column (not a lazy ListView) so every field stays mounted and the
      // Form validates all of them, wherever the user has scrolled to.
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Role'),
                    const SizedBox(height: 12),
                    ProField(
                      label: 'Job title',
                      required: true,
                      child: TextFormField(
                        controller: _title,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [TitleCaseTextFormatter()],
                        decoration: const InputDecoration(
                          hintText: 'e.g. Branch Relationship Officer',
                          prefixIcon: Icon(Icons.work_outline_rounded, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Title is required'
                            : null,
                      ),
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
                    ProField(
                      label: 'Number of positions',
                      child: TextFormField(
                        controller: _positions,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildBranchCard(branchesAsync),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Hiring details'),
                    const SizedBox(height: 12),
                    ProField(
                      label: 'Experience level',
                      child: DropdownButtonFormField<ExperienceLevel>(
                        value: _experience,
                        isExpanded: true,
                        hint: const Text('Select experience level'),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.trending_up_rounded, size: 20),
                        ),
                        items: [
                          for (final e in ExperienceLevel.values)
                            DropdownMenuItem(value: e, child: Text(e.label)),
                        ],
                        onChanged: (v) => setState(() => _experience = v),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Priority',
                      child: DropdownButtonFormField<RequisitionPriority>(
                        value: _priority,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.flag_outlined, size: 20),
                        ),
                        items: [
                          for (final p in RequisitionPriority.values)
                            DropdownMenuItem(value: p, child: Text(p.label)),
                        ],
                        onChanged: (v) => setState(
                            () => _priority = v ?? RequisitionPriority.medium),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Target date',
                      child: InkWell(
                        onTap: _pickTargetDate,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.event_outlined, size: 20),
                          ),
                          child: Text(
                            _targetDate == null
                                ? 'Not set'
                                : DateFormat('d MMM yyyy').format(_targetDate!),
                            style: TextStyle(
                              fontSize: 15,
                              color: _targetDate == null
                                  ? AppColors.faint
                                  : AppColors.ink,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Description'),
                    const SizedBox(height: 12),
                    ProField(
                      label: 'Job description',
                      child: TextFormField(
                        controller: _jobDescription,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [TitleCaseTextFormatter()],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Required skills',
                      child: TextFormField(
                        controller: _requiredSkills,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [TitleCaseTextFormatter()],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Notes',
                      child: TextFormField(
                        controller: _notes,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [TitleCaseTextFormatter()],
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AppErrorPanel(message: _error!),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_loading ? 'Creating…' : 'Create requisition'),
          ),
        ],
      ),
    );
  }
}
