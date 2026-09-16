import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'assistant_models.dart';

/// API client for `/api/assistant`. The chat call streams Server-Sent Events
/// (named events with single-line JSON payloads) which [chat] surfaces as an
/// [AssistantEvent] stream; everything else is the normal ApiResponse shape.
class AssistantRepository {
  AssistantRepository(this._api);
  final ApiClient _api;

  /// One chat turn. Emits meta/status/token/done/error events until the
  /// server closes the stream. Cancel via [cancelToken] (barge-in, screen
  /// dispose) — cancellation is not an error.
  Stream<AssistantEvent> chat({
    int? conversationId,
    required String message,
    CancelToken? cancelToken,
  }) async* {
    final Response<ResponseBody> res;
    try {
      res = await _api.raw.post<ResponseBody>(
        '/api/assistant/chat',
        data: {
          if (conversationId != null) 'conversationId': conversationId,
          'message': message,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          // The stream can be silent for >30s while tools run server-side —
          // don't let the client's default idle timeout kill the answer.
          receiveTimeout: const Duration(minutes: 3),
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      yield AssistantEvent('error', {'message': _dioMessage(e)});
      return;
    }

    // SSE framing: "event: <name>" + one or more "data: <json>" lines,
    // dispatched on the blank separator line.
    String eventName = 'message';
    final dataLines = <String>[];
    // Once done/error has been delivered the turn is over; a later read failure
    // is just the server's clean end-of-stream surfacing as an exception, and
    // must never be reported as "Connection lost".
    var sawTerminal = false;
    final lines = res.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    try {
      await for (final line in lines) {
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            final event = _decode(eventName, dataLines.join('\n'));
            if (event != null) {
              if (event.name == 'done' || event.name == 'error') sawTerminal = true;
              yield event;
            }
          }
          eventName = 'message';
          dataLines.clear();
          continue;
        }
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        }
      }
      // Flush a trailing event if the stream ended without a final blank line.
      if (dataLines.isNotEmpty) {
        final event = _decode(eventName, dataLines.join('\n'));
        if (event != null) yield event;
      }
    } catch (e) {
      final cancelled = e is DioException && CancelToken.isCancel(e);
      if (!sawTerminal && !cancelled) {
        yield AssistantEvent('error', {
          'message': e is DioException
              ? _dioMessage(e)
              : 'Connection lost. Please retry.',
        });
      }
    }
  }

  AssistantEvent? _decode(String name, String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return AssistantEvent(name, decoded);
    } catch (_) {
      // Malformed frame — skip rather than kill the stream.
    }
    return null;
  }

  static String _dioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Network timeout. Check your connection.';
    }
    return 'Could not reach the assistant. Please try again.';
  }

  // ── Conversation management ─────────────────────────────────────────────

  Future<List<AssistantConversation>> conversations() {
    return _api.get<List<AssistantConversation>>(
      '/api/assistant/conversations',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => AssistantConversation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<AssistantConversationDetail> conversation(int id) {
    return _api.get<AssistantConversationDetail>(
      '/api/assistant/conversations/$id',
      parse: (d) =>
          AssistantConversationDetail.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<AssistantConversation> updateConversation(int id,
      {String? title, bool? pinned}) {
    return _api.patch<AssistantConversation>(
      '/api/assistant/conversations/$id',
      body: {
        if (title != null) 'title': title,
        if (pinned != null) 'pinned': pinned,
      },
      parse: (d) => AssistantConversation.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> deleteConversation(int id) async {
    await _api.raw.delete('/api/assistant/conversations/$id');
  }

  /// Privacy: wipe the caller's entire assistant history.
  Future<void> deleteAllConversations() async {
    await _api.raw.delete('/api/assistant/conversations');
  }

  /// Execute an approve/reject the user confirmed on a chat card. Plain REST —
  /// no LLM in this path; the backend re-verifies the request is genuinely
  /// waiting on the caller before performing the review.
  Future<String> executeApproval({
    required String kind, // LEAVE | REGULARIZATION
    required int id,
    required bool approve,
    String? comment,
  }) {
    return _api.post<String>(
      '/api/assistant/actions/execute',
      body: {
        'kind': kind,
        'id': id,
        'approve': approve,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      },
      parse: (d) => (d as Map<String, dynamic>?)?['message'] as String? ?? 'Done',
    );
  }

  /// feedback: 'UP' | 'DOWN' | null (clear).
  Future<void> feedback(int messageId, String? feedback) {
    return _api.post<void>(
      '/api/assistant/messages/$messageId/feedback',
      body: {'feedback': feedback},
      parse: (_) {},
    );
  }
}

final assistantRepositoryProvider =
    Provider((ref) => AssistantRepository(ref.watch(apiClientProvider)));

/// Conversation list for the history sheet (pinned first, newest first).
final assistantConversationsProvider = FutureProvider.autoDispose<
    List<AssistantConversation>>((ref) {
  return ref.watch(assistantRepositoryProvider).conversations();
});
