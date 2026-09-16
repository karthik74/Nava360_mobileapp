import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme.dart';
import '../../files/file_repository.dart';
import 'video_qa_recorder_screen.dart';

/// Watch the take back, then send it. Nothing is attached to the task until the
/// upload succeeds, so a failed send leaves the recording here to retry rather
/// than half-attached to the form.
class VideoQaReviewScreen extends ConsumerStatefulWidget {
  const VideoQaReviewScreen({
    super.key,
    required this.take,
    required this.title,
    required this.allowRetake,
  });

  final VideoQaTake take;
  final String title;
  final bool allowRetake;

  @override
  ConsumerState<VideoQaReviewScreen> createState() => _VideoQaReviewScreenState();
}

/// What the review screen hands back to the form field.
class VideoQaUploadResult {
  const VideoQaUploadResult({required this.answer});

  /// The form value: a file ref (id/url/name/contentType) carrying the take's
  /// duration and question marks, so every screen that already knows how to
  /// show a stored file handles it unchanged.
  final Map<String, dynamic> answer;
}

class _VideoQaReviewScreenState extends ConsumerState<VideoQaReviewScreen> {
  /// A ~480p take of a couple of minutes is already small; re-encoding it only
  /// costs the person time. Compress only what is actually big.
  static const int _compressOverBytes = 8 * 1024 * 1024;

  VideoPlayerController? _player;
  bool _busy = false;
  String? _status;
  String? _error;
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _readSize();
  }

  Future<void> _readSize() async {
    try {
      final n = await File(widget.take.path).length();
      if (mounted) setState(() => _bytes = n);
    } catch (_) {
      // Size is only shown as a courtesy; the upload does not depend on it.
    }
  }

  Future<void> _initPlayer() async {
    final c = VideoPlayerController.file(File(widget.take.path));
    try {
      await c.initialize();
    } catch (_) {
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _player = c);
  }

  @override
  void dispose() {
    _player?.pause();
    _player?.dispose();
    VideoCompress.cancelCompression();
    super.dispose();
  }

  String _size(int? bytes) {
    if (bytes == null) return '';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  String _clock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _player?.pause();

    var path = widget.take.path;
    try {
      final size = _bytes ?? await File(path).length();
      if (size > _compressOverBytes) {
        setState(() => _status = 'Shrinking the video…');
        final info = await VideoCompress.compressVideo(
          path,
          quality: VideoQuality.Res640x480Quality,
          deleteOrigin: false,
          includeAudio: true,
          frameRate: 24,
        );
        // Compression is an optimisation, not a requirement: if the device
        // cannot do it, send what we recorded.
        if (info?.path != null) path = info!.path!;
      }

      setState(() => _status = 'Uploading…');
      final uploaded = await ref.read(fileRepositoryProvider).upload(
            path,
            filename: 'video-answers-${DateTime.now().millisecondsSinceEpoch}.mp4',
          );

      final answer = <String, dynamic>{
        ...uploaded.toJson(),
        'durationSec': widget.take.durationSec,
        'recordedAt': DateTime.now().toIso8601String(),
        'questions': widget.take.marks.map((m) => m.toJson()).toList(),
      };
      if (!mounted) return;
      Navigator.of(context).pop(VideoQaUploadResult(answer: answer));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _error = 'Could not send the recording. $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (player != null && player.value.isInitialized)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: player.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(player),
                        IconButton(
                          iconSize: 56,
                          color: Colors.white,
                          icon: Icon(player.value.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill),
                          onPressed: () => player.value.isPlaying
                              ? player.pause()
                              : player.play(),
                        ),
                      ],
                    ),
                  ),
                ),
                VideoProgressIndicator(player, allowScrubbing: true),
              ],
            )
          else
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),

          const SizedBox(height: 10),
          Text(
            '${_clock(widget.take.durationSec)} · ${_size(_bytes)}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),

          const SizedBox(height: 16),
          const Text('Questions asked',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final m in widget.take.marks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                // Tapping a question jumps to the answer, the same way the web
                // review screen does with the stored offsets.
                onTap: player == null || !player.value.isInitialized
                    ? null
                    : () {
                        player.seekTo(Duration(seconds: m.startSec));
                        player.play();
                      },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(_clock(m.startSec),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                    ),
                    Expanded(child: Text(m.text, style: const TextStyle(fontSize: 13.5))),
                  ],
                ),
              ),
            ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
          ],

          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_busy ? (_status ?? 'Working…') : (_error == null ? 'Use this recording' : 'Try again')),
          ),
          if (widget.allowRetake) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Record again'),
            ),
          ],
        ],
      ),
    );
  }
}
