// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — Agreement & PDC submission (BM after DM approval).
//  Route: /np/candidates/:id/agreement
//
//  Rules (server-enforced, mirrored here): signed agreement scan + date, two
//  post-dated cheques each with a 6-digit cheque number and a scan, account +
//  IFSC required and identical on both cheques (PDC 2 mirrors PDC 1), cheque
//  numbers distinct. Amount and cheque date are not captured (cheques are
//  collected blank). A customer verification video — the customer speaking on
//  camera, recorded here — is required with every submission.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'np_models.dart';
import 'np_repository.dart';
import 'np_verification_video_screen.dart';
import 'np_widgets.dart';

final _ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

/// A ~480p take is already small; re-encode only what is actually big.
const int _compressOverBytes = 8 * 1024 * 1024;

class NpAgreementScreen extends ConsumerStatefulWidget {
  const NpAgreementScreen({super.key, required this.candidateId});
  final int candidateId;

  @override
  ConsumerState<NpAgreementScreen> createState() => _NpAgreementScreenState();
}

class _NpAgreementScreenState extends ConsumerState<NpAgreementScreen> {
  NpCandidateDetail? _d;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  DateTime _agreementDate = DateTime.now();
  NpPickedFile? _agreementFile;
  NpPickedFile? _pdc1File;
  NpPickedFile? _pdc2File;
  NpVideoTake? _video;
  VideoPlayerController? _player;
  String? _status;
  final _pdc1No = TextEditingController();
  final _pdc2No = TextEditingController();
  final _bankName = TextEditingController();
  final _ifsc = TextEditingController();
  final _account = TextEditingController();
  final _remarks = TextEditingController();

  int get _id => widget.candidateId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pdc1No.dispose();
    _pdc2No.dispose();
    _bankName.dispose();
    _ifsc.dispose();
    _account.dispose();
    _remarks.dispose();
    _player?.dispose();
    VideoCompress.cancelCompression();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(npRepositoryProvider).candidate(_id);
      if (!mounted) return;
      setState(() {
        _d = d;
        // Pre-fill the cheque account from the candidate's bank details.
        if (_bankName.text.isEmpty) _bankName.text = d.bankName ?? '';
        if (_ifsc.text.isEmpty) _ifsc.text = d.bankIfsc ?? '';
        if (_account.text.isEmpty) _account.text = d.bankAccountNumber ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validate() {
    if (_agreementFile == null) return 'Attach the signed agreement.';
    final ifsc = _ifsc.text.trim().toUpperCase();
    final account = _account.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(_pdc1No.text.trim())) return 'PDC 1 cheque number must be exactly 6 digits.';
    if (!RegExp(r'^\d{6}$').hasMatch(_pdc2No.text.trim())) return 'PDC 2 cheque number must be exactly 6 digits.';
    if (_pdc1No.text.trim() == _pdc2No.text.trim()) return 'The two PDCs cannot have the same cheque number.';
    if (account.isEmpty) return 'Enter the account number the cheques are drawn on.';
    if (!_ifscRe.hasMatch(ifsc)) return 'Enter a valid IFSC, e.g. SBIN0001234.';
    if (_pdc1File == null) return 'PDC 1 needs a scan.';
    if (_pdc2File == null) return 'PDC 2 needs a scan.';
    if (_video == null) return 'Record the customer verification video.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      npToast(context, problem, error: true);
      return;
    }
    if (!await npConfirm(context,
        title: 'Submit agreement & PDCs?', message: 'The file moves to OPS for verification.', confirmLabel: 'Submit')) {
      return;
    }
    setState(() => _busy = true);
    final ifsc = _ifsc.text.trim().toUpperCase();
    final account = _account.text.replaceAll(RegExp(r'\s'), '');
    final bank = _bankName.text.trim().isEmpty ? null : _bankName.text.trim();
    NpPdcInput pdc(String no) => NpPdcInput()
      ..chequeNumber = no.trim()
      ..bankName = bank
      ..ifsc = ifsc
      ..accountNumber = account;
    _player?.pause();
    try {
      final videoPath = await _uploadableVideo();
      if (mounted) setState(() => _status = 'Uploading…');
      await ref.read(npRepositoryProvider).submitAgreement(
            _id,
            agreementPath: _agreementFile!.path,
            pdc1Path: _pdc1File!.path,
            pdc2Path: _pdc2File!.path,
            videoPath: videoPath,
            agreementDate: npIsoDate(_agreementDate),
            pdc1: pdc(_pdc1No.text),
            pdc2: pdc(_pdc2No.text),
            remarks: _remarks.text,
          );
      if (!mounted) return;
      npToast(context, 'Agreement & PDCs submitted');
      context.pop(true);
    } catch (e) {
      if (mounted) npToast(context, 'Agreement submission failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  /// The recorded file, shrunk first when it is big. Compression is an
  /// optimisation: if the device cannot do it, the original is sent.
  Future<String> _uploadableVideo() async {
    final path = _video!.path;
    try {
      if (await File(path).length() <= _compressOverBytes) return path;
      if (mounted) setState(() => _status = 'Shrinking the video…');
      final info = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.Res640x480Quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 24,
      );
      return info?.path ?? path;
    } catch (_) {
      return path;
    }
  }

  Future<void> _record() async {
    final d = _d;
    if (d == null) return;
    _player?.pause();
    final take = await Navigator.of(context).push<NpVideoTake>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => NpVerificationVideoScreen(candidateName: d.fullName)),
    );
    if (take == null || !mounted) return;
    final old = _player;
    setState(() {
      _video = take;
      _player = null;
    });
    await old?.dispose();
    final c = VideoPlayerController.file(File(take.path));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      return; // Preview is a courtesy; the take is still attached.
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

  Future<void> _pick(void Function(NpPickedFile f) set) async {
    final f = await npPickAnyFile(context);
    if (f != null) setState(() => set(f));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final allowed = d?.can('SUBMIT_AGREEMENT') ?? false;
    final showForm = !_loading && d != null && allowed;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(context, title: 'Agreement & PDCs', subtitle: 'Signed agreement, two cheques and a video'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? Padding(padding: const EdgeInsets.all(16), child: AppErrorPanel(message: _error ?? 'Not found', onRetry: _load))
              : !allowed
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: ProEmpty(
                        icon: Icons.lock_outline_rounded,
                        title: 'Not available',
                        message: 'The agreement cannot be submitted at this stage (${d.statusLabel}).',
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        NpWhoCard(d: d),
                        const SizedBox(height: 14),
                        if (d.status == 'SENT_BACK_FOR_CORRECTION' && d.correctionRemarks != null) ...[
                          NpBanner(icon: Icons.undo_rounded, color: const Color(0xFFEA580C), title: 'Sent back — resubmit the agreement', body: d.correctionRemarks),
                          const SizedBox(height: 14),
                        ],
                        _card('Signed agreement', [
                          const NpFieldLabel('Agreement date', required: true),
                          InkWell(
                            onTap: () async {
                              final p = await showDatePicker(context: context, initialDate: _agreementDate, firstDate: DateTime(2020), lastDate: DateTime(2035));
                              if (p != null) setState(() => _agreementDate = p);
                            },
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            child: InputDecorator(
                              decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                              child: Text(npFmtDate(_agreementDate), style: const TextStyle(fontSize: 15, color: AppColors.ink)),
                            ),
                          ),
                          NpFilePickField(
                            label: 'Signed agreement scan',
                            fileName: _agreementFile?.name,
                            onPick: () => _pick((f) => _agreementFile = f),
                          ),
                        ]),
                        _card('Cheque account', help: 'Both post-dated cheques are drawn on this account.', [
                          const NpFieldLabel('Bank name'),
                          TextField(controller: _bankName, textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()]),
                          const NpFieldLabel('Account number', required: true),
                          TextField(controller: _account, keyboardType: TextInputType.number),
                          const NpFieldLabel('IFSC', required: true),
                          TextField(
                            controller: _ifsc,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [const UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(11)],
                            decoration: const InputDecoration(hintText: 'SBIN0001234'),
                          ),
                        ]),
                        _pdcCard(1, _pdc1No, _pdc1File, (f) => _pdc1File = f),
                        _pdcCard(2, _pdc2No, _pdc2File, (f) => _pdc2File = f),
                        _videoCard(),
                        _card('Remarks', [
                          const SizedBox(height: 8),
                          TextField(
                            controller: _remarks,
                            minLines: 2,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(hintText: 'Anything OPS should know'),
                          ),
                        ]),
                      ],
                    ),
      bottomNavigationBar: !showForm
          ? null
          : ProBottomBar(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_busy ? (_status ?? 'Uploading…') : 'Submit agreement & PDCs'),
              ),
            ]),
    );
  }

  Widget _pdcCard(int seq, TextEditingController no, NpPickedFile? file, void Function(NpPickedFile f) setFile) => _card(
        'PDC $seq',
        icon: Icons.payments_outlined,
        [
          const NpFieldLabel('Cheque number', required: true),
          TextField(
            controller: no,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: const InputDecoration(hintText: '6 digits'),
          ),
          NpFilePickField(label: 'Cheque scan', fileName: file?.name, onPick: () => _pick(setFile)),
        ],
      );

  Widget _videoCard() {
    final take = _video;
    final player = _player;
    String clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return _card(
      'Customer verification video',
      help: 'Record the customer speaking on camera — their name, and that they have signed the agreement '
          'and handed over the cheques.',
      [
        const SizedBox(height: 12),
        if (take != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: AppColors.deep,
              height: 220,
              alignment: Alignment.center,
              child: player == null || !player.value.isInitialized
                  ? const Icon(Icons.videocam_outlined, color: Colors.white38, size: 40)
                  : Stack(alignment: Alignment.center, children: [
                      AspectRatio(aspectRatio: player.value.aspectRatio, child: VideoPlayer(player)),
                      IconButton(
                        iconSize: 56,
                        color: Colors.white,
                        tooltip: player.value.isPlaying ? 'Pause' : 'Play',
                        onPressed: () => player.value.isPlaying ? player.pause() : player.play(),
                        icon: Icon(player.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                      ),
                    ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Recorded · ${clock(take.durationSec)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _record,
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('Re-record'),
            ),
          ]),
        ] else
          OutlinedButton.icon(
            onPressed: _busy ? null : _record,
            icon: const Icon(Icons.videocam_outlined, size: 18),
            label: const Text('Record video'),
          ),
      ],
    );
  }

  Widget _card(String title, List<Widget> children, {String? help, IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (icon != null) ...[ProIconWell(icon: icon, color: AppColors.primary, size: 30), const SizedBox(width: 10)],
              Expanded(child: Text(title, style: AppText.section)),
            ]),
            if (help != null) ...[
              const SizedBox(height: 3),
              Text(help, style: AppText.caption),
            ],
            ...children,
          ]),
        ),
      );
}
