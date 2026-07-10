import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/tts_service.dart';
import 'assistant_controller.dart';
import 'assistant_language.dart';
import 'assistant_voice_settings.dart';

/// Voice interaction phases.
enum VoicePhase { idle, listening, confirming, speaking }

class AssistantVoiceState {
  final VoicePhase phase;

  /// Live transcript while listening.
  final String partialText;

  /// Set when a reply could not be spoken because the device has no voice for
  /// its language (e.g. Kannada TTS not installed). Surfaced once, not fatal.
  final String? voiceUnavailable;

  /// Low-confidence final transcript awaiting the user's polite confirmation.
  final String confirmText;

  /// Normalized microphone level 0..1 for the wave animation.
  final double soundLevel;
  final String? error;

  const AssistantVoiceState({
    this.phase = VoicePhase.idle,
    this.partialText = '',
    this.voiceUnavailable,
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
    Object? voiceUnavailable = _sentinel,
  }) =>
      AssistantVoiceState(
        phase: phase ?? this.phase,
        partialText: partialText ?? this.partialText,
        confirmText: confirmText ?? this.confirmText,
        soundLevel: soundLevel ?? this.soundLevel,
        error: identical(error, _sentinel) ? this.error : error as String?,
        voiceUnavailable: identical(voiceUnavailable, _sentinel)
            ? this.voiceUnavailable
            : voiceUnavailable as String?,
      );

  static const _sentinel = Object();
}

/// Orchestrates speech-to-text, the chat pipeline, and text-to-speech:
///
/// mic → listening (wave) → transcript → [low confidence? confirm politely]
/// → send through the SAME chat controller → reply streams → spoken aloud in
/// the reply's own language (script-detected). Tapping the mic while the
/// assistant is speaking stops speech instantly (barge-in) and listens again.
class AssistantVoiceController extends StateNotifier<AssistantVoiceState> {
  AssistantVoiceController(this._ref) : super(const AssistantVoiceState()) {
    // Speak replies for voice-initiated turns as soon as the answer lands.
    _chatSub = _ref.listen<AssistantChatState>(assistantChatControllerProvider,
        (prev, next) {
      final finished = prev != null && prev.busy && !next.busy;
      if (!finished || !_lastTurnWasVoice || next.messages.isEmpty) return;
      final last = next.messages.last;
      if (!last.isUser && last.content.isNotEmpty) {
        speak(last.content);
      }
    });
  }

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
  final FlutterTts _tts = FlutterTts();
  ProviderSubscription<AssistantChatState>? _chatSub;
  bool _speechReady = false;
  bool _ttsReady = false;
  bool _lastTurnWasVoice = false;

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

  /// A typed turn cancels reply speech and voice continuity.
  void markTextTurn() {
    _lastTurnWasVoice = false;
    stopSpeaking();
  }

  // ── Listening ─────────────────────────────────────────────────────────────

  Future<void> startListening() async {
    stopSpeaking(); // barge-in: never talk over the user
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
    state = state.copyWith(phase: VoicePhase.idle, confirmText: '', partialText: '');
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
    _lastTurnWasVoice = true;
    _haptic();
    state = const AssistantVoiceState(); // idle; the chat state takes over
    _ref.read(assistantChatControllerProvider.notifier).send(text);
  }

  void _haptic() {
    if (_ref.read(assistantVoiceSettingsProvider).haptics) {
      HapticFeedback.mediumImpact();
    }
  }

  // ── Speaking ──────────────────────────────────────────────────────────────

  Future<void> speak(String markdown) async {
    final settings = _ref.read(assistantVoiceSettingsProvider);
    if (!settings.voiceOutput) return;
    final text = speakableText(markdown);
    if (text.isEmpty) return;

    if (!_ttsReady) {
      _tts.setCompletionHandler(_onSpeechDone);
      _tts.setCancelHandler(_onSpeechDone);
      _tts.setErrorHandler((_) => _onSpeechDone());
      _ttsReady = true;
    }
    final code = detectAssistantLanguage(text,
        devanagariPreference: settings.language);
    final lang = assistantLanguageByCode(code);

    // Kannada never uses the device engine: it goes through the self-hosted
    // pipeline (bundled assets → cache → our /api/tts microservice), which
    // works on every phone regardless of installed voice packs.
    if (code == 'kn') {
      state = state.copyWith(
          phase: VoicePhase.idle, error: null, voiceUnavailable: null);
      final ok = await TtsService.instance.speak(text);
      if (!ok && mounted) {
        state = state.copyWith(
            voiceUnavailable: 'Kannada speech is unavailable right now — '
                'check your connection and try again.');
      }
      return;
    }

    // The engine does NOT fail loudly for a missing voice — setLanguage()
    // silently leaves the default (usually English) in place, which would read
    // Kannada/Tamil text with an English voice. Verify first.
    final resolved = await _resolveTtsLocale(lang);
    if (resolved == null) {
      state = state.copyWith(
        phase: VoicePhase.idle,
        voiceUnavailable: '${lang.label} speech is not installed on this device. '
            'Add it in Settings → Text-to-speech to hear replies aloud.',
      );
      return;
    }

    await _tts.setLanguage(resolved);
    await _tts.setSpeechRate(settings.speechRate);
    state = state.copyWith(
        phase: VoicePhase.speaking, error: null, voiceUnavailable: null);
    await _tts.speak(text);
  }

  /// Cache of locale → usable, so we hit the platform channel once per language.
  final Map<String, String?> _localeCache = {};

  /// Picks a locale the engine can actually speak: the regional tag
  /// ("kn-IN") first, then the bare language ("kn"). Null = no voice for this
  /// language; we then stay silent rather than mispronounce it in English.
  Future<String?> _resolveTtsLocale(AssistantLanguage lang) async {
    if (_localeCache.containsKey(lang.code)) return _localeCache[lang.code];
    String? usable;
    for (final candidate in [lang.ttsLocale, lang.code]) {
      try {
        if (await _tts.isLanguageAvailable(candidate) == true) {
          usable = candidate;
          break;
        }
      } catch (_) {
        // Platform doesn't support the probe — assume the regional tag works.
        usable = lang.ttsLocale;
        break;
      }
    }
    _localeCache[lang.code] = usable;
    return usable;
  }

  void _onSpeechDone() {
    if (mounted && state.phase == VoicePhase.speaking) {
      state = state.copyWith(phase: VoicePhase.idle);
    }
  }

  Future<void> stopSpeaking() async {
    await TtsService.instance.stop(); // self-hosted Kannada playback
    try {
      await _tts.stop();
    } catch (_) {/* engine not started yet */}
    if (mounted && state.phase == VoicePhase.speaking) {
      state = state.copyWith(phase: VoicePhase.idle);
    }
  }

  @override
  void dispose() {
    _chatSub?.close();
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }
}

/// Not autoDispose: keeps TTS/recognizer warm alongside the persistent chat.
final assistantVoiceControllerProvider =
    StateNotifierProvider<AssistantVoiceController, AssistantVoiceState>(
        AssistantVoiceController.new);
