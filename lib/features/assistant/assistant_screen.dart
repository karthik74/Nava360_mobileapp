import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'assistant_controller.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';
import 'assistant_voice_controller.dart';
import 'assistant_voice_sheet.dart';
import 'voice/voice_conversation_screen.dart';
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

  /// Opens the ChatGPT-style hands-free voice conversation (full screen).
  Future<void> _openVoiceConversation() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const VoiceConversationScreen(),
    ));
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

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const AssistantVoiceSettingsSheet(),
    );
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
        toolbarHeight: 60,
        titleSpacing: 4,
        // Gradient header (flexibleSpace) → white content, light status icons.
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        flexibleSpace: const ProDeepSurface(
          padding: EdgeInsets.zero,
          child: SizedBox.expand(),
        ),
        title: Row(
          children: [
            const _BotMark(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.live,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'AI assistant',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    state.title ?? '$productName Assistant',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.35,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ProHeroIconButton(
            tooltip: 'Voice chat',
            icon: Icons.graphic_eq_rounded,
            onTap: _openVoiceConversation,
          ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 10,
                  child: _ToolButton(
                    icon: Icons.add_comment_outlined,
                    label: 'New chat',
                    onTap: () => ref
                        .read(assistantChatControllerProvider.notifier)
                        .newChat(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 9,
                  child: _ToolButton(
                    icon: Icons.history_rounded,
                    label: 'History',
                    onTap: () => _openHistory(context),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 13,
                  child: _ToolButton(
                    icon: Icons.tune_rounded,
                    label: 'Voice settings',
                    onTap: _openSettings,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
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
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppErrorPanel(
                                message: state.error!,
                                onRetry: () => ref
                                    .read(assistantChatControllerProvider
                                        .notifier)
                                    .retry(),
                              ),
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

/// White squircle with a lime ring and the brand sparkle (header identity).
class _BotMark extends StatelessWidget {
  const _BotMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        // Flutter paints later shadows on top: lime ring first, then the deep
        // gap that separates it from the squircle.
        boxShadow: [
          BoxShadow(
              color: AppColors.live.withValues(alpha: 0.85), spreadRadius: 3.5),
          BoxShadow(color: AppColors.deep, spreadRadius: 2),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.primary),
    );
  }
}

/// Translucent tool button in the deep header (New chat / History / …).
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: const Color(0xE0FFFFFF)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xE0FFFFFF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});
  final void Function(String prompt) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.deep.withValues(alpha: 0.5),
                  blurRadius: 28,
                  spreadRadius: -14,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: const ProDeepSurface(
              radius: 20,
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: 64,
                height: 64,
                child: Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 30),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Hi! Ask me anything about your HR',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            height: 1.27,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Attendance, leave, salary, approvals, holidays, policies — in '
            'English, हिन्दी, ಕನ್ನಡ, தமிழ், తెలుగు, മലയാളം, मराठी or বাংলা.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
          ),
        ),
        const SizedBox(height: 22),
        AssistantSuggestions(onPick: onPick),
      ],
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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                  style: const TextStyle(fontSize: 15, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Ask about leave, salary, attendance…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFDBE3E5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFDBE3E5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          BorderSide(color: AppColors.primary, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!busy) ...[
                _RoundButton(
                  tooltip: 'Speak',
                  icon: Icons.mic_none_rounded,
                  background: const Color(0xFFEEF3F4),
                  foreground: AppColors.primary,
                  onTap: onMic,
                ),
                const SizedBox(width: 8),
              ],
              busy
                  ? _RoundButton(
                      tooltip: 'Stop',
                      icon: Icons.stop_rounded,
                      background: AppColors.danger,
                      foreground: Colors.white,
                      onTap: onStop,
                    )
                  : _RoundButton(
                      tooltip: 'Send',
                      icon: Icons.arrow_upward_rounded,
                      background: AppColors.primary,
                      foreground: Colors.white,
                      onTap: onSend,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 46px round composer button (mic / send / stop).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 21, color: foreground),
          ),
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
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assistantConversationsProvider);
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('Conversations',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.35,
                        color: AppColors.ink)),
              ),
              _SheetClose(onTap: () => Navigator.of(context).pop()),
            ],
          ),
          const SizedBox(height: 12),
          ProSearchField(
            controller: _search,
            hint: 'Search conversations…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Align(
                alignment: Alignment.topCenter,
                child: AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(assistantConversationsProvider),
                ),
              ),
              data: (all) {
                final rows = _query.isEmpty
                    ? all
                    : all
                        .where((c) =>
                            (c.title ?? '').toLowerCase().contains(_query))
                        .toList();
                if (rows.isEmpty) {
                  return ListView(
                    children: const [
                      ProEmpty(
                        icon: Icons.forum_outlined,
                        title: 'No conversations yet.',
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    ProListGroup(
                      children: [
                        for (final c in rows) _ConversationTile(c: c),
                      ],
                    ),
                  ],
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
    return ProListRow(
      leading: ProIconWell(
        icon: Icons.chat_bubble_outline_rounded,
        color: c.pinned ? AppColors.primary : null,
      ),
      title: c.title ?? 'New conversation',
      subtitle: c.updatedAt == null
          ? null
          : DateFormat('d MMM, h:mm a').format(c.updatedAt!),
      chevron: false,
      onTap: () {
        Navigator.of(context).pop();
        ref
            .read(assistantChatControllerProvider.notifier)
            .openConversation(c.id);
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: c.pinned ? 'Unpin' : 'Pin',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              c.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 18,
              color: c.pinned ? AppColors.primary : AppColors.muted,
            ),
            onPressed: () async {
              await repo.updateConversation(c.id, pinned: !c.pinned);
              ref.invalidate(assistantConversationsProvider);
            },
          ),
          IconButton(
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.muted),
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
                            backgroundColor: AppColors.dangerTint,
                            foregroundColor: AppColors.danger),
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

/// 40×5 drag handle for the white bottom sheets.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFC6D3D6),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}

/// 40px light close button for sheet headers.
class _SheetClose extends StatelessWidget {
  const _SheetClose({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close',
      child: Material(
        color: const Color(0xFFF1F4F5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.close_rounded, size: 20, color: AppColors.inkSoft),
          ),
        ),
      ),
    );
  }
}
