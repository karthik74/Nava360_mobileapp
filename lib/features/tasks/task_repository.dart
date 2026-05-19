import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'task_models.dart';

class TaskRepository {
  TaskRepository(this._api);
  final ApiClient _api;

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

  Future<Task> updateStatus(int id, String status) {
    return _api.patch<Task>(
      '/api/tasks/$id/status',
      body: {'status': status},
      parse: (d) => Task.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Submit the filled form. [formResponseJson] is a JSON-encoded
  /// `Map<String, dynamic>` produced by the form renderer.
  Future<Task> submitFormResponse(int id, String formResponseJson) {
    return _api.patch<Task>(
      '/api/tasks/$id/form-response',
      body: {'formResponse': formResponseJson},
      parse: (d) => Task.fromJson(d as Map<String, dynamic>),
    );
  }
}

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(apiClientProvider)),
);
