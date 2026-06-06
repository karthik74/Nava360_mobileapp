import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_thread_screen.dart';

/// Opens a chat thread by conversation id — used for notification deep-links
/// (`/chats/:id`). Resolves the conversation from the loaded list, then shows
/// the existing [ChatThreadScreen]. Shows a spinner while the list loads and a
/// graceful fallback if the conversation can't be found.
class ChatThreadByIdScreen extends ConsumerWidget {
  const ChatThreadByIdScreen({super.key, required this.conversationId});

  final int conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convs = ref.watch(conversationsProvider);
    return convs.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(child: Text('Could not open chat.\n$e', textAlign: TextAlign.center)),
      ),
      data: (list) {
        Conversation? conv;
        for (final c in list) {
          if (c.id == conversationId) {
            conv = c;
            break;
          }
        }
        if (conv == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chat')),
            body: const Center(child: Text('Conversation not found.')),
          );
        }
        return ChatThreadScreen(conversation: conv);
      },
    );
  }
}
