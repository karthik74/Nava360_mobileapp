import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme.dart';
import '../form_renderer.dart' show absoluteFileUrl;
import '../task_models.dart';
import 'video_qa_recorder_screen.dart';
import 'video_qa_review_screen.dart';

/// The `video_qa` form field: the script of questions before recording, and the
/// finished take (with its questions as chapters) afterwards.
class VideoQaField extends StatelessWidget {
  const VideoQaField({
    super.key,
    required this.label,
    required this.config,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final VideoQaConfig? config;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  Map<String, dynamic>? get _answer =>
      value is Map<String, dynamic> && (value['url'] as String?)?.isNotEmpty == true
          ? value as Map<String, dynamic>
          : null;

  /// Runs the recorder, then the review screen. A discarded take at either step
  /// leaves the field exactly as it was.
  Future<void> _record(BuildContext context) async {
    final cfg = config;
    if (cfg == null || !cfg.isUsable) return;
    // Resolved once, before any await: the loop pushes two routes in turn and
    // must not reach back into a BuildContext across those gaps.
    final navigator = Navigator.of(context);

    while (true) {
      final take = await navigator.push<VideoQaTake>(
        MaterialPageRoute(
          builder: (_) => VideoQaRecorderScreen(config: cfg, title: label),
        ),
      );
      if (take == null || !navigator.mounted) return;

      final result = await navigator.push<VideoQaUploadResult>(
        MaterialPageRoute(
          builder: (_) => VideoQaReviewScreen(
            take: take,
            title: label,
            allowRetake: cfg.allowRetake,
          ),
        ),
      );
      if (result != null) {
        onChanged(result.answer);
        return;
      }
      // Back from review without sending means "record again" — unless retakes
      // are off, in which case leaving review abandons the take.
      if (!cfg.allowRetake || !navigator.mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    final answer = _answer;

    if (answer != null) {
      return _RecordedAnswer(
        answer: answer,
        canReRecord: !readOnly && (cfg?.allowRetake ?? false) && (cfg?.isUsable ?? false),
        onReRecord: () => _record(context),
      );
    }

    if (cfg == null || !cfg.isUsable) {
      return Text(
        'No questions have been set for this recording yet.',
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${cfg.questions.length} question${cfg.questions.length == 1 ? '' : 's'} · '
                '${cfg.secondsPerQuestion}s to answer each',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < cfg.questions.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text('${i + 1}.',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ),
                      Expanded(
                        child: Text(cfg.questions[i].text,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (readOnly)
          Text('Not recorded.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12.5))
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _record(context),
              icon: const Icon(Icons.videocam_outlined, size: 18),
              label: const Text('Record answers'),
            ),
          ),
      ],
    );
  }
}

/// A finished recording: plays back, with each question seeking to its answer.
class _RecordedAnswer extends StatefulWidget {
  const _RecordedAnswer({
    required this.answer,
    required this.canReRecord,
    required this.onReRecord,
  });

  final Map<String, dynamic> answer;
  final bool canReRecord;
  final VoidCallback onReRecord;

  @override
  State<_RecordedAnswer> createState() => _RecordedAnswerState();
}

class _RecordedAnswerState extends State<_RecordedAnswer> {
  VideoPlayerController? _player;
  bool _failed = false;

  List<Map<String, dynamic>> get _chapters =>
      ((widget.answer['questions'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = (widget.answer['url'] as String?) ?? '';
    if (url.isEmpty) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(absoluteFileUrl(url)));
    try {
      await c.initialize();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      await c.dispose();
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
    super.dispose();
  }

  String _clock(num seconds) {
    final s = seconds.toInt().clamp(0, 1 << 30);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final duration = widget.answer['durationSec'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_failed)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Text('The recording could not be played on this device.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
          )
        else if (player != null && player.value.isInitialized)
          Column(
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
                        iconSize: 52,
                        color: Colors.white,
                        icon: Icon(player.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill),
                        onPressed: () =>
                            player.value.isPlaying ? player.pause() : player.play(),
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
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          ),

        if (duration is num) ...[
          const SizedBox(height: 6),
          Text('Recorded · ${_clock(duration)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],

        for (final c in _chapters)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: InkWell(
              onTap: player == null || !player.value.isInitialized
                  ? null
                  : () {
                      player.seekTo(Duration(seconds: (c['startSec'] as num?)?.toInt() ?? 0));
                      player.play();
                    },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(_clock((c['startSec'] as num?) ?? 0),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
                  Expanded(
                    child: Text((c['text'] as String?) ?? '',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),

        if (widget.canReRecord) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onReRecord,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Record again'),
          ),
        ],
      ],
    );
  }
}
