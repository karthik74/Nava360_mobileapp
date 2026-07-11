import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import 'voice_conversation_controller.dart';

/// Full-screen hands-free voice conversation (ChatGPT-style): an animated orb
/// listens, thinks and speaks in a continuous loop. Tapping the orb is
/// barge-in; the ✕ closes voice mode.
class VoiceConversationScreen extends ConsumerStatefulWidget {
  const VoiceConversationScreen({super.key});

  @override
  ConsumerState<VoiceConversationScreen> createState() =>
      _VoiceConversationScreenState();
}

class _VoiceConversationScreenState
    extends ConsumerState<VoiceConversationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void initState() {
    super.initState();
    // Kick off the loop after the first frame so the provider is alive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(voiceConversationControllerProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _statusText(VoiceConvPhase phase) {
    switch (phase) {
      case VoiceConvPhase.listening:
        return 'Listening…';
      case VoiceConvPhase.transcribing:
        return 'Got it…';
      case VoiceConvPhase.thinking:
        return 'Thinking…';
      case VoiceConvPhase.speaking:
        return 'Speaking… (tap to interrupt)';
      case VoiceConvPhase.error:
        return 'Reconnecting…';
      case VoiceConvPhase.idle:
        return 'Starting…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(voiceConversationControllerProvider);
    final notifier = ref.read(voiceConversationControllerProvider.notifier);
    final speaking = s.phase == VoiceConvPhase.speaking;
    final listening = s.phase == VoiceConvPhase.listening;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                iconSize: 28,
                onPressed: () async {
                  await notifier.stop();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ),
            const Spacer(),

            // Animated orb — pulses with mic level while listening, glows while speaking.
            GestureDetector(
              onTap: () {
                if (speaking) {
                  notifier.interrupt();
                }
              },
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  const base = 150.0;
                  final levelBoost = listening ? s.level * 70 : 0.0;
                  final breathe =
                      speaking ? (math.sin(_pulse.value * 2 * math.pi) * 14 + 14) : 0.0;
                  final size = base + levelBoost + breathe;
                  return Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.95),
                          AppColors.primary.withValues(alpha: 0.75),
                          AppColors.pink.withValues(alpha: 0.55),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.45),
                          blurRadius: 40 + levelBoost,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      speaking
                          ? Icons.graphic_eq_rounded
                          : listening
                              ? Icons.mic_rounded
                              : Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 36),
            Text(
              _statusText(s.phase),
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),

            // Live transcript / reply preview.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: SizedBox(
                height: 90,
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    speaking && s.replyText.isNotEmpty
                        ? s.replyText
                        : s.userText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),

            if (s.error != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  s.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                ),
              ),
            ],

            const Spacer(),

            // Bottom controls: barge-in (talk now) and end.
            Padding(
              padding: const EdgeInsets.only(bottom: 28, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundBtn(
                    icon: Icons.mic_rounded,
                    label: 'Talk',
                    onTap: () => notifier.interrupt(),
                  ),
                  const SizedBox(width: 40),
                  _RoundBtn(
                    icon: Icons.close_rounded,
                    label: 'End',
                    danger: true,
                    onTap: () async {
                      await notifier.stop();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: onTap,
          radius: 40,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger
                  ? Colors.red.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.12),
              border: Border.all(
                  color: danger ? Colors.redAccent : Colors.white24, width: 1),
            ),
            child: Icon(icon,
                color: danger ? Colors.redAccent : Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
      ],
    );
  }
}
