import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'assistant_controller.dart';
import 'assistant_language.dart';
import 'assistant_repository.dart';
import 'assistant_voice_controller.dart';
import 'assistant_voice_settings.dart';

/// Full-width voice sheet: animated mic with sound-reactive wave rings, the
/// live transcript, the polite low-confidence confirmation, and a language
/// picker. Opens listening; closes itself once a turn is sent.
class AssistantVoiceSheet extends ConsumerStatefulWidget {
  const AssistantVoiceSheet({super.key});

  @override
  ConsumerState<AssistantVoiceSheet> createState() =>
      _AssistantVoiceSheetState();
}

class _AssistantVoiceSheetState extends ConsumerState<AssistantVoiceSheet> {
  final _editCtrl = TextEditingController();
  bool _closing = false;

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(assistantVoiceControllerProvider);
    final settings = ref.watch(assistantVoiceSettingsProvider);

    // A turn was dispatched (chat went busy) → the sheet's job is done.
    ref.listen(assistantChatControllerProvider, (prev, next) {
      if (next.busy) _close();
    });
    // Keep the editable confirm field in sync when a low-confidence
    // transcript arrives.
    ref.listen(assistantVoiceControllerProvider, (prev, next) {
      if (next.phase == VoicePhase.confirming &&
          prev?.phase != VoicePhase.confirming) {
        _editCtrl.text = next.confirmText;
      }
    });

    final listening = voice.phase == VoicePhase.listening;
    final confirming = voice.phase == VoicePhase.confirming;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Language chips — switching restarts nothing mid-flight; it applies
          // to the next listen.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final l in kAssistantLanguages)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(l.label,
                          style: const TextStyle(fontSize: 11.5)),
                      selected: settings.language == l.code,
                      onSelected: (_) => ref
                          .read(assistantVoiceSettingsProvider.notifier)
                          .update(settings.copyWith(language: l.code)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (confirming) ...[
            const Text(
              'Did I hear that right?',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _editCtrl,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              decoration: const InputDecoration(
                  helperText: 'Edit if needed, then send.'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.mic_rounded, size: 16),
                    label: const Text('Try again'),
                    onPressed: () {
                      ref
                          .read(assistantVoiceControllerProvider.notifier)
                          .discardTranscript();
                      ref
                          .read(assistantVoiceControllerProvider.notifier)
                          .startListening();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send'),
                    onPressed: () => ref
                        .read(assistantVoiceControllerProvider.notifier)
                        .confirmTranscript(_editCtrl.text),
                  ),
                ),
              ],
            ),
          ] else ...[
            _MicOrb(
              listening: listening,
              soundLevel: voice.soundLevel,
              onTap: () {
                final notifier =
                    ref.read(assistantVoiceControllerProvider.notifier);
                listening ? notifier.stopListening() : notifier.startListening();
              },
            ),
            const SizedBox(height: 14),
            Text(
              listening
                  ? (voice.partialText.isEmpty
                      ? 'Listening…'
                      : voice.partialText)
                  : (voice.error ?? 'Tap the mic and speak'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: voice.partialText.isEmpty ? 12.5 : 14,
                fontWeight: voice.partialText.isEmpty
                    ? FontWeight.w500
                    : FontWeight.w700,
                color: voice.error != null && !listening
                    ? AppColors.danger
                    : (voice.partialText.isEmpty
                        ? AppColors.muted
                        : AppColors.ink),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                ref
                    .read(assistantVoiceControllerProvider.notifier)
                    .cancelListening();
                _close();
              },
              child: const Text('Cancel'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The animated microphone: a breathing brand-gradient orb with up to three
/// sound-reactive ripple rings while listening.
class _MicOrb extends StatefulWidget {
  const _MicOrb({
    required this.listening,
    required this.soundLevel,
    required this.onTap,
  });

  final bool listening;
  final double soundLevel; // 0..1
  final VoidCallback onTap;

  @override
  State<_MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<_MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.listening ? 'Stop listening' : 'Start speaking',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: 148,
          height: 148,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final rings = <Widget>[];
            if (widget.listening) {
              for (var i = 0; i < 3; i++) {
                final t = (_pulse.value + i / 3) % 1.0;
                final boost = 0.5 + widget.soundLevel; // louder → wider rings
                rings.add(Center(
                  child: Container(
                    width: 84 + t * 64 * boost,
                    height: 84 + t * 64 * boost,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(
                            (1 - t) * 0.35 * (0.6 + widget.soundLevel)),
                        width: 2,
                      ),
                    ),
                  ),
                ));
              }
            }
            return Stack(
              children: [
                ...rings,
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: AppColors.heroGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: widget.listening ? 24 : 12,
                          spreadRadius: widget.listening ? 4 : 0,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.listening
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              ],
            );
          },
          ),
        ),
      ),
    );
  }
}

/// Assistant voice settings sheet: input language and haptics. Replies are
/// text-only — there is no voice output.
class AssistantVoiceSettingsSheet extends ConsumerWidget {
  const AssistantVoiceSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(assistantVoiceSettingsProvider);
    final notifier = ref.read(assistantVoiceSettingsProvider.notifier);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Voice settings',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Haptic feedback',
                style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('Vibrate on voice actions',
                style: TextStyle(fontSize: 11.5)),
            value: settings.haptics,
            onChanged: (v) => notifier.update(settings.copyWith(haptics: v)),
          ),
          const SizedBox(height: 4),
          const Text('Voice input language',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in kAssistantLanguages)
                ChoiceChip(
                  label:
                      Text(l.label, style: const TextStyle(fontSize: 11.5)),
                  selected: settings.language == l.code,
                  onSelected: (_) =>
                      notifier.update(settings.copyWith(language: l.code)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Privacy: wipe the entire server-side assistant history.
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Clear all chat history'),
              onPressed: () => _clearHistory(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all chat history?'),
        content: const Text(
            'Every assistant conversation will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete all')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(assistantRepositoryProvider).deleteAllConversations();
      ref.read(assistantChatControllerProvider.notifier).newChat();
      ref.invalidate(assistantConversationsProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat history cleared.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not clear history. Please try again.')));
      }
    }
  }
}
