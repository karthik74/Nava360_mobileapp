import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme.dart';
import '../task_models.dart';

/// What a finished take hands back: the file on disk, how long it ran, and where
/// each question landed in it.
class VideoQaTake {
  const VideoQaTake({
    required this.path,
    required this.durationSec,
    required this.marks,
  });

  final String path;
  final int durationSec;
  final List<VideoQaMark> marks;
}

/// A question and the span of the recording that answers it.
class VideoQaMark {
  const VideoQaMark({
    required this.key,
    required this.text,
    required this.startSec,
    required this.endSec,
  });

  final String key;
  final String text;
  final int startSec;
  final int endSec;

  Map<String, dynamic> toJson() => {
        'key': key,
        'text': text,
        'startSec': startSec,
        'endSec': endSec,
      };
}

/// Records ONE continuous take while working through the field's questions: each
/// is shown (and, unless turned off, spoken), then a countdown gives the person
/// their answer window before moving on. The last question stops the recording.
///
/// The offsets of each question are kept as the take runs, so a reviewer can jump
/// straight to the answer they care about instead of scrubbing the whole video.
class VideoQaRecorderScreen extends StatefulWidget {
  const VideoQaRecorderScreen({
    super.key,
    required this.config,
    required this.title,
  });

  final VideoQaConfig config;

  /// The field's label — shown so the person knows which question set this is.
  final String title;

  @override
  State<VideoQaRecorderScreen> createState() => _VideoQaRecorderScreenState();
}

class _VideoQaRecorderScreenState extends State<VideoQaRecorderScreen>
    with TickerProviderStateMixin {
  /// Device TTS locales for the languages the web designer offers.
  static const Map<String, String> _ttsLocales = {
    'en': 'en-IN',
    'hi': 'hi-IN',
    'kn': 'kn-IN',
    'ta': 'ta-IN',
    'te': 'te-IN',
    'ml': 'ml-IN',
    'mr': 'mr-IN',
  };

  /// A stalled TTS engine must not hold the recording hostage.
  static const Duration _speakTimeout = Duration(seconds: 10);

  CameraController? _camera;
  final FlutterTts _tts = FlutterTts();
  late final AnimationController _countdown;

  bool _initialising = true;
  String? _initError;
  bool _recording = false;
  bool _speaking = false;
  bool _finishing = false;
  int _index = 0;

  /// Wall clock of the take, for the per-question offsets.
  final Stopwatch _elapsed = Stopwatch();
  final List<VideoQaMark> _marks = [];
  int _questionStartedAtSec = 0;

  List<VideoQaQuestion> get _questions => widget.config.questions;

  @override
  void initState() {
    super.initState();
    _countdown = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.config.secondsPerQuestion),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _nextQuestion();
      });
    _initTts();
    _initCamera();
  }

  Future<void> _initTts() async {
    if (!widget.config.speakQuestions) return;
    try {
      final locale = _ttsLocales[widget.config.language] ?? 'en-IN';
      if (await _tts.isLanguageAvailable(locale) == true) {
        await _tts.setLanguage(locale);
      }
      // A language the phone has no voice for is not an error: the question is
      // on screen either way, so we simply read it in whatever voice there is.
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // Recording without narration still collects the answers.
    }
  }

  Future<void> _initCamera() async {
    final camera = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!camera.isGranted || !mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _initError = 'Nava360 needs the camera and microphone to record your answers.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw 'No camera on this device';
      final wanted = widget.config.frontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final picked = cameras.firstWhere(
        (c) => c.lensDirection == wanted,
        orElse: () => cameras.first,
      );
      // Medium (~480p) is deliberate: plenty for a spoken answer, and small
      // enough that the upload succeeds on a field connection.
      final controller = CameraController(
        picked,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _initialising = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _initError = 'The camera could not be started. $e';
      });
    }
  }

  Future<void> _start() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _recording) return;
    try {
      await cam.startVideoRecording();
    } catch (e) {
      _toast('Recording could not start. $e');
      return;
    }
    _marks.clear();
    _elapsed
      ..reset()
      ..start();
    setState(() {
      _recording = true;
      _index = 0;
    });
    _askCurrent();
  }

  /// Speak (optionally), then hand the floor over for the answer window.
  Future<void> _askCurrent() async {
    if (!mounted || !_recording) return;
    final asking = _index;
    _questionStartedAtSec = _elapsed.elapsed.inSeconds;

    if (widget.config.speakQuestions) {
      setState(() => _speaking = true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!_stillOn(asking)) return;
      await _speak(_questions[asking].text);
      if (!_stillOn(asking)) return;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!_stillOn(asking)) return;
    }

    setState(() => _speaking = false);
    _countdown
      ..reset()
      ..forward();
  }

  /// True while this is still the question we started asking — a retake, a stop,
  /// or a tap on "Next" mid-sentence must not resume an abandoned question.
  bool _stillOn(int asking) =>
      mounted && _recording && _index == asking && !_finishing;

  Future<void> _speak(String text) async {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      _tts
        ..setCompletionHandler(finish)
        ..setCancelHandler(finish)
        ..setErrorHandler((_) => finish());
      final started = await _tts.speak(text);
      if (started != 1) finish();
      await done.future.timeout(_speakTimeout, onTimeout: finish);
    } catch (_) {
      finish();
    }
  }

  void _nextQuestion() {
    if (!_recording || _finishing) return;
    _tts.stop();
    _countdown.stop();
    _markCurrent();

    if (_index < _questions.length - 1) {
      setState(() => _index++);
      _askCurrent();
    } else {
      _finish();
    }
  }

  void _markCurrent() {
    final q = _questions[_index];
    _marks.add(VideoQaMark(
      key: q.key,
      text: q.text,
      startSec: _questionStartedAtSec,
      endSec: _elapsed.elapsed.inSeconds,
    ));
  }

  Future<void> _finish() async {
    final cam = _camera;
    if (cam == null || !_recording || _finishing) return;
    setState(() => _finishing = true);
    _tts.stop();
    _countdown.stop();
    try {
      final file = await cam.stopVideoRecording();
      _elapsed.stop();
      if (!mounted) return;
      Navigator.of(context).pop(VideoQaTake(
        path: file.path,
        durationSec: _elapsed.elapsed.inSeconds,
        marks: List.of(_marks),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _finishing = false;
      });
      _toast('The recording could not be saved. $e');
    }
  }

  /// Abandons the take and throws the partial file away — a half-answered
  /// recording is worse than none.
  Future<void> _discardAndLeave() async {
    _tts.stop();
    _countdown.stop();
    final cam = _camera;
    if (cam != null && cam.value.isRecordingVideo) {
      try {
        final file = await cam.stopVideoRecording();
        final partial = File(file.path);
        if (partial.existsSync()) partial.deleteSync();
      } catch (_) {
        // Nothing to salvage either way.
      }
    }
    _elapsed.stop();
    if (mounted) Navigator.of(context).pop();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _tts.stop();
    _countdown.dispose();
    final cam = _camera;
    if (cam != null) {
      if (cam.value.isRecordingVideo) {
        cam.stopVideoRecording().catchError((_) => XFile('')).whenComplete(cam.dispose);
      } else {
        cam.dispose();
      }
    }
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Leaving mid-take must clean up the partial file, so intercept the back
      // gesture rather than letting the route drop out from under the camera.
      canPop: !_recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _recording ? _confirmLeave : () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop recording?'),
        content: const Text(
            'This take will be discarded and you will have to start again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep recording'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true) await _discardAndLeave();
  }

  Widget _body() {
    if (_initialising) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_initError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              _initError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: openAppSettings,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
    }

    final cam = _camera!;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cam.value.previewSize?.height ?? 480,
                  height: cam.value.previewSize?.width ?? 640,
                  child: CameraPreview(cam),
                ),
              ),
              if (_recording) _recordingBadge(),
            ],
          ),
        ),
        _prompt(),
      ],
    );
  }

  Widget _recordingBadge() => Positioned(
        top: 12,
        right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Question ${_index + 1} of ${_questions.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      );

  Widget _prompt() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: _recording ? _askingPanel() : _readyPanel(),
    );
  }

  Widget _readyPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_questions.length} question${_questions.length == 1 ? '' : 's'}, '
          '${widget.config.secondsPerQuestion}s to answer each',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Recording runs straight through. Answer each question as it appears.',
          style: TextStyle(color: Colors.white60, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.fiber_manual_record, size: 18),
            label: const Text('Start recording'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          ),
        ),
      ],
    );
  }

  Widget _askingPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _speaking ? 'Listen…' : 'Your answer',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          _questions[_index].text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _countdown,
          builder: (_, __) {
            final left = _speaking
                ? widget.config.secondsPerQuestion
                : (widget.config.secondsPerQuestion * (1 - _countdown.value)).ceil();
            return Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _speaking ? 0 : 1 - _countdown.value,
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(
                        _speaking ? Colors.white38 : AppColors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${left}s',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _finishing ? null : _nextQuestion,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: Text(
                  _index < _questions.length - 1 ? 'Next question' : 'Finish',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _finishing ? null : _finish,
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                child: Text(_finishing ? 'Saving…' : 'Stop'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
