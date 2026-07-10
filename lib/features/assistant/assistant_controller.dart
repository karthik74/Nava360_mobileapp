import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'assistant_models.dart';
import 'assistant_repository.dart';

/// UI state of the active assistant chat.
class AssistantChatState {
  /// Null until the first turn creates a conversation server-side.
  final int? conversationId;
  final String? title;
  final List<AssistantMessage> messages;

  /// Partial assistant reply while streaming ('' = none).
  final String streamingText;

  /// idle | loading | thinking | tool | answering
  final String phase;

  /// Friendly label for the running tool ('Checking attendance…').
  final String? toolLabel;
  final String? error;

  const AssistantChatState({
    this.conversationId,
    this.title,
    this.messages = const [],
    this.streamingText = '',
    this.phase = 'idle',
    this.toolLabel,
    this.error,
  });

  bool get busy => phase != 'idle';

  AssistantChatState copyWith({
    int? conversationId,
    String? title,
    List<AssistantMessage>? messages,
    String? streamingText,
    String? phase,
    String? toolLabel,
    Object? error = _sentinel,
  }) =>
      AssistantChatState(
        conversationId: conversationId ?? this.conversationId,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        streamingText: streamingText ?? this.streamingText,
        phase: phase ?? this.phase,
        toolLabel: toolLabel,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

/// Friendly labels for tool activity shown in the status chip.
const Map<String, String> kAssistantToolLabels = {
  'get_my_attendance': 'Checking your attendance…',
  'get_my_leave_balance': 'Checking your leave balance…',
  'get_my_leave_requests': 'Looking up your leave requests…',
  'get_my_payslips': 'Fetching your payslips…',
  'get_my_pending_approvals': 'Checking your approval inbox…',
  'get_my_team_today': "Checking your team's attendance…",
  'prepare_approval_action': 'Preparing the request for your confirmation…',
  'get_team_member_location': 'Looking up their last known location…',
  'search_employees': 'Searching the directory…',
  'get_my_holidays': 'Looking up holidays…',
  'get_my_assets': 'Checking your assets…',
  'get_company_policies': 'Reading company policies…',
};

class AssistantChatController extends StateNotifier<AssistantChatState> {
  AssistantChatController(this._repo, this._ref)
      : super(const AssistantChatState());

  final AssistantRepository _repo;
  final Ref _ref;
  CancelToken? _cancel;
  String? _lastUserText;

  /// Send one user turn; safe to call only when not busy.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;
    _lastUserText = trimmed;
    state = state.copyWith(
      messages: [
        ...state.messages,
        AssistantMessage(
            role: AssistantMessage.roleUser,
            content: trimmed,
            createdAt: DateTime.now()),
      ],
      phase: 'thinking',
      streamingText: '',
      error: null,
    );
    await _run(trimmed);
  }

  /// Re-send the last user message after a failure.
  Future<void> retry() async {
    final text = _lastUserText;
    if (text == null || state.busy) return;
    state = state.copyWith(phase: 'thinking', streamingText: '', error: null);
    await _run(text);
  }

  Future<void> _run(String text) async {
    _cancel = CancelToken();
    var gotDone = false;
    try {
      await for (final event in _repo.chat(
        conversationId: state.conversationId,
        message: text,
        cancelToken: _cancel,
      )) {
        if (!mounted) return;
        switch (event.name) {
          case 'meta':
            state = state.copyWith(
                conversationId: (event.data['conversationId'] as num?)?.toInt());
          case 'status':
            final s = event.data['state'] as String? ?? 'thinking';
            state = state.copyWith(
              phase: s == 'tool' ? 'tool' : (s == 'answering' ? 'answering' : 'thinking'),
              toolLabel: s == 'tool'
                  ? (kAssistantToolLabels[event.data['tool']] ?? 'Looking that up…')
                  : null,
            );
          case 'token':
            state = state.copyWith(
              phase: 'answering',
              streamingText: state.streamingText + (event.data['t'] as String? ?? ''),
            );
          case 'done':
            gotDone = true;
            state = state.copyWith(
              conversationId: (event.data['conversationId'] as num?)?.toInt() ??
                  state.conversationId,
              title: event.data['title'] as String? ?? state.title,
              messages: [
                ...state.messages,
                AssistantMessage(
                  id: (event.data['messageId'] as num?)?.toInt(),
                  role: AssistantMessage.roleAssistant,
                  content: state.streamingText,
                  cards: AssistantCard.listFrom(event.data['cards']),
                  createdAt: DateTime.now(),
                ),
              ],
              streamingText: '',
              phase: 'idle',
            );
            _ref.invalidate(assistantConversationsProvider);
          case 'error':
            final msg = event.data['message'] as String? ?? 'Something went wrong.';
            // A stream hiccup AFTER the done event is cosmetic — the reply is
            // already complete and persisted; never surface it as an error.
            if (!gotDone && msg != 'disconnected') {
              state = state.copyWith(
                  phase: 'idle', streamingText: '', error: msg);
            }
        }
      }
      // Stream closed without a done/error event (drop mid-answer).
      if (mounted && !gotDone && state.busy) {
        _finishInterrupted();
      }
    } catch (_) {
      // A read failure AFTER the reply completed is cosmetic — the HTTP client
      // can report the server's clean end-of-stream as an error. Only surface
      // it when the turn never finished.
      if (mounted && !gotDone) {
        state = state.copyWith(
            phase: 'idle',
            streamingText: '',
            error: 'Connection lost. Please retry.');
      }
    } finally {
      _cancel = null;
    }
  }

  /// Keep whatever streamed before an interruption as a normal message.
  void _finishInterrupted() {
    final partial = state.streamingText;
    state = state.copyWith(
      messages: partial.isEmpty
          ? state.messages
          : [
              ...state.messages,
              AssistantMessage(
                  role: AssistantMessage.roleAssistant,
                  content: partial,
                  createdAt: DateTime.now()),
            ],
      streamingText: '',
      phase: 'idle',
      error: partial.isEmpty ? 'The answer was interrupted. Please retry.' : null,
    );
  }

  /// Abort the in-flight turn (user pressed stop / left the screen).
  void stop() {
    _cancel?.cancel('user');
    if (state.busy) _finishInterrupted();
  }

  void newChat() {
    stop();
    _lastUserText = null;
    state = const AssistantChatState();
  }

  Future<void> openConversation(int id) async {
    stop();
    state = state.copyWith(phase: 'loading', error: null);
    try {
      final detail = await _repo.conversation(id);
      if (!mounted) return;
      state = AssistantChatState(
        conversationId: detail.id,
        title: detail.title,
        messages: detail.messages,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(phase: 'idle', error: 'Could not open that conversation.');
    }
  }

  /// Thumbs up/down on a persisted assistant reply (tap again to clear).
  Future<void> feedback(AssistantMessage message, String value) async {
    final id = message.id;
    if (id == null) return;
    final next = message.feedback == value ? null : value;
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          identical(m, message) || (m.id != null && m.id == id)
              ? m.copyWith(id: m.id, feedback: next)
              : m,
      ],
    );
    try {
      await _repo.feedback(id, next);
    } catch (_) {
      // Non-fatal; leave the optimistic state.
    }
  }

  @override
  void dispose() {
    _cancel?.cancel('dispose');
    super.dispose();
  }
}

/// NOT autoDispose: the conversation survives navigating away and back,
/// matching the web assistant's persistent dock behaviour.
final assistantChatControllerProvider =
    StateNotifierProvider<AssistantChatController, AssistantChatState>(
        (ref) => AssistantChatController(
            ref.watch(assistantRepositoryProvider), ref));
