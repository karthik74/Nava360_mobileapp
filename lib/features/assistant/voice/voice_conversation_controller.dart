import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../assistant_controller.dart';
import 'voice_conversation_repository.dart';

/// Phases of the hands-free voice conversation (ChatGPT-style).
enum VoiceConvPhase { idle, listening, transcribing, thinking, speaking, error }

class VoiceConvState {
  final VoiceConvPhase phase;

  /// Mic level 0..1 while listening (drives the orb animation).
  final double level;

  /// The user's last recognized utterance (shown briefly).
  final String userText;

  /// The assistant reply currently being spoken.
  final String replyText;
  final String? error;

  const VoiceConvState({
    this.phase = VoiceConvPhase.idle,
    this.level = 0,
    this.userText = '',
    this.replyText = '',
    this.error,
  });

  VoiceConvState copyWith({
    VoiceConvPhase? phase,
    double? level,
    String? userText,
    String? replyText,
    Object? error = _sentinel,
  }) =>
      VoiceConvState(
        phase: phase ?? this.phase,
        level: level ?? this.level,
        userText: userText ?? this.userText,
        replyText: replyText ?? this.replyText,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

/// Runs the continuous listen → transcribe → think → speak → listen loop the
/// same way ChatGPT's voice mode does. STT and TTS go through the backend
/// Sarvam proxy; the LLM turn reuses the existing streaming chat controller
/// (so tools, RBAC and conversation history all apply). Tapping the orb is
/// barge-in: it interrupts whatever is happening and starts listening again.
class VoiceConversationController extends StateNotifier<VoiceConvState> {
  VoiceConversationController(this._ref) : super(const VoiceConvState());

  final Ref _ref;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _active = false; // conversation is open
  bool _stopRequested = false; // current recording should stop now
  StreamSubscription<Amplitude>? _ampSub;

  // Silence-based turn taking.
  static const double _speechDb = -30; // above this = speaking
  static const double _silenceDb = -38; // below this = quiet
  static const Duration _endSilence = Duration(milliseconds: 1500);
  static const Duration _maxUtterance = Duration(seconds: 30);
  static const Duration _minUtterance = Duration(milliseconds: 500);

  VoiceConversationRepository get _repo =>
      _ref.read(voiceConversationRepositoryProvider);

  // ── Public control ─────────────────────────────────────────────────────────

  /// Opens the conversation and starts the first listen.
  Future<void> start() async {
    if (_active) return;
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(
          phase: VoiceConvPhase.error,
          error: 'Microphone permission is required for voice chat.');
      return;
    }
    _active = true;
    unawaited(_loop());
  }

  /// Barge-in: whatever we're doing, stop and listen to the user now.
  Future<void> interrupt() async {
    if (!_active) return;
    _haptic();
    _stopRequested = true;
    await _player.stop();
    // If we're mid-playback the loop is awaiting; nudging it back to listening
    // happens when the current speak() returns. If idle-ish, kick a new listen.
    if (state.phase == VoiceConvPhase.speaking ||
        state.phase == VoiceConvPhase.idle ||
        state.phase == VoiceConvPhase.error) {
      // handled by _loop continuation
    }
  }

  /// Closes the conversation entirely.
  Future<void> stop() async {
    _active = false;
    _stopRequested = true;
    await _ampSub?.cancel();
    await _recorder.stop();
    await _player.stop();
    if (mounted) state = const VoiceConvState();
  }

  // ── The loop ────────────────────────────────────────────────────────────────

  Future<void> _loop() async {
    while (_active) {
      try {
        final path = await _listen();
        if (!_active) break;
        if (path == null) {
          continue; // nothing heard — listen again
        }

        state = state.copyWith(phase: VoiceConvPhase.transcribing, level: 0);
        final t = await _repo.transcribe(path);
        if (!_active) break;
        if (t.text.isEmpty) {
          continue; // silence/noise — listen again
        }
        state = state.copyWith(userText: t.text);

        // LLM turn via the shared streaming chat controller.
        state = state.copyWith(phase: VoiceConvPhase.thinking);
        final reply = await _askAssistant(t.text);
        if (!_active) break;
        if (reply.trim().isEmpty) {
          continue;
        }

        await _speak(reply, t.languageCode);
        // then loop straight back to listening (hands-free)
      } catch (e) {
        if (!_active) break;
        state = state.copyWith(
            phase: VoiceConvPhase.error, error: _friendly(e), level: 0);
        // Brief pause, then resume listening so a transient error doesn't end
        // the conversation.
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Records one utterance, auto-stopping on trailing silence (or a tap/cap).
  /// Returns the file path, or null when nothing usable was captured.
  Future<String?> _listen() async {
    _stopRequested = false;
    state = state.copyWith(
        phase: VoiceConvPhase.listening, level: 0, userText: '', replyText: '');
    _haptic();

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/nava_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    // 16 kHz mono WAV — what Saaras works best with.
    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );

    final started = DateTime.now();
    var lastLoud = DateTime.now();
    var heardSpeech = false;
    final done = Completer<void>();

    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      final db = amp.current; // dBFS: ~0 loud, ~-60 silent
      final norm = ((db + 45) / 45).clamp(0.0, 1.0);
      if (mounted && state.phase == VoiceConvPhase.listening) {
        state = state.copyWith(level: norm);
      }
      final now = DateTime.now();
      if (db > _speechDb) {
        heardSpeech = true;
        lastLoud = now;
      }
      final silentFor = now.difference(lastLoud);
      final tooLong = now.difference(started) > _maxUtterance;
      final endedBySilence =
          heardSpeech && db < _silenceDb && silentFor > _endSilence;
      if (_stopRequested || tooLong || endedBySilence) {
        if (!done.isCompleted) done.complete();
      }
    });

    await done.future;
    await _ampSub?.cancel();
    _ampSub = null;
    final recordedPath = await _recorder.stop();

    final tooShort = DateTime.now().difference(started) < _minUtterance;
    if (!heardSpeech || tooShort || _stopRequested && !heardSpeech) {
      return null;
    }
    return recordedPath ?? path;
  }

  /// Drives the shared chat controller for one turn and returns the reply text.
  Future<String> _askAssistant(String text) async {
    final notifier = _ref.read(assistantChatControllerProvider.notifier);
    final before = _ref.read(assistantChatControllerProvider).messages.length;
    // send() awaits the full SSE stream, so the reply is ready when it returns.
    await notifier.send(text);
    final msgs = _ref.read(assistantChatControllerProvider).messages;
    if (msgs.length > before && msgs.last.role == 'ASSISTANT') {
      return msgs.last.content;
    }
    return '';
  }

  /// Synthesizes and plays the reply, clip by clip. A barge-in tap stops it.
  Future<void> _speak(String reply, String? languageCode) async {
    state = state.copyWith(phase: VoiceConvPhase.speaking, replyText: reply);
    _stopRequested = false;
    final clips = await _repo.synthesize(reply, languageCode);
    for (final clip in clips) {
      if (!_active || _stopRequested) break;
      await _player.play(BytesSource(Uint8List.fromList(clip)));
      await _player.onPlayerComplete.first;
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('not configured')) {
      return 'Voice chat is not set up yet. Please contact your administrator.';
    }
    return 'Something went wrong. Listening again…';
  }

  void _haptic() => HapticFeedback.lightImpact();

  @override
  void dispose() {
    _active = false;
    _ampSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}

final voiceConversationControllerProvider = StateNotifierProvider.autoDispose<
    VoiceConversationController, VoiceConvState>(
  VoiceConversationController.new,
);
