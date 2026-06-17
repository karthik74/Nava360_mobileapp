import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'trainings_models.dart';
import 'trainings_repository.dart';

/// Take a Pre/Post test or give feedback for a training.
class TrainingTestScreen extends ConsumerStatefulWidget {
  const TrainingTestScreen({
    super.key,
    required this.trainingId,
    required this.section, // PRE_TEST | POST_TEST | FEEDBACK
    required this.titleLabel,
  });

  final int trainingId;
  final String section;
  final String titleLabel;

  @override
  ConsumerState<TrainingTestScreen> createState() => _TrainingTestScreenState();
}

class _TrainingTestScreenState extends ConsumerState<TrainingTestScreen> {
  List<TQuestion>? _questions;
  final Map<int, dynamic> _answers = {}; // qid -> String | int(rating) | List<int>(options)
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _result;

  bool get _isFeedback => widget.section == 'FEEDBACK';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final qs = await ref
          .read(trainingsRepositoryProvider)
          .getQuestionForm(widget.trainingId, widget.section);
      if (!mounted) return;
      setState(() {
        _questions = qs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load questions.';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(trainingsRepositoryProvider);
    try {
      final payload = (_questions ?? []).map((q) {
        final a = _answers[q.id];
        final isOptions = q.questionType == 'MCQ_SINGLE' ||
            q.questionType == 'MCQ_MULTI' ||
            q.questionType == 'DROPDOWN';
        return <String, dynamic>{
          'questionId': q.id,
          'answerText': (!isOptions && q.questionType != 'RATING') ? a : null,
          'selectedOptionIds': isOptions
              ? (a is List ? a : (a == null ? <int>[] : [a]))
              : <int>[],
          'rating': q.questionType == 'RATING' ? a : null,
        };
      }).toList();

      if (_isFeedback) {
        await repo.submitFeedback(
          widget.trainingId,
          payload
              .map((p) => {
                    'questionId': p['questionId'],
                    'answerText': p['answerText'],
                    'rating': p['rating'],
                  })
              .toList(),
        );
        setState(() => _result = 'Thank you! Your feedback was recorded.');
      } else {
        final attempt = await repo.submitTest(widget.trainingId, widget.section, payload);
        final pct = attempt['percentage'];
        final passed = attempt['passed'] == true;
        setState(() => _result =
            'You scored ${attempt['score']}/${attempt['maxScore']} (${pct}%) — ${passed ? 'Passed' : 'Not passed'}.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(widget.titleLabel)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _result != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 56),
                        const SizedBox(height: 12),
                        Text(_result!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                      ),
                    ...(_questions ?? []).asMap().entries.map((e) => _questionCard(e.key + 1, e.value)),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_submitting ? 'Submitting…' : 'Submit'),
                    ),
                  ],
                ),
    );
  }

  Widget _questionCard(int n, TQuestion q) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n. ${q.text}${q.required ? ' *' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 8),
          _input(q),
        ],
      ),
    );
  }

  Widget _input(TQuestion q) {
    switch (q.questionType) {
      case 'MCQ_SINGLE':
      case 'DROPDOWN':
        return Column(
          children: q.options
              .map((o) => RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(o.text),
                    value: o.id,
                    groupValue: _answers[q.id] is int ? _answers[q.id] as int : null,
                    onChanged: (v) => setState(() => _answers[q.id] = v),
                  ))
              .toList(),
        );
      case 'MCQ_MULTI':
        final sel = (_answers[q.id] as List?)?.cast<int>() ?? <int>[];
        return Column(
          children: q.options
              .map((o) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(o.text),
                    value: sel.contains(o.id),
                    onChanged: (v) => setState(() {
                      final next = [...sel];
                      if (v == true) {
                        next.add(o.id);
                      } else {
                        next.remove(o.id);
                      }
                      _answers[q.id] = next;
                    }),
                  ))
              .toList(),
        );
      case 'YES_NO':
        return Row(
          children: ['YES', 'NO']
              .map((v) => Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(v == 'YES' ? 'Yes' : 'No'),
                      value: v,
                      groupValue: _answers[q.id] as String?,
                      onChanged: (x) => setState(() => _answers[q.id] = x),
                    ),
                  ))
              .toList(),
        );
      case 'RATING':
        final max = q.maxRating ?? 5;
        final current = _answers[q.id] is int ? _answers[q.id] as int : 0;
        return Wrap(
          spacing: 6,
          children: List.generate(max, (i) => i + 1)
              .map((v) => ChoiceChip(
                    label: Text('$v'),
                    selected: current >= v,
                    onSelected: (_) => setState(() => _answers[q.id] = v),
                  ))
              .toList(),
        );
      case 'LONG_ANSWER':
        return TextField(
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (v) => _answers[q.id] = v,
        );
      default: // SHORT_ANSWER
        return TextField(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (v) => _answers[q.id] = v,
        );
    }
  }
}
