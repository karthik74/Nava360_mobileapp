// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — New Audit Plan (mirrors web AuditPlanFormPage).
//
//  Schedules a branch audit against a published template version. Gated by
//  AUDIT_PLAN_CREATE / AUDIT_ADMIN like the web "+ New plan" button. The web has
//  no edit form (a plan is never re-edited; use assign / cancel / reopen), so
//  neither does this screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/branding.dart';
import '../../core/employee_lookup.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'audit_detail_screen.dart';
import 'audit_repository.dart';
import 'my_audits_screen.dart' show auditBranchesProvider;

final _publishedVersionsProvider =
    FutureProvider.autoDispose<List<({int id, String label})>>(
  (ref) => ref.watch(auditRepositoryProvider).publishedTemplateVersions(),
);

final _auditorSearchProvider =
    FutureProvider.autoDispose.family<List<EmployeeLookup>, String>((ref, q) {
  if (q.trim().length < 2) return const [];
  return ref.watch(auditRepositoryProvider).searchAuditors(q.trim());
});

class AuditPlanFormScreen extends ConsumerStatefulWidget {
  const AuditPlanFormScreen({super.key});

  @override
  ConsumerState<AuditPlanFormScreen> createState() =>
      _AuditPlanFormScreenState();
}

class _AuditPlanFormScreenState extends ConsumerState<AuditPlanFormScreen> {
  final _title = TextEditingController();
  final _auditorSearch = TextEditingController();
  int? _versionId;
  int? _branchId;
  EmployeeLookup? _auditor;
  String _auditorQ = '';
  DateTime? _plannedStart, _plannedEnd, _periodFrom, _periodTo;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _auditorSearch.dispose();
    super.dispose();
  }

  static String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (_branchId == null) {
      setState(() => _error =
          'Please select a ${Branding.current.term('branch').toLowerCase()}.');
      return;
    }
    if (_versionId == null) {
      setState(() => _error = 'Please select a published template version.');
      return;
    }
    setState(() => _saving = true);
    try {
      final plan = await ref.read(auditRepositoryProvider).createPlan({
        'title': _title.text.trim(),
        'templateVersionId': _versionId,
        'branchId': _branchId,
        'auditorEmployeeId': _auditor?.id,
        'plannedStartDate': _plannedStart == null ? null : _iso(_plannedStart!),
        'plannedEndDate': _plannedEnd == null ? null : _iso(_plannedEnd!),
        'periodFrom': _periodFrom == null ? null : _iso(_periodFrom!),
        'periodTo': _periodTo == null ? null : _iso(_periodTo!),
      });
      ref.invalidate(myAuditsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Audit plan created'),
        backgroundColor: AppColors.success,
      ));
      final id = plan.id;
      if (id != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AuditDetailScreen(planId: id),
        ));
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final allowed = (user?.hasPermission('AUDIT_PLAN_CREATE') ?? false) ||
        (user?.hasPermission('AUDIT_ADMIN') ?? false);
    final termBranch = Branding.current.term('branch');
    final versions = ref.watch(_publishedVersionsProvider);
    final branches = ref.watch(auditBranchesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('New Audit Plan'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: !allowed
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: AppEmptyState(
                  icon: Icons.lock_outline_rounded,
                  message: 'You do not have permission to create audit plans.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  const Text(
                    'Schedule a branch audit against a published template version.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.danger)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _title,
                    decoration: InputDecoration(
                      labelText: 'Title *',
                      hintText: 'e.g. Q1 $termBranch Audit',
                    ),
                  ),
                  const SizedBox(height: 12),
                  versions.when(
                    loading: () => const LinearProgressIndicator(minHeight: 2),
                    error: (e, __) => Text('Could not load templates: $e',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.danger)),
                    data: (list) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: _versionId,
                          decoration: const InputDecoration(
                              labelText: 'Template version *'),
                          items: [
                            for (final v in list)
                              DropdownMenuItem(
                                  value: v.id,
                                  child: Text(v.label,
                                      overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _versionId = v),
                        ),
                        if (list.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                                'No published template versions available yet.',
                                style: TextStyle(
                                    fontSize: 11.5, color: AppColors.muted)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  branches.when(
                    loading: () => const LinearProgressIndicator(minHeight: 2),
                    error: (e, __) => Text('Could not load branches: $e',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.danger)),
                    data: (list) => DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _branchId,
                      decoration: InputDecoration(labelText: '$termBranch *'),
                      items: [
                        for (final b in list)
                          DropdownMenuItem(
                              value: b.id,
                              child:
                                  Text(b.label, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _branchId = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _auditorField(),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _dateField('Planned start', _plannedStart,
                            (d) => setState(() => _plannedStart = d))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _dateField('Planned end', _plannedEnd,
                            (d) => setState(() => _plannedEnd = d))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _dateField('Audit period from', _periodFrom,
                            (d) => setState(() => _periodFrom = d))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _dateField('Audit period to', _periodTo,
                            (d) => setState(() => _periodTo = d))),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: Text(_saving ? 'Creating…' : 'Create plan'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _auditorField() {
    if (_auditor != null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Auditor',
          suffixIcon: IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _auditor = null),
          ),
        ),
        child: Text(_auditor!.label,
            style: const TextStyle(fontSize: 14, color: AppColors.ink)),
      );
    }
    final results = ref.watch(_auditorSearchProvider(_auditorQ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _auditorSearch,
          decoration: const InputDecoration(
            labelText: 'Auditor (optional)',
            hintText: 'Search an auditor by name',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
          onChanged: (v) => setState(() => _auditorQ = v),
        ),
        if (_auditorQ.trim().length >= 2)
          results.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(minHeight: 2)),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text('$e',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.danger))),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('No matching auditors',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)))
                : Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: ListView(shrinkWrap: true, children: [
                      for (final e in list)
                        ListTile(
                          dense: true,
                          title: Text(e.label,
                              style: const TextStyle(fontSize: 13)),
                          onTap: () {
                            _auditorSearch.clear();
                            setState(() {
                              _auditor = e;
                              _auditorQ = '';
                            });
                          },
                        ),
                    ]),
                  ),
          ),
      ],
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime?> on) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) on(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => on(null),
                ),
        ),
        child: Text(
          value == null ? 'Select' : DateFormat('dd MMM yyyy').format(value),
          style: TextStyle(
              fontSize: 13.5,
              color: value == null ? AppColors.muted : AppColors.ink),
        ),
      ),
    );
  }
}
