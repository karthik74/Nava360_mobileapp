import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../tasks/task_models.dart';
import 'customer_models.dart';

/// Pulls the `content` list out of a paged `ApiResponse<PageResponse<T>>`
/// `data` payload, tolerating a bare list for forward-compatibility.
List<Map<String, dynamic>> _pageContent(dynamic d) {
  if (d is List) return d.cast<Map<String, dynamic>>();
  final content = (d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
  return content.cast<Map<String, dynamic>>();
}

class CustomerRepository {
  CustomerRepository(this._api);
  final ApiClient _api;

  /// Search / list customers visible to the caller (branch-scoped server-side).
  Future<List<Customer>> search(String query, {int page = 0, int size = 20}) {
    return _api.get<List<Customer>>(
      '/api/customers',
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(Customer.fromJson).toList(),
    );
  }

  Future<Customer> get(int id) {
    return _api.get<Customer>(
      '/api/customers/$id',
      parse: (d) => Customer.fromJson(d as Map<String, dynamic>),
    );
  }

  /// All tasks raised for a customer (optionally filtered by status).
  Future<List<Task>> tasksForCustomer(int customerId, {String? status, int size = 100}) {
    return _api.get<List<Task>>(
      '/api/customers/$customerId/tasks',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(Task.fromJson).toList(),
    );
  }

  /// Raise a customer task for the calling employee from a template. Returns the
  /// created task (in TODO) which the caller then performs via the task screen.
  Future<Task> createSelfTask(
    int customerId, {
    required int templateId,
    String? title,
    String? description,
    String? priority,
    String? dueDate, // ISO yyyy-MM-dd
  }) {
    return _api.post<Task>(
      '/api/customers/$customerId/self-tasks',
      body: {
        'templateId': templateId,
        if (title != null && title.isNotEmpty) 'title': title,
        if (description != null && description.isNotEmpty) 'description': description,
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        if (dueDate != null && dueDate.isNotEmpty) 'dueDate': dueDate,
      },
      parse: (d) => Task.fromJson(d as Map<String, dynamic>),
    );
  }
}

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(apiClientProvider)),
);
