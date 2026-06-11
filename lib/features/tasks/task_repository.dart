import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'task_models.dart';
import 'task_template_models.dart';

class TaskRepository {
  TaskRepository(this._api);
  final ApiClient _api;

  /// Active CUSTOMER task templates the field employee can perform.
  Future<List<TaskTemplate>> customerTemplates({String query = ''}) {
    return _api.get<List<TaskTemplate>>(
      '/api/task-templates',
      query: {
        'activeOnly': true,
        'taskType': 'CUSTOMER',
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'size': 100,
      },
      parse: (d) {
        final content = d is List
            ? d
            : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const []);
        return content
            .map((e) => TaskTemplate.fromJson(e as Map<String, dynamic>))
            // Safety net: keep only CUSTOMER templates even if the backend
            // hasn't been redeployed with the taskType query filter yet.
            .where((t) => t.isCustomer)
            .toList();
      },
    );
  }

  Future<List<Task>> listForEmployee(int employeeId, {String? status}) {
    return _api.get<List<Task>>(
      '/api/tasks/employee/$employeeId',
      query: {if (status != null && status.isNotEmpty) 'status': status},
      parse: (d) {
        if (d is List) {
          return d.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
        }
        final content = (d as Map<String, dynamic>)['content'] as List<dynamic>;
        return content
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<Task> get(int id) {
    return _api.get<Task>(
      '/api/tasks/$id',
      parse: (d) => Task.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Move a task to [status]. When the employee is completing the task we also
  /// send the captured GPS coordinates (and optional reverse-geocoded address)
  /// so the backend can record where the work was finished.
  Future<Task> updateStatus(
    int id,
    String status, {
    double? lat,
    double? lng,
    String? address,
  }) {
    return _api.patch<Task>(
      '/api/tasks/$id/status',
      body: {
        'status': status,
        if (lat != null) 'completionLat': lat,
        if (lng != null) 'completionLng': lng,
        if (address != null && address.isNotEmpty) 'completionAddress': address,
      },
      parse: (d) => Task.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Submit the filled form. [formResponseJson] is a JSON-encoded
  /// `Map<String, dynamic>` produced by the form renderer. Optional GPS
  /// coordinates geo-tag where the form was submitted from.
  Future<Task> submitFormResponse(
    int id,
    String formResponseJson, {
    double? lat,
    double? lng,
    String? address,
  }) {
    return _api.patch<Task>(
      '/api/tasks/$id/form-response',
      body: {
        'formResponse': formResponseJson,
        if (lat != null) 'completionLat': lat,
        if (lng != null) 'completionLng': lng,
        if (address != null && address.isNotEmpty) 'completionAddress': address,
      },
      parse: (d) => Task.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Logged-in employee's task summary counts.
  Future<TaskDashboard> dashboard() {
    return _api.get<TaskDashboard>(
      '/api/tasks/dashboard',
      parse: (d) => TaskDashboard.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Status / audit trail for a task, newest first.
  Future<List<TaskHistoryEntry>> history(int id) {
    return _api.get<List<TaskHistoryEntry>>(
      '/api/tasks/$id/history',
      parse: (d) => (d as List? ?? const [])
          .map((e) => TaskHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Discussion thread for a task.
  Future<List<TaskComment>> comments(int id) {
    return _api.get<List<TaskComment>>(
      '/api/tasks/$id/comments',
      parse: (d) => (d as List? ?? const [])
          .map((e) => TaskComment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Post a comment to a task's thread. Requires the `TASK_COMMENT` authority
  /// server-side; callers should surface a permission error if thrown.
  Future<TaskComment> addComment(int id, String text) {
    return _api.post<TaskComment>(
      '/api/tasks/$id/comments',
      body: {'commentText': text},
      parse: (d) => TaskComment.fromJson(d as Map<String, dynamic>),
    );
  }
}

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(apiClientProvider)),
);
