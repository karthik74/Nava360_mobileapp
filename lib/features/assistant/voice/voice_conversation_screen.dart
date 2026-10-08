import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pro_ui.dart';
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
    final live = s.phase != VoiceConvPhase.idle &&
        s.phase != VoiceConvPhase.error;
    final showReply = speaking && s.replyText.isNotEmpty;

    Future<void> close() async {
      await notifier.stop();
      if (context.mounted) Navigator.of(context).pop();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.deep,
        body: ProDeepSurface(
          padding: EdgeInsets.zero,
          child: SizedBox.expand(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    // Header: close, title, live pill.
                    Row(
                      children: [
                        ProHeroIconButton(
                          icon: Icons.close_rounded,
                          iconSize: 22,
                          tooltip: 'Close voice chat',
                          onTap: close,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Voice chat',
                                style: TextStyle(
                                  fontSize: 22,
                                  height: 1.27,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.55,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'AI assistant',
                                style: TextStyle(
                                    fontSize: 12.5, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        _LivePill(live: live),
                      ],
                    ),
                    // Animated orb — pulses with mic level while listening,
                    // breathes while speaking.
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: GestureDetector(
                            onTap: () {
                              if (speaking) {
                                notifier.interrupt();
                              }
                            },
                            child: SizedBox(
                              width: 264,
                              height: 264,
                              child: AnimatedBuilder(
                                animation: _pulse,
                                builder: (context, _) {
                                  const base = 150.0;
                                  final levelBoost = listening ? s.level * 70 : 0.0;
                                  final breathe = speaking
                                      ? (math.sin(_pulse.value * 2 * math.pi) * 14 +
                                          14)
                                      : 0.0;
                                  final size = base + levelBoost + breathe;
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Faint halo rings.
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.08)),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(26),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppColors.primary
                                                .withValues(alpha: 0.08),
                                            border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.1)),
                                          ),
                                        ),
                                      ),
                                      // Core.
                                      Container(
                                        width: size,
                                        height: size,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            center: const Alignment(-0.32, -0.44),
                                            radius: 0.9,
                                            colors: [
                                              Color.lerp(AppColors.primary,
                                                  Colors.white, 0.18)!,
                                              AppColors.primary,
                                              Color.lerp(AppColors.primary,
                                                  AppColors.deep, 0.6)!,
                                            ],
                                            stops: const [0, 0.46, 1],
                                          ),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.2)),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.45),
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
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
                    Text(
                      _statusText(s.phase),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.27,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Live transcript / reply preview.
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 344),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            showReply ? 'Assistant' : 'You',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  showReply ? AppColors.live : Colors.white60,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 78,
                            child: SingleChildScrollView(
                              reverse: true,
                              child: Text(
                                showReply ? s.replyText : s.userText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (s.error != null) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          s.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFFFD690), fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Bottom controls: barge-in (talk now) and end.
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: _RoundBtn(
                              icon: Icons.mic_rounded,
                              label: 'Talk',
                              primary: true,
                              onTap: () => notifier.interrupt(),
                            ),
                          ),
                          Expanded(
                            child: _RoundBtn(
                              icon: Icons.call_end_rounded,
                              label: 'End',
                              danger: true,
                              onTap: close,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "● Live" pill on the deep header.
class _LivePill extends StatelessWidget {
  const _LivePill({required this.live});
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 6, right: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          live
              ? const ProPulseDot(color: AppColors.live, size: 7)
              : const SizedBox(
                  width: 17,
                  child: Center(
                    child: CircleAvatar(
                        radius: 3.5, backgroundColor: AppColors.faint),
                  ),
                ),
          const SizedBox(width: 2),
          Text(
            live ? 'Live' : 'Connecting',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: live ? Colors.white : Colors.white70,
            ),
          ),
        ],
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
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final size = primary ? 68.0 : 60.0;
    final Color bg = danger
        ? AppColors.danger
        : primary
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          child: Material(
            color: bg,
            shape: CircleBorder(
              side: primary || danger
                  ? BorderSide.none
                  : BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: Colors.white, size: 26),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
                color: Color(0xC7FFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
