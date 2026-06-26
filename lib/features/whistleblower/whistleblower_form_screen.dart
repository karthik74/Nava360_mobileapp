import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'whistleblower_evidence.dart';
import 'whistleblower_models.dart';
import 'whistleblower_repository.dart';

class WhistleblowerFormScreen extends ConsumerStatefulWidget {
  const WhistleblowerFormScreen({super.key});

  @override
  ConsumerState<WhistleblowerFormScreen> createState() => _WhistleblowerFormScreenState();
}

class _WhistleblowerFormScreenState extends ConsumerState<WhistleblowerFormScreen> {
  List<WbCategoryOption> _categories = [];
  String? _category;
  final _subject = TextEditingController();
  final _description = TextEditingController();
  DateTime? _incidentDate;
  final _department = TextEditingController();
  final _persons = TextEditingController();
  bool _anonymous = false;
  final List<EvidenceFile> _evidence = [];

  bool _submitting = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(whistleblowerRepositoryProvider).categories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    _department.dispose();
    _persons.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_category == null) {
      setState(() => _error = 'Please choose a category.');
      return;
    }
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Subject and description are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _progress = 0;
    });
    try {
      await ref.read(whistleblowerRepositoryProvider).createCase(
            category: _category!,
            subject: _subject.text.trim(),
            description: _description.text.trim(),
            incidentDate: _incidentDate,
            department: _department.text,
            personsInvolved: _persons.text,
            anonymous: _anonymous,
            evidence: _evidence,
            onProgress: (s, t) {
              if (mounted && t > 0) setState(() => _progress = s / t);
            },
          );
      if (mounted) await _showSubmitted();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSubmitted() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
            SizedBox(height: 12),
            Text('Submitted successfully',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            SizedBox(height: 6),
            Text('Your concern has been received and will be handled confidentially.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(); // back to the dashboard
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a Concern')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            color: AppColors.info.withOpacity(0.06),
            shadow: AppShadows.soft,
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.info),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your report will be handled confidentially. Please provide accurate and genuine information.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _label('Category *'),
          DropdownButtonFormField<String>(
            value: _category,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined, size: 20)),
            items: [
              for (final c in _categories) DropdownMenuItem(value: c.value, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          _label('Subject *'),
          TextField(controller: _subject, maxLength: 200),
          _label('Description *'),
          TextField(controller: _description, minLines: 4, maxLines: 8),
          const SizedBox(height: 12),
          _label('Incident Date'),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _incidentDate ?? DateTime.now(),
                firstDate: DateTime(2015),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _incidentDate = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.event_rounded, size: 20)),
              child: Text(
                _incidentDate == null ? 'Not set' : DateFormat('d MMM yyyy').format(_incidentDate!),
                style: TextStyle(color: _incidentDate == null ? AppColors.muted : AppColors.ink),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _label('Branch / Department involved'),
          TextField(controller: _department),
          const SizedBox(height: 12),
          _label('Person(s) involved'),
          TextField(controller: _persons),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: const Text('Submit anonymously'),
            subtitle: const Text('Your name will be hidden from reviewers.'),
          ),
          const SizedBox(height: 8),
          EvidenceSection(evidence: _evidence, onChanged: () => setState(() {})),
          const SizedBox(height: 16),
          const Text(
            'Please ensure the uploaded evidence is genuine and relevant to the concern raised.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          GlassCard(
            color: AppColors.warning.withOpacity(0.08),
            shadow: AppShadows.soft,
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'False or malicious complaints may lead to disciplinary action as per company policy.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppErrorPanel(message: _error!),
          ],
          const SizedBox(height: 18),
          if (_submitting && _progress > 0 && _progress < 1) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Submit Report'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      );
}
