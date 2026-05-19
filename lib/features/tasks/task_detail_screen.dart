import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'form_renderer.dart';
import 'task_done_screen.dart';
import 'task_models.dart';
import 'task_repository.dart';

final taskDetailProvider =
    FutureProvider.autoDispose.family<Task, int>((ref, id) async {
  return ref.watch(taskRepositoryProvider).get(id);
});

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final int taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  FormValues _values = {};
  Map<String, String> _errors = {};
  bool _submitting = false;
  String? _topError;
  String? _topInfo;
  bool _hydrated = false;

  void _hydrate(Task task) {
    if (_hydrated) return;
    _values = parseFormValues(task.formResponse);
    _hydrated = true;
  }

  bool _canSubmit(Task task) {
    return task.status != 'DONE' && task.status != 'CANCELLED';
  }

  Future<void> _submit(Task task) async {
    final schema = FormSchema.parse(task.formSchema);
    final errors = schema == null ? <String, String>{} : validateForm(schema, _values);
    setState(() {
      _errors = errors;
      _topError = errors.isEmpty ? null : 'Please fix the highlighted fields.';
      _topInfo = null;
    });
    if (errors.isNotEmpty) return;

    // Strip values for hidden fields, then JSON-encode.
    final FormValues pruned = {};
    if (schema != null) {
      for (final f in schema.fields) {
        if (isFieldVisible(f, _values) && _values.containsKey(f.name)) {
          pruned[f.name] = _values[f.name];
        }
      }
    } else {
      pruned.addAll(_values);
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(taskRepositoryProvider);
      await repo.submitFormResponse(task.id, jsonEncode(pruned));
      // Also flip status to DONE so it disappears from "todo" filters.
      await repo.updateStatus(task.id, 'DONE');
      if (!mounted) return;
      // Invalidate so the list reloads when the user returns.
      ref.invalidate(taskDetailProvider(task.id));
      // Replace detail with the confirmation screen.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TaskDoneScreen(
            taskTitle: task.title,
            message: 'Marked as Done. You can review submitted answers from the task list.',
          ),
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _topError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _markInProgress(Task task) async {
    try {
      await ref.read(taskRepositoryProvider).updateStatus(task.id, 'IN_PROGRESS');
      ref.invalidate(taskDetailProvider(task.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(widget.taskId));
    return Scaffold(
      appBar: AppBar(title: const Text('Task')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(e.toString())),
        ),
        data: (task) {
          _hydrate(task);
          final schema = FormSchema.parse(task.formSchema);
          final isDone = task.status == 'DONE' || task.status == 'CANCELLED';
          final readOnly = isDone || _submitting;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(task: task),
              const SizedBox(height: 20),
              if (task.description != null && task.description!.isNotEmpty) ...[
                const _SectionLabel('Description'),
                const SizedBox(height: 6),
                Text(task.description!),
                const SizedBox(height: 20),
              ],
              const _SectionLabel('Submission'),
              const SizedBox(height: 10),
              if (schema == null)
                Text(
                  'This task has no form. Mark it done when finished.',
                  style: TextStyle(color: Theme.of(context).hintColor),
                )
              else
                FormRenderer(
                  schema: schema,
                  values: _values,
                  readOnly: readOnly,
                  errors: _errors,
                  onChanged: (name, v) {
                    setState(() {
                      if (v == null) {
                        _values.remove(name);
                      } else {
                        _values[name] = v;
                      }
                      _errors.remove(name);
                    });
                  },
                ),
              const SizedBox(height: 16),
              if (_topInfo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _topInfo!,
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              if (_topError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _topError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (!isDone)
                Row(
                  children: [
                    if (task.status == 'PENDING') ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting ? null : () => _markInProgress(task),
                          child: const Text('Start'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: _submitting || !_canSubmit(task)
                            ? null
                            : () => _submit(task),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Text(schema == null ? 'Mark done' : 'Submit'),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    task.status == 'DONE'
                        ? 'This task is complete.'
                        : 'This task was cancelled.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final due = task.dueDate == null
        ? null
        : DateFormat('EEE, d MMM y').format(task.dueDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Chip(
              label: task.status.replaceAll('_', ' '),
              color: _statusColor(task.status),
            ),
            if (task.priority != null)
              _Chip(label: task.priority!, color: Colors.blueGrey),
            if (due != null) _Chip(label: 'Due $due', color: Colors.indigo),
          ],
        ),
        if (task.assignedByName != null) ...[
          const SizedBox(height: 8),
          Text(
            'Assigned by ${task.assignedByName}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ],
    );
  }
}

Color _statusColor(String status) {
  final s = status.toUpperCase();
  if (s.contains('DONE')) return Colors.green;
  if (s.contains('IN_PROGRESS')) return Colors.orange;
  if (s.contains('CANCEL') || s.contains('REJECT')) return Colors.red;
  return Colors.blue;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
