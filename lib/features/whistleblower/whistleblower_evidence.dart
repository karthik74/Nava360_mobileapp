import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
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
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_rounded, color: AppColors.primary),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'Add Proof / Evidence', subtitle: 'Optional — keep it genuine and relevant'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _EvidenceButton(icon: Icons.mic_rounded, label: 'Record Voice', onTap: () => _recordVoice(context)),
            _EvidenceButton(icon: Icons.add_a_photo_rounded, label: 'Add Image', onTap: () => _addImage(context)),
            _EvidenceButton(icon: Icons.attach_file_rounded, label: 'Add Document', onTap: () => _addDocument(context)),
          ],
        ),
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (int i = 0; i < evidence.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
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

class _EvidenceButton extends StatelessWidget {
  const _EvidenceButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.file, required this.onRemove});
  final EvidenceFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          if (file.category == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(file.path), width: 44, height: 44, fit: BoxFit.cover),
            )
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                file.category == 'audio' ? Icons.graphic_eq_rounded : Icons.picture_as_pdf_rounded,
                color: AppColors.primary,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: file.category == 'audio'
                ? WbAudioPlayer(path: file.path, label: 'Voice message')
                : Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
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
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(20),
          child: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
              color: AppColors.primary, size: 30),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(widget.label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            AppErrorPanel(message: _error!),
            const SizedBox(height: 14),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ] else ...[
            const Text('Recording voice message',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 18),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded, color: AppColors.danger, size: 34),
            ),
            const SizedBox(height: 12),
            Text(_elapsed,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _started ? _stop : null,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Stop & Save'),
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
