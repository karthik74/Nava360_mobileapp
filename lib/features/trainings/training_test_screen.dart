import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
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

  /// Presentation only: whether a question already has an answer (drives the
  /// progress bar; submit/validation are unchanged).
  bool _answered(TQuestion q) {
    final a = _answers[q.id];
    if (a == null) return false;
    if (a is List) return a.isNotEmpty;
    if (a is String) return a.trim().isNotEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final qs = _questions ?? const <TQuestion>[];
    final answered = qs.where(_answered).length;
    final kind = _isFeedback ? 'Feedback' : 'Training test';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: widget.titleLabel,
        subtitle: _loading || _result != null
            ? kind
            : '$kind · ${qs.length} ${qs.length == 1 ? 'question' : 'questions'}',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _result != null
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                      child: Column(
                        children: [
                          const ProIconWell(
                            icon: Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 64,
                          ),
                          const SizedBox(height: 14),
                          ProPill.ok(_isFeedback ? 'Recorded' : 'Submitted'),
                          const SizedBox(height: 12),
                          Text(
                            _result!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (qs.isNotEmpty) ...[
                      Text(
                        '$answered of ${qs.length} answered',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ProBar(value: qs.isEmpty ? 0 : answered / qs.length),
                      const SizedBox(height: 14),
                    ],
                    if (_error != null) ...[
                      ProNote(_error!, tone: ProNoteTone.bad),
                      const SizedBox(height: 12),
                    ],
                    for (final e in qs.asMap().entries) ...[
                      _questionCard(e.key + 1, qs.length, e.value),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
      bottomNavigationBar: _loading
          ? null
          : ProBottomBar(
              children: [
                if (_result != null)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Done'),
                  )
                else
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(_submitting ? 'Submitting…' : 'Submit'),
                  ),
              ],
            ),
    );
  }

  Widget _questionCard(int n, int total, TQuestion q) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Question $n of $total',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (q.required) ProPill.neutral('Required'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${q.text}${q.required ? ' *' : ''}',
            style: const TextStyle(
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.25,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          _input(q),
        ],
      ),
    );
  }

  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  Widget _input(TQuestion q) {
    switch (q.questionType) {
      case 'MCQ_SINGLE':
      case 'DROPDOWN':
        final current = _answers[q.id] is int ? _answers[q.id] as int : null;
        return Column(
          children: [
            for (final (i, o) in q.options.indexed)
              _OptionTile(
                letter: i < _letters.length ? _letters[i] : '${i + 1}',
                label: o.text,
                selected: current == o.id,
                multi: false,
                onTap: () => setState(() => _answers[q.id] = o.id),
              ),
          ],
        );
      case 'MCQ_MULTI':
        final sel = (_answers[q.id] as List?)?.cast<int>() ?? <int>[];
        return Column(
          children: [
            for (final (i, o) in q.options.indexed)
              _OptionTile(
                letter: i < _letters.length ? _letters[i] : '${i + 1}',
                label: o.text,
                selected: sel.contains(o.id),
                multi: true,
                onTap: () {
                  final v = !sel.contains(o.id);
                  setState(() {
                    final next = [...sel];
                    if (v) {
                      next.add(o.id);
                    } else {
                      next.remove(o.id);
                    }
                    _answers[q.id] = next;
                  });
                },
              ),
          ],
        );
      case 'YES_NO':
        final current = _answers[q.id] as String?;
        return Row(
          children: [
            for (final v in const ['YES', 'NO']) ...[
              if (v == 'NO') const SizedBox(width: 10),
              Expanded(
                child: _YesNoTile(
                  label: v == 'YES' ? 'Yes' : 'No',
                  selected: current == v,
                  onTap: () => setState(() => _answers[q.id] = v),
                ),
              ),
            ],
          ],
        );
      case 'RATING':
        final max = q.maxRating ?? 5;
        final current = _answers[q.id] is int ? _answers[q.id] as int : 0;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in List.generate(max, (i) => i + 1))
              _RatingBox(
                value: v,
                selected: current >= v,
                onTap: () => setState(() => _answers[q.id] = v),
              ),
          ],
        );
      case 'LONG_ANSWER':
        return TextField(
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Your answer'),
          onChanged: (v) => setState(() => _answers[q.id] = v),
        );
      default: // SHORT_ANSWER
        return TextField(
          decoration: const InputDecoration(hintText: 'Your answer'),
          onChanged: (v) => setState(() => _answers[q.id] = v),
        );
    }
  }
}

/// Bordered answer option with a letter badge and a radio / check mark.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.label,
    required this.selected,
    required this.multi,
    required this.onTap,
  });
  final String letter;
  final String label;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFF2F8F9) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? primary : const Color(0xFFDBE3E5),
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? primary : AppColors.neutralTint,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : const Color(0xFF43585D),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Mark(selected: selected, multi: multi),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.selected, required this.multi});
  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    if (multi) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: selected ? null : Border.all(color: const Color(0xFFB9C7CA), width: 1.5),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? primary : const Color(0xFFB9C7CA),
          width: selected ? 6.5 : 1.5,
        ),
      ),
    );
  }
}

class _YesNoTile extends StatelessWidget {
  const _YesNoTile({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Material(
      color: selected ? const Color(0xFFF2F8F9) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? primary : const Color(0xFFDBE3E5),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Mark(selected: selected, multi: false),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingBox extends StatelessWidget {
  const _RatingBox({required this.value, required this.selected, required this.onTap});
  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.primary : const Color(0xFFDBE3E5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.inkSoft,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
