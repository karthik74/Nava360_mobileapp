import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'whistleblower_models.dart';

/// Evidence picker: record voice, capture/select images, attach PDFs — with
/// in-app previews and remove-before-submit. Mutates [evidence] and calls
/// [onChanged] so the parent re-renders.
class EvidenceSection extends StatelessWidget {
  const EvidenceSection({super.key, required this.evidence, required this.onChanged});
  final List<EvidenceFile> evidence;
  final VoidCallback onChanged;

  Future<void> _recordVoice(BuildContext context) async {
    final result = await showModalBottomSheet<EvidenceFile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RecordVoiceSheet(),
    );
    if (result != null) {
      evidence.add(result);
      onChanged();
    }
  }

  Future<void> _addImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _SheetHandle()),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Add image',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.35,
                      color: AppColors.ink)),
            ),
            const SizedBox(height: 12),
            ProListGroup(
              children: [
                ProListRow(
                  leading: ProIconWell(icon: Icons.photo_camera_outlined, color: AppColors.primary),
                  title: 'Take a photo',
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ProListRow(
                  leading: const ProIconWell(icon: Icons.photo_library_outlined, color: AppColors.info),
                  title: 'Choose from gallery',
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 2000);
    if (picked == null) return;
    evidence.add(EvidenceFile(path: picked.path, fileName: _name(picked.path, 'jpg'), category: 'image'));
    onChanged();
  }

  Future<void> _addDocument(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    evidence.add(EvidenceFile(path: path, fileName: _name(path, 'pdf'), category: 'document'));
    onChanged();
  }

  static String _name(String path, String fallbackExt) {
    final base = path.split(Platform.pathSeparator).last;
    return base.contains('.') ? base : '$base.$fallbackExt';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProSectionHeader(
          title: 'Add proof or evidence',
          subtitle: 'Optional — keep it genuine and relevant',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _EvidenceButton(
                  icon: Icons.mic_none_rounded,
                  label: 'Record voice',
                  color: AppColors.primary,
                  onTap: () => _recordVoice(context)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _EvidenceButton(
                  icon: Icons.add_a_photo_outlined,
                  label: 'Add image',
                  color: AppColors.info,
                  onTap: () => _addImage(context)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _EvidenceButton(
                  icon: Icons.attach_file_rounded,
                  label: 'Add document',
                  color: const Color(0xFF4253A8),
                  onTap: () => _addDocument(context)),
            ),
          ],
        ),
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (int i = 0; i < evidence.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _EvidenceTile(
                file: evidence[i],
                onRemove: () {
                  evidence.removeAt(i);
                  onChanged();
                },
              ),
            ),
        ],
      ],
    );
  }
}

/// White hairline tile with a tinted icon well (Record voice / Add image / …).
class _EvidenceButton extends StatelessWidget {
  const _EvidenceButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ProIconWell(icon: icon, color: color, size: 40),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.file, required this.onRemove});
  final EvidenceFile file;
  final VoidCallback onRemove;

  String get _sub {
    switch (file.category) {
      case 'image':
        return 'Photo';
      case 'audio':
        final s = file.durationSeconds;
        if (s == null) return 'Voice message';
        final m = (s ~/ 60).toString().padLeft(2, '0');
        final r = (s % 60).toString().padLeft(2, '0');
        return 'Voice message · $m:$r';
      default:
        return 'PDF document';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          if (file.category == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(file.path), width: 44, height: 44, fit: BoxFit.cover),
            )
          else if (file.category == 'audio')
            ProIconWell(icon: Icons.graphic_eq_rounded, color: AppColors.primary, size: 44)
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.infoTint,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_outlined, size: 18, color: AppColors.info),
                  Text('PDF',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.info)),
                ],
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: file.category == 'audio'
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WbAudioPlayer(path: file.path, label: 'Voice message'),
                      if (file.durationSeconds != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 38),
                          child: Text(_sub, style: AppText.caption),
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w500, color: AppColors.ink),
                      ),
                      Text(_sub, style: AppText.caption),
                    ],
                  ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, color: AppColors.muted, size: 20),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

/// A compact play/pause control for a local (or already-downloaded) audio file.
class WbAudioPlayer extends StatefulWidget {
  const WbAudioPlayer({super.key, required this.path, required this.label});
  final String path;
  final String label;

  @override
  State<WbAudioPlayer> createState() => _WbAudioPlayerState();
}

class _WbAudioPlayerState extends State<WbAudioPlayer> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(widget.path));
      if (mounted) setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: _playing ? 'Pause' : 'Play',
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(20),
            child: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: AppColors.primary, size: 30),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(widget.label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: AppColors.ink)),
        ),
      ],
    );
  }
}

/// Records a voice note, shows the running time, lets the user stop/cancel.
class _RecordVoiceSheet extends StatefulWidget {
  const _RecordVoiceSheet();

  @override
  State<_RecordVoiceSheet> createState() => _RecordVoiceSheetState();
}

class _RecordVoiceSheetState extends State<_RecordVoiceSheet> {
  final _recorder = AudioRecorder();
  Timer? _timer;
  int _seconds = 0;
  bool _started = false;
  String? _error;
  String? _path;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Microphone permission is required to record your voice message.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/wb_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _path = path;
      _started = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
      setState(() {});
    } catch (e) {
      setState(() => _error = 'Could not start recording: $e');
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    await _recorder.dispose();
    final secs = _seconds;
    if (!mounted) return;
    final p = path ?? _path;
    if (p == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      EvidenceFile(
        path: p,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        category: 'audio',
        durationSeconds: secs,
      ),
    );
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try {
      if (_started) await _recorder.stop();
      await _recorder.dispose();
      if (_path != null) {
        final f = File(_path!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  String get _elapsed {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 16),
          if (_error != null) ...[
            ProNote(_error!, tone: ProNoteTone.warn),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ),
          ] else ...[
            const Text('Recording voice message',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.35,
                    color: AppColors.ink)),
            const SizedBox(height: 18),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic_rounded, color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: 12),
            Text(_elapsed,
                style: const TextStyle(
                  fontSize: 32,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  color: AppColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_started) const ProPulseDot(color: AppColors.live, size: 7),
                const SizedBox(width: 4),
                Text(_started ? 'Recording' : 'Starting…', style: AppText.caption),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _started ? _stop : null,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Stop & save'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 40×5 drag handle for the white bottom sheets.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFFC6D3D6),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}
