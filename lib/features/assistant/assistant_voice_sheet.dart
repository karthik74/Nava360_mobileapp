import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
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
    final hasError = voice.error != null && !listening;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom +
            MediaQuery.of(context).viewInsets.bottom +
            20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Handle(),
          const SizedBox(height: 14),
          // Language chips — switching restarts nothing mid-flight; it applies
          // to the next listen.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final l in kAssistantLanguages)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(l.label),
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
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Did I hear that right?',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.35,
                    color: AppColors.ink),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _editCtrl,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              decoration: const InputDecoration(
                  helperText: 'Edit if needed, then send.'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.mic_rounded, size: 18),
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
                    icon: const Icon(Icons.send_rounded, size: 18),
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
            const SizedBox(height: 12),
            if (listening && voice.partialText.isEmpty)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProPulseDot(color: AppColors.live),
                  SizedBox(width: 6),
                  Text(
                    'Listening…',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              )
            else
              Text(
                listening
                    ? voice.partialText
                    : (voice.error ?? 'Tap the mic and speak'),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: listening ? 16 : 14,
                  height: 1.4,
                  fontWeight: listening ? FontWeight.w600 : FontWeight.w500,
                  color: hasError
                      ? AppColors.danger
                      : (listening ? AppColors.ink : AppColors.muted),
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

/// The animated microphone: a deep brand orb with up to three sound-reactive
/// ripple rings while listening.
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
          width: 156,
          height: 156,
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
                      width: 92 + t * 64 * boost,
                      height: 92 + t * 64 * boost,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(
                              alpha: ((1 - t) * 0.45 * (0.6 + widget.soundLevel))
                                  .clamp(0.0, 1.0)),
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
                    child: AnimatedScale(
                      scale: widget.listening
                          ? 1 + widget.soundLevel.clamp(0.0, 1.0) * 0.06
                          : 1,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.deep.withValues(alpha: 0.6),
                              blurRadius: 30,
                              spreadRadius: -12,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: ProDeepSurface(
                          radius: 46,
                          padding: EdgeInsets.zero,
                          child: SizedBox(
                            width: 92,
                            height: 92,
                            child: Icon(
                              widget.listening
                                  ? Icons.graphic_eq_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Handle(),
          const SizedBox(height: 14),
          const Text('Voice settings',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.35,
                  color: AppColors.ink)),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: ProIconWell(
                  icon: Icons.vibration_rounded, color: AppColors.primary),
              title: const Text('Haptic feedback'),
              subtitle: const Text('Vibrate on voice actions'),
              value: settings.haptics,
              onChanged: (v) => notifier.update(settings.copyWith(haptics: v)),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Voice input language', style: AppText.label),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in kAssistantLanguages)
                ChoiceChip(
                  label: Text(l.label),
                  selected: settings.language == l.code,
                  onSelected: (_) =>
                      notifier.update(settings.copyWith(language: l.code)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Privacy: wipe the entire server-side assistant history.
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.dangerTint,
                  foregroundColor: AppColors.danger),
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

/// 40×5 drag handle for the white bottom sheets.
class _Handle extends StatelessWidget {
  const _Handle();

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
