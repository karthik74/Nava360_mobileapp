// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — customer verification video (Agreement & PDC step).
//
//  The BM films the customer speaking at signing: one continuous take, ~480p
//  so it uploads on a field connection, capped at [kMaxSeconds]. Pops an
//  [NpVideoTake] on success, null when the person backs out.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// A finished recording: the file on disk and how long it ran.
class NpVideoTake {
  const NpVideoTake({required this.path, required this.durationSec});
  final String path;
  final int durationSec;
}

class NpVerificationVideoScreen extends StatefulWidget {
  const NpVerificationVideoScreen({super.key, required this.candidateName});

  /// Shown in the prompt so the recorder knows who should be on camera.
  final String candidateName;

  /// Longest take allowed — recording stops by itself here.
  static const int kMaxSeconds = 180;

  /// Shorter takes are refused; a two-second clip verifies nothing.
  static const int kMinSeconds = 5;

  @override
  State<NpVerificationVideoScreen> createState() => _NpVerificationVideoScreenState();
}

class _NpVerificationVideoScreenState extends State<NpVerificationVideoScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _camera;
  bool _initialising = true;
  String? _initError;

  bool _recording = false;
  bool _stopping = false;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final camera = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!camera.isGranted || !mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _initError = 'Camera and microphone access are needed to record the verification video.';
      });
      return;
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw 'No camera on this device';
      // The back camera faces the customer across the table.
      final back = _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => _cameras.first);
      await _open(back);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _initError = 'The camera could not be started. $e';
      });
    }
  }

  Future<void> _open(CameraDescription description) async {
    final previous = _camera;
    setState(() => _camera = null);
    await previous?.dispose();
    // Medium (~480p): clear enough to see and hear the customer, small enough to upload.
    final controller = CameraController(description, ResolutionPreset.medium, enableAudio: true);
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _camera = controller;
      _initialising = false;
    });
  }

  Future<void> _flip() async {
    final cam = _camera;
    if (cam == null || _recording || _cameras.length < 2) return;
    final next = _cameras.firstWhere(
      (c) => c.lensDirection != cam.description.lensDirection,
      orElse: () => _cameras.first,
    );
    try {
      await _open(next);
    } catch (e) {
      _toast('Could not switch camera. $e');
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
    _elapsed
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_elapsed.elapsed.inSeconds >= NpVerificationVideoScreen.kMaxSeconds) {
        _stop();
      } else {
        setState(() {});
      }
    });
    setState(() => _recording = true);
  }

  Future<void> _stop() async {
    final cam = _camera;
    if (cam == null || !_recording || _stopping) return;
    final seconds = _elapsed.elapsed.inSeconds;
    if (seconds < NpVerificationVideoScreen.kMinSeconds) {
      _toast('Keep recording — the video must be at least ${NpVerificationVideoScreen.kMinSeconds} seconds.');
      return;
    }
    _stopping = true;
    _ticker?.cancel();
    _elapsed.stop();
    try {
      final file = await cam.stopVideoRecording();
      _recording = false;
      if (!mounted) return;
      Navigator.of(context).pop(NpVideoTake(path: file.path, durationSec: seconds));
    } catch (e) {
      _stopping = false;
      if (mounted) {
        setState(() => _recording = false);
        _toast('Recording could not be saved. $e');
      }
    }
  }

  Future<void> _discardAndLeave() async {
    final cam = _camera;
    _ticker?.cancel();
    _elapsed.stop();
    if (cam != null && _recording) {
      try {
        final f = await cam.stopVideoRecording();
        await File(f.path).delete();
      } catch (_) {
        // A partial file that cannot be removed is left to the OS temp cleaner.
      }
    }
    _recording = false;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop recording?'),
        content: const Text('This video will be discarded.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep recording')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Discard')),
        ],
      ),
    );
    if (leave == true) await _discardAndLeave();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final cam = _camera;
    if (cam != null) {
      if (_recording) {
        cam.stopVideoRecording().catchError((_) => XFile('')).whenComplete(cam.dispose);
      } else {
        cam.dispose();
      }
    }
    _elapsed.stop();
    super.dispose();
  }

  String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
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
          title: const Text('Verification video', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _recording ? _confirmLeave : () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_initialising) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (_initError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Text(_initError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: openAppSettings,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Open settings'),
          ),
        ]),
      );
    }
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final seconds = _elapsed.elapsed.inSeconds;
    final remaining = NpVerificationVideoScreen.kMaxSeconds - seconds;
    return Column(children: [
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: cam.value.previewSize?.height ?? 480,
              height: cam.value.previewSize?.width ?? 640,
              child: CameraPreview(cam),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: Text(
                _recording
                    ? 'Ask ${widget.candidateName} to state their name, confirm they have read and signed the '
                        'agreement, and that they have handed over two post-dated cheques.'
                    : 'Keep ${widget.candidateName}\'s face in frame and record in a quiet place. '
                        'Tap the red button to start.',
                style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35),
              ),
            ),
          ),
        ]),
      ),
      Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
        child: Row(children: [
          Expanded(
            child: _recording
                ? Row(children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 6),
                    Text(_clock(seconds), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    if (remaining <= 30) ...[
                      const SizedBox(width: 8),
                      Text('${remaining}s left', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                    ],
                  ])
                : const Text('Up to ${NpVerificationVideoScreen.kMaxSeconds ~/ 60} min',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5)),
          ),
          GestureDetector(
            onTap: _recording ? _stop : _start,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: _recording ? 28 : 56,
                height: _recording ? 28 : 56,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(_recording ? 6 : 28),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: _recording || _cameras.length < 2 ? null : _flip,
                icon: const Icon(Icons.cameraswitch_rounded),
                color: Colors.white,
                disabledColor: Colors.white24,
                tooltip: 'Switch camera',
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
