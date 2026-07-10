import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'assistant_controller.dart';
import 'assistant_language.dart';
import 'assistant_voice_settings.dart';

/// Voice interaction phases. Voice is INPUT-ONLY: replies are read as text,
/// never spoken aloud.
enum VoicePhase { idle, listening, confirming }

class AssistantVoiceState {
  final VoicePhase phase;

  /// Live transcript while listening.
  final String partialText;

  /// Low-confidence final transcript awaiting the user's polite confirmation.
  final String confirmText;

  /// Normalized microphone level 0..1 for the wave animation.
  final double soundLevel;
  final String? error;

  const AssistantVoiceState({
    this.phase = VoicePhase.idle,
    this.partialText = '',
    this.confirmText = '',
    this.soundLevel = 0,
    this.error,
  });

  AssistantVoiceState copyWith({
    VoicePhase? phase,
    String? partialText,
    String? confirmText,
    double? soundLevel,
    Object? error = _sentinel,
  }) =>
      AssistantVoiceState(
        phase: phase ?? this.phase,
        partialText: partialText ?? this.partialText,
        confirmText: confirmText ?? this.confirmText,
        soundLevel: soundLevel ?? this.soundLevel,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

/// Orchestrates speech-to-text into the chat pipeline:
///
/// mic → listening (wave) → transcript → [low confidence? confirm politely]
/// → send through the SAME chat controller → reply streams as TEXT.
class AssistantVoiceController extends StateNotifier<AssistantVoiceState> {
  AssistantVoiceController(this._ref) : super(const AssistantVoiceState());

  /// Confidence below this asks the user to confirm instead of auto-sending.
  static const double _confidenceFloor = 0.45;

  /// Trailing silence that means "I have finished speaking".
  static const Duration _pauseFor = Duration(seconds: 8);

  /// A recognizer stop with less trailing silence than this is the PLATFORM
  /// giving up early (Android finalizes after a few seconds of pause no
  /// matter what pauseFor asks for) — not the user finishing. We resume
  /// listening and keep accumulating instead of cutting the user off.
  static const Duration _completionSilence = Duration(seconds: 6);

  /// Cap for one recognizer session; the utterance spans several via resume.
  static const Duration _sessionCap = Duration(seconds: 60);

  /// Hard cap for one mic tap, across all resumed sessions.
  static const Duration _utteranceCap = Duration(minutes: 3);

  final Ref _ref;
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;

  // One user utterance accumulated across recognizer sessions.
  String _accumulated = '';
  String _lastPartial = '';
  bool _userDone = false;
  bool _allConfident = true;
  bool _stopHandled = false;
  String _localeId = '';
  DateTime _utteranceStart = DateTime.now();
  DateTime _lastSpeechActivity = DateTime.now();

  static String _join(String a, String b) =>
      a.isEmpty ? b : (b.isEmpty ? a : '$a $b');

  // ── Listening ─────────────────────────────────────────────────────────────

  Future<void> startListening() async {
    if (_ref.read(assistantChatControllerProvider).busy) return;

    if (!_speechReady) {
      try {
        _speechReady = await _speech.initialize(
          onError: _onSpeechError,
          onStatus: _onSpeechStatus,
        );
      } catch (_) {
        _speechReady = false;
      }
      if (!_speechReady) {
        state = state.copyWith(
            phase: VoicePhase.idle,
            error: 'Voice input is unavailable. Check the microphone '
                'permission and try again.');
        return;
      }
    }

    final lang = assistantLanguageByCode(
        _ref.read(assistantVoiceSettingsProvider).language);
    _localeId = lang.sttLocale;
    _accumulated = '';
    _userDone = false;
    _allConfident = true;
    _utteranceStart = DateTime.now();
    _lastSpeechActivity = DateTime.now();
    _haptic();
    state = const AssistantVoiceState(phase: VoicePhase.listening);
    await _listen();
  }

  /// One recognizer session; an utterance may span several (see
  /// [_finishOrKeepListening]).
  Future<void> _listen() async {
    _stopHandled = false;
    _lastPartial = '';
    await _speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: _localeId,
        pauseFor: _pauseFor,
        listenFor: _sessionCap,
      ),
      onSoundLevelChange: (level) {
        // Android reports roughly -2..10 dB; normalize for the wave UI.
        final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
        if (state.phase == VoicePhase.listening) {
          state = state.copyWith(soundLevel: normalized);
        }
      },
    );
  }

  void _onSpeechResult(SpeechRecognitionResult r) {
    if (!mounted || state.phase != VoicePhase.listening) return;
    final text = r.recognizedWords.trim();
    if (!r.finalResult) {
      if (text.isNotEmpty && text != _lastPartial) {
        _lastPartial = text;
        _lastSpeechActivity = DateTime.now();
      }
      state = state.copyWith(partialText: _join(_accumulated, text));
      return;
    }
    if (_stopHandled) return;
    _stopHandled = true;
    final confident = !r.hasConfidenceRating ||
        r.confidence <= 0 ||
        r.confidence >= _confidenceFloor;
    _finishOrKeepListening(text, confident);
  }

  void _onSpeechError(SpeechRecognitionError e) {
    if (!mounted || state.phase != VoicePhase.listening) return;
    if (e.permanent) {
      state = state.copyWith(
        phase: VoicePhase.idle,
        partialText: '',
        error: 'Voice input is unavailable for this language on your device.',
      );
      return;
    }
    // Transient errors (no-match, speech timeout) end the OS session, not
    // the user's turn — decide like any other session stop.
    if (_stopHandled) return;
    _stopHandled = true;
    _finishOrKeepListening('', true);
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status != 'notListening' && status != 'done') return;
    // Give the final-result callback a moment to arrive first; if nothing
    // claims this session stop, decide with the last partial we heard.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || _stopHandled || state.phase != VoicePhase.listening) {
        return;
      }
      _stopHandled = true;
      _finishOrKeepListening(_lastPartial, true);
    });
  }

  /// A recognizer session ended having heard [segment]. Either the user is
  /// actually done — mic tap, long trailing silence, or the utterance cap —
  /// and the accumulated text is dispatched; or the platform gave up early
  /// mid-utterance and listening resumes so the user is never cut off
  /// before completing their words.
  Future<void> _finishOrKeepListening(String segment, bool confident) async {
    _accumulated = _join(_accumulated, segment);
    _allConfident = _allConfident && confident;
    final silence = DateTime.now().difference(_lastSpeechActivity);
    final capped = DateTime.now().difference(_utteranceStart) >= _utteranceCap;

    if (!_userDone && !capped && silence < _completionSilence) {
      state = state.copyWith(partialText: _accumulated);
      // The platform needs a beat between sessions before it can listen again.
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted && state.phase == VoicePhase.listening) await _listen();
      return;
    }

    final text = _accumulated;
    _accumulated = '';
    if (text.isEmpty) {
      state = state.copyWith(
          phase: VoicePhase.idle,
          partialText: '',
          error: "Sorry, I didn't catch that. Please try again.");
    } else if (_allConfident) {
      _sendVoiceTurn(text);
    } else {
      // Polite low-confidence check: show what was heard, let the user
      // send it, edit it, or re-record — never fire a guess silently.
      state = state.copyWith(
          phase: VoicePhase.confirming, partialText: '', confirmText: text);
    }
  }

  /// User accepted the low-confidence transcript (possibly edited).
  void confirmTranscript([String? edited]) {
    final text = (edited ?? state.confirmText).trim();
    if (text.isEmpty) {
      state = state.copyWith(phase: VoicePhase.idle, confirmText: '');
      return;
    }
    _sendVoiceTurn(text);
  }

  void discardTranscript() {
    state = state.copyWith(
        phase: VoicePhase.idle, confirmText: '', partialText: '');
  }

  /// User says they're done (mic tap): finish with whatever was heard so far
  /// instead of resuming after the recognizer stops.
  Future<void> stopListening() async {
    _userDone = true;
    await _speech.stop();
  }

  Future<void> cancelListening() async {
    _userDone = true;
    _stopHandled = true;
    _accumulated = '';
    await _speech.cancel();
    if (mounted) {
      state = state.copyWith(phase: VoicePhase.idle, partialText: '');
    }
  }

  void _sendVoiceTurn(String text) {
    _haptic();
    state = const AssistantVoiceState(); // idle; the chat state takes over
    _ref.read(assistantChatControllerProvider.notifier).send(text);
  }

  void _haptic() {
    if (_ref.read(assistantVoiceSettingsProvider).haptics) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }
}

/// Not autoDispose: keeps the recognizer warm alongside the persistent chat.
final assistantVoiceControllerProvider =
    StateNotifierProvider<AssistantVoiceController, AssistantVoiceState>(
        AssistantVoiceController.new);
