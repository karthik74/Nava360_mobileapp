import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
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
    final branches = branchesAsync.valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Issue notice',
        subtitle: 'Rent management · notice to a branch',
      ),
      bottomNavigationBar: branches == null
          ? null
          : ProBottomBar(
              children: [
                FilledButton.icon(
                  onPressed: _saving || branches.isEmpty ? null : _save,
                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: Text(_saving ? 'Issuing…' : 'Issue notice'),
                ),
              ],
            ),
      body: branchesAsync.when(
        data: (branches) {
          _branchId ??= branches.isNotEmpty ? branches.first.id : null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProSectionHeader(title: 'Notice'),
                    const SizedBox(height: 12),
                    ProField(
                      label: 'Branch',
                      required: true,
                      child: DropdownButtonFormField<int>(
                        value: _branchId,
                        isExpanded: true,
                        items: [
                          for (final b in branches)
                            DropdownMenuItem(
                                value: b.id, child: Text(b.branchName, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _branchId = v),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Subject',
                      required: true,
                      child: TextField(controller: _subject, textCapitalization: TextCapitalization.sentences),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Body',
                      child: TextField(controller: _body, minLines: 3, maxLines: 6),
                    ),
                    const SizedBox(height: 14),
                    ProField(
                      label: 'Issued on',
                      required: true,
                      child: InkWell(
                        onTap: _pickIssuedOn,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.calendar_today_rounded, size: 17, color: AppColors.primary),
                            suffixIcon: const Icon(Icons.expand_more_rounded),
                          ),
                          child: Text(df.format(_issuedOn),
                              style: const TextStyle(fontSize: 15, color: AppColors.ink)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: SwitchListTile.adaptive(
                  value: _holdRent,
                  onChanged: (v) => setState(() => _holdRent = v),
                  title: const Text("Place this branch's current month rent on hold",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                ProNote(_error!, tone: ProNoteTone.bad),
              ],
              if (branches.isEmpty) ...[
                const SizedBox(height: 14),
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
}
