import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'helpdesk_models.dart';

/// API layer for the mobile helpdesk (`/api/helpdesk/tickets`).
class HelpdeskRepository {
  HelpdeskRepository(this._api);
  final ApiClient _api;

  /// scope = mine | assigned | team | all.
  Future<List<HdTicketSummary>> list(
    String scope, {
    String? status,
    String? q,
    int page = 0,
    int size = 20,
  }) {
    return _api.get<List<HdTicketSummary>>(
      '/api/helpdesk/tickets/$scope',
      query: {
        'page': page,
        'size': size,
        if (status != null) 'status': status,
        if (q != null && q.isNotEmpty) 'q': q,
      },
      parse: (d) {
        final list = (d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
        return list.map((e) => HdTicketSummary.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
  }

  Future<HdTicket> get(int id) => _api.get<HdTicket>(
        '/api/helpdesk/tickets/$id',
        parse: (d) => HdTicket.fromJson(d as Map<String, dynamic>),
      );

  Future<HdFormVersion?> getActiveForm(int ticketTypeId) => _api.get<HdFormVersion?>(
        '/api/helpdesk/forms/active',
        query: {'ticketTypeId': ticketTypeId},
        parse: (d) => d == null ? null : HdFormVersion.fromJson(d as Map<String, dynamic>),
      );

  Future<HdTicket> create({
    required String title,
    String? description,
    String? category,
    int? categoryId,
    int? ticketTypeId,
    Map<String, dynamic>? formResponse,
    required String priority,
  }) {
    return _api.post<HdTicket>(
      '/api/helpdesk/tickets',
      body: {
        'title': title,
        if (description != null && description.isNotEmpty) 'description': description,
        if (categoryId == null && category != null && category.isNotEmpty) 'category': category,
        if (categoryId != null) 'categoryId': categoryId,
        if (ticketTypeId != null) 'ticketTypeId': ticketTypeId,
        if (formResponse != null && formResponse.isNotEmpty) 'formResponse': formResponse,
        'priority': priority,
        'deviceInfo': 'mobile',
        'operatingSystem': 'mobile',
        'appVersion': 'mobile',
      },
      parse: (d) => HdTicket.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<HdCategory>> listCategories() => _api.get<List<HdCategory>>(
        '/api/helpdesk/config/categories',
        query: {'activeOnly': true},
        parse: (d) => (d as List).map((e) => HdCategory.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<List<HdTicketType>> listTicketTypes(int categoryId) => _api.get<List<HdTicketType>>(
        '/api/helpdesk/config/ticket-types',
        query: {'activeOnly': true, 'categoryId': categoryId},
        parse: (d) => (d as List).map((e) => HdTicketType.fromJson(e as Map<String, dynamic>)).toList(),
      );

  // ── Knowledge Base (Phase 5) ──
  Future<List<HdKbArticleSummary>> browseArticles({String? q}) => _api.get<List<HdKbArticleSummary>>(
        '/api/helpdesk/kb/articles',
        query: {'size': 30, if (q != null && q.isNotEmpty) 'q': q},
        parse: (d) {
          final list = (d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
          return list.map((e) => HdKbArticleSummary.fromJson(e as Map<String, dynamic>)).toList();
        },
      );

  Future<HdKbArticle> getArticle(int id) => _api.get<HdKbArticle>(
        '/api/helpdesk/kb/articles/$id',
        parse: (d) => HdKbArticle.fromJson(d as Map<String, dynamic>),
      );

  Future<void> rateArticle(int id, bool helpful) => _api.post<void>(
        '/api/helpdesk/kb/articles/$id/rate',
        query: {'helpful': helpful},
        parse: (_) {},
      );

  Future<List<HdKbSuggestion>> suggestArticles(String text) => _api.get<List<HdKbSuggestion>>(
        '/api/helpdesk/kb/suggest',
        query: {'text': text, 'limit': 5},
        parse: (d) => (d as List).map((e) => HdKbSuggestion.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<HdTicket> addComment(int id, String body, {bool internal = false}) {
    return _api.post<HdTicket>(
      '/api/helpdesk/tickets/$id/comments',
      body: {'body': body, 'internalNote': internal},
      parse: (d) => HdTicket.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<HdTicket> workflowAction(int id, String action, {String? note, int? reassignEmployeeId}) {
    return _api.patch<HdTicket>(
      '/api/helpdesk/tickets/$id/workflow-action',
      body: {
        'action': action,
        if (note != null && note.isNotEmpty) 'note': note,
        if (reassignEmployeeId != null) 'reassignEmployeeId': reassignEmployeeId,
      },
      parse: (d) => HdTicket.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<HdTicket> updateStatus(int id, String status, {String? comment}) {
    return _api.patch<HdTicket>(
      '/api/helpdesk/tickets/$id/status',
      body: {'status': status, if (comment != null && comment.isNotEmpty) 'comment': comment},
      parse: (d) => HdTicket.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Scoped dashboard metrics (Phase 6). Backend restricts to the caller's
  /// reporting hierarchy / branch scope.
  Future<HdDashboard> dashboard({String? from, String? to}) {
    return _api.get<HdDashboard>(
      '/api/helpdesk/reports/dashboard',
      query: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
      parse: (d) => HdDashboard.fromJson(d as Map<String, dynamic>),
    );
  }
}

final helpdeskRepositoryProvider = Provider<HelpdeskRepository>(
  (ref) => HelpdeskRepository(ref.watch(apiClientProvider)),
);

/// Tickets for a scope tab (mine/assigned). Family keyed by scope.
final helpdeskTicketsProvider =
    FutureProvider.family.autoDispose<List<HdTicketSummary>, String>(
  (ref, scope) => ref.watch(helpdeskRepositoryProvider).list(scope),
);

final helpdeskTicketProvider =
    FutureProvider.family.autoDispose<HdTicket, int>(
  (ref, id) => ref.watch(helpdeskRepositoryProvider).get(id),
);

/// Scoped helpdesk dashboard (Phase 6).
final helpdeskDashboardProvider =
    FutureProvider.autoDispose<HdDashboard>(
  (ref) => ref.watch(helpdeskRepositoryProvider).dashboard(),
);
