import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/branding.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'assistant_controller.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';
import 'assistant_voice_controller.dart';
import 'assistant_voice_sheet.dart';
import 'assistant_widgets.dart';

/// The AI-assistant chat page (route /assistant). Voice arrives in Phase 2 —
/// this page already reserves the mic slot in the composer.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = preset ?? _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(assistantChatControllerProvider.notifier).send(text);
    _scrollToBottom();
  }

  Future<void> _openVoice() async {
    ref.read(assistantVoiceControllerProvider.notifier).startListening();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const AssistantVoiceSheet(),
    );
    // Sheet dismissed by swipe/tap-outside while still listening → cancel.
    final phase = ref.read(assistantVoiceControllerProvider).phase;
    if (phase == VoicePhase.listening || phase == VoicePhase.confirming) {
      ref.read(assistantVoiceControllerProvider.notifier).cancelListening();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantChatControllerProvider);
    final productName = ref.watch(brandingProvider).productName;
    // Keep the list pinned to the bottom while tokens stream in.
    ref.listen(assistantChatControllerProvider, (prev, next) {
      if (prev?.streamingText != next.streamingText ||
          prev?.messages.length != next.messages.length) {
        _scrollToBottom();
      }
    });
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0.5,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                state.title ?? '$productName Assistant',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            onPressed: () =>
                ref.read(assistantChatControllerProvider.notifier).newChat(),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded, size: 21),
            onPressed: () => _openHistory(context),
          ),
          IconButton(
            tooltip: 'Voice settings',
            icon: const Icon(Icons.tune_rounded, size: 20),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => const AssistantVoiceSettingsSheet(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.phase == 'loading'
                ? const Center(child: CircularProgressIndicator())
                : state.messages.isEmpty && state.streamingText.isEmpty
                    ? _EmptyState(onPick: (s) => _send(s))
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        children: [
                          for (final m in state.messages)
                            AssistantChatBubble(
                              message: m,
                              onCopy: () {
                                Clipboard.setData(
                                    ClipboardData(text: m.content));
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copied')));
                              },
                              onFeedback: m.isUser || m.id == null
                                  ? null
                                  : (v) => ref
                                      .read(assistantChatControllerProvider
                                          .notifier)
                                      .feedback(m, v),
                            ),
                          if (state.phase == 'thinking' ||
                              state.phase == 'tool')
                            AssistantThinkingIndicator(label: state.toolLabel),
                          if (state.streamingText.isNotEmpty)
                            AssistantChatBubble(
                              message: const AssistantMessage(
                                      role: AssistantMessage.roleAssistant,
                                      content: '')
                                  .copyWith(content: state.streamingText),
                              streaming: true,
                            ),
                          if (state.error != null)
                            _ErrorRow(
                              message: state.error!,
                              onRetry: () => ref
                                  .read(
                                      assistantChatControllerProvider.notifier)
                                  .retry(),
                            ),
                        ],
                      ),
          ),
          _Composer(
            controller: _input,
            busy: state.busy,
            onSend: _send,
            onMic: _openVoice,
            onStop: () =>
                ref.read(assistantChatControllerProvider.notifier).stop(),
          ),
        ],
      ),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HistorySheet(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});
  final void Function(String prompt) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 30),
        ),
        const SizedBox(height: 16),
        const Text(
          'Hi! Ask me anything about your HR',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        const Text(
          'Attendance, leave, salary, approvals, holidays, policies — in '
          'English, हिन्दी, ಕನ್ನಡ, தமிழ், తెలుగు, മലയാളം, मराठी or বাংলা.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        AssistantSuggestions(onPick: onPick),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onMic,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask about leave, salary, attendance…',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppColors.hairline),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (!busy)
              IconButton(
                tooltip: 'Speak',
                onPressed: onMic,
                icon: Icon(Icons.mic_rounded,
                    color: AppColors.primary, size: 24),
              ),
            const SizedBox(width: 2),
            busy
                ? IconButton.filled(
                    tooltip: 'Stop',
                    style: IconButton.styleFrom(
                        backgroundColor: AppColors.danger),
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded,
                        color: Colors.white, size: 20),
                  )
                : IconButton.filled(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    onPressed: onSend,
                    icon: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 20),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Conversation history: search, open, pin, delete.
class _HistorySheet extends ConsumerStatefulWidget {
  const _HistorySheet();

  @override
  ConsumerState<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<_HistorySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assistantConversationsProvider);
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conversations',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Search conversations…',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(assistantConversationsProvider),
              ),
              data: (all) {
                final rows = _query.isEmpty
                    ? all
                    : all
                        .where((c) =>
                            (c.title ?? '').toLowerCase().contains(_query))
                        .toList();
                if (rows.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.forum_outlined,
                    message: 'No conversations yet.',
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _ConversationTile(c: rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.c});
  final AssistantConversation c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(assistantRepositoryProvider);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                ref
                    .read(assistantChatControllerProvider.notifier)
                    .openConversation(c.id);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title ?? 'New conversation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                    if (c.updatedAt != null)
                      Text(
                        DateFormat('d MMM, h:mm a').format(c.updatedAt!),
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: c.pinned ? 'Unpin' : 'Pin',
            icon: Icon(
              c.pinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              size: 17,
              color: c.pinned ? AppColors.primary : AppColors.muted,
            ),
            onPressed: () async {
              await repo.updateConversation(c.id, pinned: !c.pinned);
              ref.invalidate(assistantConversationsProvider);
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 17, color: AppColors.muted),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete conversation?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) {
                await repo.deleteConversation(c.id);
                ref.invalidate(assistantConversationsProvider);
                final active = ref.read(assistantChatControllerProvider);
                if (active.conversationId == c.id) {
                  ref
                      .read(assistantChatControllerProvider.notifier)
                      .newChat();
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
