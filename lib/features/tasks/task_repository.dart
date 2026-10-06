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
        // Perform picker: targeting rules apply even to template managers,
        // matching the server-side guard at task creation.
        'applicableOnly': true,
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

  /// Active INTERNAL task templates the employee can raise for themselves
  /// (the "create my own task" flow on the My Tasks screen).
  Future<List<TaskTemplate>> individualTemplates({String query = ''}) {
    return _api.get<List<TaskTemplate>>(
      '/api/task-templates',
      query: {
        'activeOnly': true,
        'taskType': 'INTERNAL',
        // Self-task picker: targeting rules apply even to template managers,
        // matching the server-side guard at task creation.
        'applicableOnly': true,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'size': 100,
      },
      parse: (d) {
        final content = d is List
            ? d
            : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const []);
        return content
            .map((e) => TaskTemplate.fromJson(e as Map<String, dynamic>))
            // Safety net: keep only INTERNAL templates even if the backend
            // hasn't been redeployed with the taskType query filter yet.
            .where((t) => !t.isCustomer)
            .toList();
      },
    );
  }

  /// Upper bound on pages walked by [_allPages]: 25 × 200 = 5,000 rows, far
  /// above any real list, so a runaway server page count can't spin forever.
  static const _maxPages = 25;

  /// Walks a paged endpoint (`page`/`size` → `{content, last}`) and returns
  /// every row. The task screens bucket, count and filter client-side, so they
  /// need the WHOLE list — a single capped page silently hid everything older
  /// than the cap (a manager with 600+ hierarchy tasks saw only the newest 200
  /// and "couldn't find" a task that was really there). A bare list response
  /// (older servers) is returned as-is.
  Future<List<T>> _allPages<T>(
    String path, {
    required Map<String, dynamic> query,
    required T Function(Map<String, dynamic>) fromJson,
    int size = 200,
  }) async {
    final out = <T>[];
    for (var page = 0; page < _maxPages; page++) {
      final last = await _api.get<bool>(
        path,
        // A fixed, unique sort key keeps page boundaries stable: without it rows
        // that tie on the server's default order can repeat or vanish between
        // pages (hundreds of imported tasks share one created-at second).
        query: {'sort': 'id,desc', ...query, 'page': page, 'size': size},
        parse: (d) {
          if (d is List) {
            out.addAll(d.map((e) => fromJson(e as Map<String, dynamic>)));
            return true;
          }
          final m = d as Map<String, dynamic>;
          final content = m['content'] as List<dynamic>? ?? const [];
          out.addAll(content.map((e) => fromJson(e as Map<String, dynamic>)));
          final isLast = m['last'];
          if (isLast is bool) return isLast || content.isEmpty;
          final totalPages = m['totalPages'];
          if (totalPages is num) return page + 1 >= totalPages;
          return content.length < size;
        },
      );
      if (last) break;
    }
    return out;
  }

  /// Manager view: assignments of the caller's team (server scopes to the
  /// reporting hierarchy / assigned branches). Every page is fetched; the
  /// screen buckets by status client-side so counts stay consistent.
  Future<List<TeamTaskAssignment>> teamTasks({
    int? employeeId,
    String? status,
    int size = 300,
  }) {
    return _allPages<TeamTaskAssignment>(
      '/api/tasks/team',
      query: {
        if (employeeId != null) 'employeeId': employeeId,
        if (status != null) 'status': status,
      },
      fromJson: TeamTaskAssignment.fromJson,
      size: size,
    );
  }

  /// Active INTERNAL task forms a manager may assign to their team. Not the
  /// self-create list: assign-only templates are included, and targeting rules
  /// are applied to the caller by the server (template admins see all).
  Future<List<TaskTemplate>> assignableTemplates({String query = ''}) {
    return _api.get<List<TaskTemplate>>(
      '/api/task-templates',
      query: {
        'activeOnly': true,
        'taskType': 'INTERNAL',
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'size': 100,
      },
      parse: (d) {
        final content = d is List
            ? d
            : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const []);
        return content
            .map((e) => TaskTemplate.fromJson(e as Map<String, dynamic>))
            .where((t) => !t.isCustomer)
            .toList();
      },
    );
  }

  /// Manager assigns a template to team members: one task per employee, all
  /// recorded as assigned by the caller (the server enforces that the
  /// employees sit inside the caller's reporting hierarchy). Returns the
  /// created tasks.
  Future<List<Task>> assignTemplate(
    int templateId, {
    required List<int> employeeIds,
    int? assignedById,
    String? priority,
    String? dueDate,
    String? description,
    String? assignedFieldValues,
  }) {
    return _api.post<List<Task>>(
      '/api/task-templates/$templateId/assign',
      body: {
        'employeeIds': employeeIds,
        if (assignedById != null) 'assignedById': assignedById,
        if (priority != null) 'priority': priority,
        if (dueDate != null) 'dueDate': dueDate,
        if (description != null) 'description': description,
        if (assignedFieldValues != null)
          'assignedFieldValues': assignedFieldValues,
      },
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Raise an INTERNAL task for the calling employee from a template. The
  /// backend sets both the assignee and assigner to the current employee, so
  /// the task lands in their own "My Tasks" list (in TODO). Returns the created
  /// task, which the caller then performs via the task detail screen.
  Future<Task> createSelfTask({
    required int templateId,
    String? title,
    String? description,
    String? priority,
    String? startDate, // ISO yyyy-MM-dd
    String? dueDate, // ISO yyyy-MM-dd
    String? dueTime, // HH:mm
  }) {
    return _api.post<Task>(
      '/api/tasks/self-tasks',
      body: {
        'templateId': templateId,
        if (title != null && title.isNotEmpty) 'title': title,
        if (description != null && description.isNotEmpty) 'description': description,
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        if (startDate != null && startDate.isNotEmpty) 'startDate': startDate,
        if (dueDate != null && dueDate.isNotEmpty) 'dueDate': dueDate,
        if (dueTime != null && dueTime.isNotEmpty) 'dueTime': dueTime,
      },
      parse: (d) => Task.fromJson(d as Map<String, dynamic>),
    );
  }

  /// The signed-in employee's tasks: their own plus hierarchy-performable
  /// tasks of their reportees (server-side). The endpoint is paged, so every
  /// page is walked — the screen's status/date/priority filters and counts
  /// need the whole history, and a manager with many reportees easily has
  /// more than one page. The title search goes to the SERVER so it matches
  /// all tasks, not only the loaded ones.
  Future<List<Task>> listForEmployee(int employeeId, {String? status, String? q}) {
    return _allPages<Task>(
      '/api/tasks/employee/$employeeId',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
      fromJson: Task.fromJson,
    );
  }

  List<TeamTaskAssignment> _assignments(dynamic d) {
    final content = d is List
        ? d
        : ((d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const []);
    return content
        .map((e) => TeamTaskAssignment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Submissions waiting for the caller's review: tasks naming them as reviewer, plus
  /// — on templates with "show review to hierarchy" — their reportees' tasks (TASK_REVIEW).
  Future<List<TeamTaskAssignment>> pendingReview({int size = 100}) {
    return _api.get<List<TeamTaskAssignment>>(
      '/api/tasks/pending-review',
      query: {'page': 0, 'size': size},
      parse: _assignments,
    );
  }

  /// Review-required submissions of employees in the caller's branches (TASK_REVIEW_BRANCH).
  /// [view] is PENDING | APPROVED | REJECTED | ALL.
  Future<List<TeamTaskAssignment>> branchReview({String view = 'PENDING', String? q, int size = 100}) {
    return _api.get<List<TeamTaskAssignment>>(
      '/api/tasks/branch-review',
      query: {
        'view': view,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'page': 0,
        'size': size,
      },
      parse: _assignments,
    );
  }

  /// Approve / reject as the named reviewer or a manager above the assignee.
  Future<void> approveAssignment(int assignmentId) =>
      _api.put<void>('/api/task-assignments/$assignmentId/approve', parse: (_) {});

  Future<void> rejectAssignment(int assignmentId, String reason) => _api.put<void>(
        '/api/task-assignments/$assignmentId/reject',
        body: {'reason': reason},
        parse: (_) {},
      );

  /// Branch review desk actions (TASK_REVIEW_BRANCH).
  Future<void> branchApprove(int assignmentId, {String? remarks}) => _api.post<void>(
        '/api/tasks/branch-review/$assignmentId/approve',
        body: {'remarks': (remarks == null || remarks.trim().isEmpty) ? null : remarks.trim()},
        parse: (_) {},
      );

  Future<void> branchReject(int assignmentId, String reason) => _api.post<void>(
        '/api/tasks/branch-review/$assignmentId/reject',
        body: {'reason': reason},
        parse: (_) {},
      );

  /// Correct the submitted form details; the task stays in review.
  Future<void> branchUpdateForm(int assignmentId, String formResponseJson) => _api.put<void>(
        '/api/tasks/branch-review/$assignmentId/form-response',
        body: {'formResponse': formResponseJson},
        parse: (_) {},
      );

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
