// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — the candidate file: header, 13-step stepper, one panel per
//  step with its actions, audit trail. Route: /np/candidates/:id
//
//  Actions render ONLY from the server-computed `allowedActions` (status ×
//  caller permissions × scope), exactly like the web detail page. The BGV
//  visit report and the Agreement & PDC submission open dedicated screens.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/branding.dart';
import '../../core/employee_lookup.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'np_models.dart';
import 'np_repository.dart';
import 'np_widgets.dart';

class NpCandidateDetailScreen extends ConsumerStatefulWidget {
  const NpCandidateDetailScreen({super.key, required this.candidateId});
  final int candidateId;

  @override
  ConsumerState<NpCandidateDetailScreen> createState() => _NpCandidateDetailScreenState();
}

class _NpCandidateDetailScreenState extends ConsumerState<NpCandidateDetailScreen> {
  NpCandidateDetail? _d;
  List<NpAuditLog> _audit = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _open = <String>{};
  bool _initialised = false;

  // per-step form state
  final _orientItems = <String, bool>{};
  DateTime _orientDate = DateTime.now();
  final _orientRemarks = TextEditingController();

  DateTime _ivDate = DateTime.now();
  EmployeeLookup? _ivInterviewer;
  String? _ivResult;
  final _ivRemarks = TextEditingController();

  String _cbResult = 'APPROVED';
  final _cbRef = TextEditingController();
  final _cbScore = TextEditingController();
  final _cbRemarks = TextEditingController();

  final _opsChecks = <String, bool>{for (final k in kNpOpsChecklistKeys) k: false};
  String _opsSendBack = 'KYC';

  final _otpMobile = TextEditingController();
  final _otpCode = TextEditingController();
  bool _otpSent = false;
  String? _deviceModel;
  String? _deviceOs;
  String? _deviceId;
  String? _appVersion;

  final _esaf = TextEditingController();

  int get _id => widget.candidateId;

  @override
  void initState() {
    super.initState();
    _load();
    _readDevice();
  }

  @override
  void dispose() {
    _orientRemarks.dispose();
    _ivRemarks.dispose();
    _cbRef.dispose();
    _cbScore.dispose();
    _cbRemarks.dispose();
    _otpMobile.dispose();
    _otpCode.dispose();
    _esaf.dispose();
    super.dispose();
  }

  Future<void> _readDevice() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        _deviceModel = '${a.manufacturer} ${a.model}'.trim();
        _deviceOs = 'Android ${a.version.release}';
        _deviceId = a.id;
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _deviceModel = i.utsname.machine;
        _deviceOs = 'iOS ${i.systemVersion}';
        _deviceId = i.identifierForVendor;
      }
      final p = await PackageInfo.fromPlatform();
      _appVersion = '${p.version}+${p.buildNumber}';
    } catch (_) {
      // Device details are optional on the activation record.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _d == null;
      _error = null;
    });
    try {
      final d = await ref.read(npRepositoryProvider).candidate(_id);
      if (!mounted) return;
      _apply(d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(NpCandidateDetail d) {
    setState(() {
      _d = d;
      for (final k in kNpOpsChecklistKeys) {
        _opsChecks[k] = d.opsChecklist[k] ?? false;
      }
      if (_otpMobile.text.isEmpty) _otpMobile.text = d.mobileNumber;
      if (_esaf.text.isEmpty && d.esafId != null) _esaf.text = d.esafId!;
      if (!_initialised) {
        _orientItems.addAll(d.orientationItems);
        if (d.orientationDate != null) _orientDate = d.orientationDate!;
        _orientRemarks.text = d.orientationRemarks ?? '';
        _open.add(d.step);
        _initialised = true;
      }
    });
    if (d.can('VIEW_AUDIT')) {
      ref.read(npRepositoryProvider).audit(_id).then((rows) {
        if (mounted) setState(() => _audit = rows);
      }).catchError((_) {});
    }
  }

  /// Every action funnels through here: busy → call → toast → apply.
  Future<void> _run(String label, Future<NpCandidateDetail> Function() fn, {String? success}) async {
    setState(() => _busy = true);
    try {
      final next = await fn();
      if (!mounted) return;
      _apply(next);
      npToast(context, success ?? '$label done');
    } catch (e) {
      if (mounted) npToast(context, '$label failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String step) => setState(() => _open.contains(step) ? _open.remove(step) : _open.add(step));

  // ── actions ──

  Future<void> _delete() async {
    final d = _d!;
    if (!await npConfirm(context,
        title: 'Delete candidate?',
        message: 'Delete ${d.fullName} (${d.candidateCode})? This cannot be undone.',
        confirmLabel: 'Delete',
        danger: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(npRepositoryProvider).delete(_id);
      if (!mounted) return;
      npToast(context, 'Candidate deleted');
      context.pop(true);
    } catch (e) {
      if (mounted) {
        npToast(context, 'Delete failed: $e', error: true);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _identify() async {
    if (!await npConfirm(context,
        title: 'Submit as identified?',
        message: 'The file moves to orientation. Details stay editable until the CB check.',
        confirmLabel: 'Submit')) {
      return;
    }
    await _run('Identification', () => ref.read(npRepositoryProvider).identify(_id));
  }

  Future<void> _orientation(List<String> items) async {
    if (items.isNotEmpty && !items.every((i) => _orientItems[i] == true)) {
      npToast(context, 'Every orientation item must be covered before you can mark it complete.', error: true);
      return;
    }
    if (!await npConfirm(context, title: 'Mark orientation completed?')) return;
    await _run(
      'Orientation',
      () => ref.read(npRepositoryProvider).orientation(
            _id,
            orientationDate: npIsoDate(_orientDate),
            items: {for (final i in items) i: _orientItems[i] == true},
            remarks: _orientRemarks.text.trim().isEmpty ? null : _orientRemarks.text.trim(),
          ),
    );
  }

  Future<void> _interview() async {
    final result = _ivResult;
    if (result == null) {
      npToast(context, 'Select whether the candidate passed or failed.', error: true);
      return;
    }
    if (result == 'REJECT' && _ivRemarks.text.trim().isEmpty) {
      npToast(context, 'Enter why the candidate failed the interview.', error: true);
      return;
    }
    final pass = result == 'PASS';
    if (!await npConfirm(context,
        title: pass ? 'Record interview as passed?' : 'Record interview as failed?',
        message: pass ? 'The file moves to KYC document collection.' : 'This ends the onboarding for this candidate and cannot be undone.',
        confirmLabel: pass ? 'Record pass' : 'Record fail',
        danger: !pass)) {
      return;
    }
    await _run(
      pass ? 'Interview' : 'Interview rejection',
      () => ref.read(npRepositoryProvider).interview(
            _id,
            interviewDate: npIsoDate(_ivDate),
            interviewerId: _ivInterviewer?.id,
            result: result,
            remarks: _ivRemarks.text.trim().isEmpty ? null : _ivRemarks.text.trim(),
          ),
    );
  }

  Future<void> _deleteDoc(NpDocument doc) async {
    if (!await npConfirm(context,
        title: 'Remove document?',
        message: '${doc.docTypeLabel} will be superseded. Upload a replacement afterwards.',
        confirmLabel: 'Remove',
        danger: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(npRepositoryProvider).deleteDocument(_id, doc.id);
      await _load();
      if (mounted) npToast(context, 'Document removed');
    } catch (e) {
      if (mounted) npToast(context, 'Remove failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyDoc(NpDocument doc) async {
    setState(() => _busy = true);
    try {
      await ref.read(npRepositoryProvider).verifyDocument(_id, doc.id);
      await _load();
      if (mounted) npToast(context, 'Document verified');
    } catch (e) {
      if (mounted) npToast(context, 'Verify failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadKyc(NpConfig config) async {
    final ok = await npUploadDocumentSheet(context, ref, candidateId: _id, docTypes: config.docTypesFor('KYC'));
    if (ok) {
      await _load();
      if (mounted) npToast(context, 'Document uploaded');
    }
  }

  Future<void> _submitDocuments() async {
    if (!await npConfirm(context, title: 'Submit KYC documents?', confirmLabel: 'Submit')) return;
    await _run('Document submission', () => ref.read(npRepositoryProvider).submitDocuments(_id));
  }

  Future<void> _submitCb() async {
    if (!await npConfirm(context,
        title: 'Submit for CB check?', message: 'A credit-bureau request is raised for this candidate.', confirmLabel: 'Submit')) {
      return;
    }
    setState(() => _busy = true);
    try {
      final next = await ref.read(npRepositoryProvider).submitCbCheck(_id);
      if (!mounted) return;
      _apply(next);
      final latest = next.cbChecks.isEmpty ? null : next.cbChecks.last;
      if (latest?.status == 'ERROR') {
        npToast(context, latest?.remarks ?? 'The credit bureau check could not be raised. Try again.', error: true);
      } else if (latest?.status == 'REJECTED') {
        npToast(context, 'Credit bureau rejected${latest?.score != null ? ' (score ${latest!.score})' : ''}: ${latest?.remarks ?? ''}', error: true);
      } else if (latest?.status == 'APPROVED') {
        npToast(context, 'Credit bureau approved${latest?.score != null ? ' (score ${latest!.score})' : ''}');
      } else {
        npToast(context, 'CB submission done');
      }
    } catch (e) {
      if (mounted) npToast(context, 'CB submission failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cbResultAction() async {
    if (_cbResult == 'REJECTED' && _cbRemarks.text.trim().isEmpty) {
      npToast(context, 'Remarks are required when the CB result is a rejection.', error: true);
      return;
    }
    final approved = _cbResult == 'APPROVED';
    if (!await npConfirm(context,
        title: approved ? 'Record CB approval?' : 'Record CB rejection?',
        message: approved ? 'The file moves straight to background verification.' : 'This ends the onboarding for this candidate.',
        confirmLabel: 'Record',
        danger: !approved)) {
      return;
    }
    await _run(
      'CB result',
      () => ref.read(npRepositoryProvider).recordCbResult(
            _id,
            status: _cbResult,
            referenceNo: _cbRef.text.trim().isEmpty ? null : _cbRef.text.trim(),
            score: _cbScore.text.trim().isEmpty ? null : _cbScore.text.trim(),
            remarks: _cbRemarks.text.trim().isEmpty ? null : _cbRemarks.text.trim(),
          ),
    );
  }

  Future<void> _openBgv() async {
    await context.push('/np/candidates/$_id/bgv');
    _load();
  }

  Future<void> _rejectBgv() async {
    final remarks = await npPrompt(context, title: 'Reject at BGV', label: 'Reason for rejection', confirmLabel: 'Reject', danger: true);
    if (remarks == null) return;
    await _run('BGV rejection', () => ref.read(npRepositoryProvider).rejectBgv(_id, remarks));
  }

  Future<void> _dmApprove() async {
    if (!await npConfirm(context, title: 'Approve as DM?', message: 'The file moves to agreement & PDC collection.', confirmLabel: 'Approve')) {
      return;
    }
    final remarks = await npPrompt(context, title: 'DM approval remarks', label: 'Remarks (optional)', required: false, confirmLabel: 'Approve');
    if (remarks == null) return;
    await _run('DM approval',
        () => ref.read(npRepositoryProvider).dmDecision(_id, action: 'APPROVE', remarks: remarks.isEmpty ? null : remarks));
  }

  Future<void> _dmSendBack() async {
    final remarks = await npPrompt(context,
        title: 'Send back for correction', label: 'What must the AM redo at the BGV stage?', confirmLabel: 'Send back');
    if (remarks == null) return;
    await _run('Send back', () => ref.read(npRepositoryProvider).dmDecision(_id, action: 'SEND_BACK', sendBackStage: 'BGV', remarks: remarks));
  }

  Future<void> _dmReject() async {
    final remarks = await npPrompt(context, title: 'Reject candidate', label: 'Reason for rejection', confirmLabel: 'Reject', danger: true);
    if (remarks == null) return;
    if (!await npConfirm(context,
        title: 'Reject this candidate?', message: 'This ends the onboarding and cannot be undone.', confirmLabel: 'Reject', danger: true)) {
      return;
    }
    await _run('DM rejection', () => ref.read(npRepositoryProvider).dmDecision(_id, action: 'REJECT', remarks: remarks));
  }

  Future<void> _openAgreement() async {
    await context.push('/np/candidates/$_id/agreement');
    _load();
  }

  Future<void> _opsApprove() async {
    if (!kNpOpsChecklistKeys.every((k) => _opsChecks[k] == true)) {
      npToast(context, 'Tick every checklist item before approving.', error: true);
      return;
    }
    if (!await npConfirm(context,
        title: 'Approve and generate the NP ID?', message: 'The NP ID is generated immediately and cannot be regenerated.', confirmLabel: 'Approve')) {
      return;
    }
    await _run('OPS approval', () => ref.read(npRepositoryProvider).opsDecision(_id, action: 'APPROVE', checklist: Map.of(_opsChecks)));
  }

  Future<void> _opsSendBackAction() async {
    final remarks = await npPrompt(context,
        title: 'Send back to ${npTitle(_opsSendBack)}', label: 'What must be corrected?', confirmLabel: 'Send back');
    if (remarks == null) return;
    await _run(
        'Send back',
        () => ref
            .read(npRepositoryProvider)
            .opsDecision(_id, action: 'SEND_BACK', sendBackStage: _opsSendBack, checklist: Map.of(_opsChecks), remarks: remarks));
  }

  Future<void> _opsReject() async {
    final remarks = await npPrompt(context, title: 'Reject at OPS', label: 'Reason for rejection', confirmLabel: 'Reject', danger: true);
    if (remarks == null) return;
    await _run('OPS rejection',
        () => ref.read(npRepositoryProvider).opsDecision(_id, action: 'REJECT', checklist: Map.of(_opsChecks), remarks: remarks));
  }

  Future<void> _resubmit() async {
    if (!await npConfirm(context,
        title: 'Resubmit for review?', message: 'The file returns to the reviewer who sent it back.', confirmLabel: 'Resubmit')) {
      return;
    }
    await _run('Resubmission', () => ref.read(npRepositoryProvider).resubmit(_id));
  }

  Future<void> _sendOtp() async {
    final m = _otpMobile.text.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(m)) {
      npToast(context, 'Enter a valid 10-digit mobile number.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(npRepositoryProvider).sendActivationOtp(_id, m);
      if (!mounted) return;
      setState(() => _otpSent = true);
      npToast(context, 'OTP sent to ${r.maskedMobile}');
      await _load();
    } catch (e) {
      if (mounted) npToast(context, 'Could not send the OTP: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCode.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      npToast(context, 'Enter the 6-digit OTP.', error: true);
      return;
    }
    await _run(
      'Activation',
      () => ref.read(npRepositoryProvider).verifyActivationOtp(
            _id,
            otp: otp,
            deviceModel: _deviceModel,
            deviceOs: _deviceOs,
            deviceId: _deviceId,
            appVersion: _appVersion,
          ),
      success: 'App activated',
    );
    _otpCode.clear();
  }

  Future<void> _activationException() async {
    final reason = await npPrompt(context,
        title: 'Record an activation exception', label: 'Why can the app not be activated by OTP?', confirmLabel: 'Record');
    if (reason == null) return;
    await _run('Activation exception', () => ref.read(npRepositoryProvider).activationException(_id, reason));
  }

  Future<void> _saveEsaf() async {
    if (_esaf.text.trim().isEmpty) {
      npToast(context, 'Enter the ESAF ID.', error: true);
      return;
    }
    if (!await npConfirm(context, title: 'Save the ESAF ID?', confirmLabel: 'Save')) return;
    await _run('ESAF ID', () => ref.read(npRepositoryProvider).createEsafId(_id, _esaf.text.trim()), success: 'ESAF ID saved');
  }

  Future<void> _finalActivate() async {
    if (!await npConfirm(context,
        title: 'Mark as Active NP?', message: 'Every mandatory artefact is re-checked on the server before activation.', confirmLabel: 'Activate')) {
      return;
    }
    await _run('Final activation', () => ref.read(npRepositoryProvider).finalActivate(_id), success: 'Candidate is now an Active NP');
  }

  // ── render ──

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(npConfigProvider).asData?.value ?? NpConfig.empty;
    final d = _d;
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(d?.candidateCode ?? 'NP candidate'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
          actions: [
            if (d != null && d.can('EDIT'))
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded),
                onPressed: _busy
                    ? null
                    : () async {
                        final changed = await context.push<bool>('/np/candidates/$_id/edit');
                        if (changed == true) _load();
                      },
              ),
            if (d != null && d.can('DELETE'))
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger), onPressed: _busy ? null : _delete),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _busy ? null : _load),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : d == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: AppErrorPanel(message: _error ?? 'NP candidate not found', onRetry: _load),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        _header(d),
                        if (_error != null) ...[const SizedBox(height: 10), AppErrorPanel(message: _error!, onRetry: _load)],
                        if (d.status == 'SENT_BACK_FOR_CORRECTION') ...[const SizedBox(height: 10), _correctionBanner(d)],
                        if (d.rejected) ...[const SizedBox(height: 10), _rejectionBanner(d)],
                        const SizedBox(height: 10),
                        GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: NpStepper(steps: d.steps, selected: d.step, onSelect: (s) => setState(() => _open.add(s))),
                        ),
                        const SizedBox(height: 10),
                        _panel(1, 'CANDIDATE', d, _candidatePanel(d)),
                        _panel(2, 'ORIENTATION', d, _orientationPanel(d, config)),
                        _panel(3, 'INTERVIEW', d, _interviewPanel(d)),
                        _panel(4, 'KYC', d, _kycPanel(d, config)),
                        _panel(5, 'CB', d, _cbPanel(d)),
                        _panel(6, 'BGV', d, _bgvPanel(d)),
                        _panel(7, 'DM_APPROVAL', d, _dmPanel(d)),
                        _panel(8, 'AGREEMENT_PDC', d, _agreementPanel(d)),
                        _panel(9, 'OPS', d, _opsPanel(d)),
                        _panel(10, 'NP_ID', d, _npIdPanel(d)),
                        _panel(11, 'NAVA360', d, _activationPanel(d)),
                        _panel(12, 'ESAF', d, _esafPanel(d)),
                        _panel(13, 'ACTIVATION', d, _finalPanel(d)),
                        if (d.supersededDocuments.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          GlassCard(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              const AppSectionHeader(title: 'Replaced documents'),
                              const SizedBox(height: 8),
                              NpDocumentList(documents: d.supersededDocuments),
                            ]),
                          ),
                        ],
                        if (d.can('VIEW_AUDIT')) ...[const SizedBox(height: 10), _auditCard()],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _panel(int index, String step, NpCandidateDetail d, List<Widget> children) {
    final info = kNpSteps[index - 1];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NpStepPanel(
        index: index,
        title: info.label,
        view: d.stepView(step),
        open: _open.contains(step),
        onToggle: () => _toggle(step),
        children: children,
      ),
    );
  }

  Widget _header(NpCandidateDetail d) {
    final photo = Env.fileUrl(d.photo?.url);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 64,
              height: 64,
              color: AppColors.surfaceAlt,
              child: photo == null
                  ? const Icon(Icons.person_rounded, size: 32, color: AppColors.muted)
                  : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: AppColors.muted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text('${d.candidateCode} · ${d.mobileNumber}', style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              if (d.orgLine.isNotEmpty) Text(d.orgLine, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          NpStatusPill(status: d.status, label: d.statusLabel),
          if (d.npId != null) StatusPill(label: 'NP ID ${d.npId}', color: AppColors.primary, icon: Icons.badge_rounded),
          if (d.esafId != null) StatusPill(label: 'ESAF ${d.esafId}', color: AppColors.info),
          if (d.activationException) const StatusPill(label: 'Activation exception', color: AppColors.warning),
        ]),
      ]),
    );
  }

  Widget _correctionBanner(NpCandidateDetail d) => NpBanner(
        icon: Icons.undo_rounded,
        color: const Color(0xFFEA580C),
        title: 'Sent back for correction${d.correctionStage != null ? ' — ${npTitle(d.correctionStage)} stage' : ''}',
        body: [
          if (d.correctionRemarks != null) d.correctionRemarks!,
          'The ${d.correctionStage != null ? npTitle(d.correctionStage).toLowerCase() : 'responsible'} owner must fix this and resubmit'
              '${d.returnToStatus != null ? ' — it then returns to ${npStatusLabel(d.returnToStatus)}.' : '.'}',
        ].join('\n'),
        action: d.can('RESUBMIT')
            ? FilledButton.icon(
                onPressed: _busy ? null : _resubmit,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Resubmit for review'),
              )
            : null,
      );

  Widget _rejectionBanner(NpCandidateDetail d) => NpBanner(
        icon: Icons.warning_amber_rounded,
        color: AppColors.danger,
        title: npStatusLabel(d.status),
        body: [if (d.rejectionReason != null) d.rejectionReason!, 'Rejected on ${npFmtDateTime(d.rejectedAt)}'].join('\n'),
      );

  // ── 1. Candidate ──
  List<Widget> _candidatePanel(NpCandidateDetail d) {
    final branch = Branding.current.term('branch');
    return [
      Column(children: [
        NpInfoRow('Gender', npTitle(d.gender)),
        NpInfoRow('Date of birth', npFmtDate(d.dateOfBirth)),
        NpInfoRow("Father's name", d.fatherOrSpouseName),
        NpInfoRow('Marital status', npTitle(d.maritalStatus)),
        if (d.spouseName != null) NpInfoRow('Spouse', d.spouseName),
        if (d.spouseDateOfBirth != null) NpInfoRow('Spouse DOB', npFmtDate(d.spouseDateOfBirth)),
        if (d.spouseMobile != null) NpInfoRow('Spouse mobile', d.spouseMobile),
        if (d.spouseOccupation != null) NpInfoRow('Spouse occupation', d.spouseOccupation),
        NpInfoRow('Alternate mobile', d.alternateMobile),
        NpInfoRow('Email', d.email),
        NpInfoRow('Education', d.education),
        NpInfoRow('Occupation', d.occupation),
        NpInfoRow('Experience', d.experienceYears == null ? null : '${d.experienceYears} yr'),
        NpInfoRow('Two-wheeler', d.hasTwoWheeler == true ? 'Yes' : 'No'),
        NpInfoRow('Smartphone', d.hasSmartphone == true ? 'Yes' : 'No'),
        NpInfoRow('Aadhaar', d.aadhaarLast4 == null ? null : '•••• ${d.aadhaarLast4}'),
        NpInfoRow('PAN', d.panNumber),
        NpInfoRow('Driving licence', d.drivingLicenceNumber),
        NpInfoRow('Bank', d.bankName),
        NpInfoRow('Account', d.bankAccountNumber),
        NpInfoRow('IFSC', d.bankIfsc),
        NpInfoRow('Name as per bank', d.bankAccountHolderName),
        NpInfoRow('Permanent address', d.permanentAddress),
        NpInfoRow('Comm. address', d.communicationAddress),
        NpInfoRow(branch, d.branchName),
      ]),
      if (d.eligibility.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const NpFieldLabel('Eligibility'),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final e in d.eligibility.entries) NpChip(e.key, on: e.value)]),
          if (d.eligibilityNotes != null) ...[
            const SizedBox(height: 6),
            Text(d.eligibilityNotes!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
          ],
        ]),
      if (d.remarks != null && d.remarks!.isNotEmpty)
        Text(d.remarks!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
      if (d.can('IDENTIFY'))
        FilledButton.icon(
          onPressed: _busy ? null : _identify,
          icon: const Icon(Icons.how_to_reg_rounded, size: 18),
          label: const Text('Submit as identified'),
        ),
    ];
  }

  // ── 2. Orientation ──
  List<Widget> _orientationPanel(NpCandidateDetail d, NpConfig config) {
    final items = config.orientationItems.isNotEmpty ? config.orientationItems : d.orientationItems.keys.toList();
    return [
      if (d.orientationCompleted)
        Row(children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Completed on ${npFmtDate(d.orientationDate)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
              NpPersonStamp(person: d.orientationBy, at: d.orientationAt),
            ]),
          ),
        ]),
      if (d.can('ORIENTATION'))
        NpActionBox(
          title: 'Cover each orientation item',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (items.isEmpty)
              const Text('No orientation items configured.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            for (final item in items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(item, style: const TextStyle(fontSize: 13.5)),
                value: _orientItems[item] ?? false,
                onChanged: (v) => setState(() => _orientItems[item] = v ?? false),
              ),
            const NpFieldLabel('Orientation date'),
            _dateField(_orientDate, (v) => setState(() => _orientDate = v)),
            const NpFieldLabel('Remarks'),
            TextField(controller: _orientRemarks, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : () => _orientation(items), child: const Text('Mark orientation completed')),
          ]),
        )
      else if (items.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [for (final i in items) NpChip(i, on: d.orientationItems[i] == true)]),
    ];
  }

  // ── 3. Interview ──
  List<Widget> _interviewPanel(NpCandidateDetail d) => [
        if (d.interviews.isEmpty && !d.can('INTERVIEW'))
          const Text('No interview recorded yet.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
        for (final iv in d.interviews)
          _historyCard(
            leading: StatusPill(
              label: iv.result == 'PASS' ? 'PASS' : 'FAIL',
              color: iv.result == 'PASS' ? AppColors.success : AppColors.danger,
            ),
            title: 'Attempt ${iv.attemptNo} · ${npFmtDate(iv.interviewDate)}',
            lines: [
              if (iv.interviewer != null) 'Interviewer: ${iv.interviewer!.name}',
              if (iv.remarks != null) iv.remarks!,
            ],
            stamp: NpPersonStamp(person: iv.recordedBy, at: iv.recordedAt, prefix: 'Recorded by'),
          ),
        if (d.can('INTERVIEW'))
          NpActionBox(
            title: 'Record the interview',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const NpFieldLabel('Interview date'),
              _dateField(_ivDate, (v) => setState(() => _ivDate = v)),
              const NpFieldLabel('Interviewer'),
              _EmployeeField(value: _ivInterviewer, onChanged: (e) => setState(() => _ivInterviewer = e)),
              const NpFieldLabel('Result', required: true),
              DropdownButtonFormField<String>(
                value: _ivResult,
                hint: const Text('— Select —'),
                items: const [
                  DropdownMenuItem(value: 'PASS', child: Text('Pass')),
                  DropdownMenuItem(value: 'REJECT', child: Text('Fail')),
                ],
                onChanged: (v) => setState(() => _ivResult = v),
              ),
              NpFieldLabel('Remarks', required: _ivResult == 'REJECT'),
              TextField(
                controller: _ivRemarks,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: _ivResult == 'REJECT' ? 'Why the candidate failed' : null),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: _ivResult == 'REJECT' ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
                onPressed: (_busy || _ivResult == null) ? null : _interview,
                child: Text(_ivResult == 'REJECT' ? 'Record as failed' : 'Record interview'),
              ),
            ]),
          ),
      ];

  // ── 4. KYC ──
  List<Widget> _kycPanel(NpCandidateDetail d, NpConfig config) {
    final kyc = d.documents.where((x) => x.stage == 'KYC').toList();
    return [
      if (d.missingKycDocs.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Missing mandatory:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.warning)),
          for (final code in d.missingKycDocs) NpChip(config.docTypeLabel(code), color: AppColors.warning),
        ]),
      if (d.can('UPLOAD_KYC'))
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _uploadKyc(config),
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Upload KYC document'),
        ),
      NpDocumentList(
        documents: kyc,
        emptyText: 'No KYC documents uploaded yet.',
        busy: _busy,
        onDelete: d.can('UPLOAD_KYC') ? _deleteDoc : null,
        onVerify: d.can('VERIFY_DOCUMENT') ? _verifyDoc : null,
      ),
      if (d.can('SUBMIT_DOCUMENTS'))
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton.icon(
            onPressed: (_busy || d.missingKycDocs.isNotEmpty) ? null : _submitDocuments,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Submit documents'),
          ),
          if (d.missingKycDocs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Still missing: ${d.missingKycDocs.map(config.docTypeLabel).join(', ')}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
        ]),
    ];
  }

  // ── 5. CB check ──
  List<Widget> _cbPanel(NpCandidateDetail d) => [
        if (d.cbChecks.isEmpty)
          const Text('No CB check has been raised yet.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
        for (final cb in d.cbChecks)
          _historyCard(
            leading: StatusPill(
              label: cb.status,
              color: cb.status == 'APPROVED'
                  ? AppColors.success
                  : (cb.status == 'REJECTED' || cb.status == 'ERROR')
                      ? AppColors.danger
                      : AppColors.warning,
            ),
            title: 'Attempt ${cb.attemptNo}${cb.referenceNo != null ? ' · Ref ${cb.referenceNo}' : ''}',
            lines: [
              if (cb.provider.isNotEmpty) 'Provider: ${cb.provider}',
              if (cb.score != null) 'Score: ${cb.score}',
              if (cb.remarks != null) cb.remarks!,
            ],
            stamp: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NpPersonStamp(person: cb.submittedBy, at: cb.submittedAt, prefix: 'Submitted by'),
              if (cb.decidedBy != null || cb.decidedAt != null) NpPersonStamp(person: cb.decidedBy, at: cb.decidedAt, prefix: 'Decided by'),
            ]),
            trailing: cb.report == null
                ? null
                : TextButton.icon(
                    onPressed: () => npOpenFile(context, cb.report),
                    icon: const Icon(Icons.description_rounded, size: 16),
                    label: const Text('Report'),
                  ),
          ),
        if (d.can('SUBMIT_CB'))
          FilledButton.icon(
            onPressed: _busy ? null : _submitCb,
            icon: const Icon(Icons.credit_score_rounded, size: 18),
            label: const Text('Submit for CB check'),
          ),
        if (d.can('RECORD_CB_RESULT'))
          NpActionBox(
            title: 'Record the bureau result',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const NpFieldLabel('Result'),
              DropdownButtonFormField<String>(
                value: _cbResult,
                items: const [
                  DropdownMenuItem(value: 'APPROVED', child: Text('Approved')),
                  DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
                ],
                onChanged: (v) => setState(() => _cbResult = v ?? 'APPROVED'),
              ),
              const NpFieldLabel('Reference no.'),
              TextField(controller: _cbRef),
              const NpFieldLabel('Score'),
              TextField(controller: _cbScore, keyboardType: TextInputType.number),
              NpFieldLabel('Remarks', required: _cbResult == 'REJECTED'),
              TextField(controller: _cbRemarks, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences),
              const SizedBox(height: 12),
              FilledButton(
                style: _cbResult == 'REJECTED' ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
                onPressed: _busy ? null : _cbResultAction,
                child: const Text('Record CB result'),
              ),
            ]),
          ),
      ];

  // ── 6. BGV ──
  List<Widget> _bgvPanel(NpCandidateDetail d) {
    final submitted = d.bgvReports.where((r) => !r.draft).toList();
    final draft = d.bgvDraft;
    return [
      if (submitted.isEmpty && draft == null)
        const Text('No BGV report submitted yet.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
      for (final r in submitted) _bgvReportCard(r),
      if (draft != null && d.can('BGV_DRAFT'))
        NpBanner(
          icon: Icons.edit_note_rounded,
          color: AppColors.info,
          title: 'Draft visit report saved',
          body: 'Photos: ${draft.photos.length} · GPS: ${draft.latitude != null ? 'captured' : 'not captured'} · '
              'Recommendation: ${draft.recommendation == null ? '—' : npTitle(draft.recommendation)}',
        ),
      if (d.can('BGV_DRAFT') || d.can('BGV_SUBMIT'))
        FilledButton.icon(
          onPressed: _busy ? null : _openBgv,
          icon: const Icon(Icons.home_work_rounded, size: 18),
          label: Text(draft == null ? 'Start visit report' : 'Continue visit report'),
        ),
      if (d.can('BGV_REJECT'))
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: _busy ? null : _rejectBgv,
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Reject at BGV'),
        ),
    ];
  }

  Widget _bgvReportCard(NpBgvReport r) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.hairline)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Visit #${r.attemptNo} · ${npFmtDateTime(r.visitAt)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            if (r.recommendation != null)
              StatusPill(
                label: r.recommendation == 'RECOMMENDED' ? 'Recommended' : 'Not recommended',
                color: r.recommendation == 'RECOMMENDED' ? AppColors.success : AppColors.danger,
              ),
          ]),
          const SizedBox(height: 6),
          NpInfoRow('Address verified', r.addressVerified == true ? 'Yes' : 'No'),
          NpInfoRow('Address as found', r.addressAsFound),
          NpInfoRow('Residence type', npTitle(r.residenceType)),
          NpInfoRow('Years at address', r.yearsAtAddress?.toString()),
          if (r.latitude != null && r.longitude != null)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () => npOpenMaps(r.latitude!, r.longitude!),
              icon: const Icon(Icons.place_rounded, size: 16),
              label: Text('${r.latitude!.toStringAsFixed(5)}, ${r.longitude!.toStringAsFixed(5)}'
                  '${r.locationAccuracyM != null ? ' (±${r.locationAccuracyM!.round()} m)' : ''}'),
            ),
          if (r.familyMembers.isNotEmpty) ...[
            const NpFieldLabel('Family members'),
            for (final m in r.familyMembers)
              Text('• ${m.name} — ${m.relation}${m.age != null ? ', ${m.age} yrs' : ''}${m.occupation != null && m.occupation!.isNotEmpty ? ', ${m.occupation}' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
          ],
          if (r.background.isNotEmpty) ...[
            const NpFieldLabel('Background'),
            for (final e in r.background.entries)
              if (e.value.isNotEmpty) NpInfoRow(_bgLabel(e.key), e.value),
          ],
          if (r.checklist.isNotEmpty) ...[
            const NpFieldLabel('Checklist'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final e in r.checklist.entries) NpChip(e.key, on: e.value)]),
          ],
          if (r.amRemarks != null && r.amRemarks!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.amRemarks!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
          ],
          const SizedBox(height: 8),
          NpDocumentList(documents: r.photos, emptyText: 'No visit photos.'),
          NpPersonStamp(person: r.submittedBy, at: r.submittedAt, prefix: 'Submitted by'),
        ]),
      );

  String _bgLabel(String key) {
    for (final e in kNpBgvBackgroundKeys) {
      if (e.key == key) return e.value;
    }
    return npTitle(key);
  }

  // ── 7. DM ──
  List<Widget> _dmPanel(NpCandidateDetail d) => [
        _approvalHistory(d.approvals.where((a) => a.level == 'DM').toList(), 'No DM decision recorded yet.'),
        if (d.can('DM_DECISION'))
          NpActionBox(
            title: 'Your decision',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: _busy ? null : _dmApprove,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _dmSendBack,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Send back to BGV'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: _busy ? null : _dmReject,
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Reject'),
              ),
            ]),
          ),
      ];

  // ── 8. Agreement & PDC ──
  List<Widget> _agreementPanel(NpCandidateDetail d) => [
        if (d.agreements.isEmpty)
          const Text('No agreement submitted yet.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
        for (final ag in d.agreements)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.hairline)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('Agreement #${ag.attemptNo} · ${npFmtDate(ag.agreementDate)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                if (ag.file != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => npOpenFile(context, ag.file),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Open'),
                  ),
              ]),
              for (final p in ag.pdcs)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('PDC ${p.seqNo} · Cheque ${p.chequeNumber}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        Text([p.bankName, p.ifsc, p.accountNumber].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ]),
                    ),
                    if (p.file != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => npOpenFile(context, p.file),
                        icon: Icon(Icons.image_rounded, size: 18, color: AppColors.primary),
                      ),
                  ]),
                ),
              if (ag.remarks != null && ag.remarks!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(ag.remarks!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              ],
              const SizedBox(height: 4),
              NpPersonStamp(person: ag.submittedBy, at: ag.submittedAt, prefix: 'Submitted by'),
            ]),
          ),
        if (d.can('SUBMIT_AGREEMENT'))
          FilledButton.icon(
            onPressed: _busy ? null : _openAgreement,
            icon: const Icon(Icons.description_rounded, size: 18),
            label: const Text('Submit agreement & PDCs'),
          ),
      ];

  // ── 9. OPS ──
  List<Widget> _opsPanel(NpCandidateDetail d) => [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const NpFieldLabel('File completeness (server-checked)'),
          for (final k in kNpOpsChecklistKeys)
            NpCheckLine(ok: d.opsChecklist[k] == true, label: kNpOpsChecklistLabels[k]!, failColor: AppColors.danger),
        ]),
        _approvalHistory(d.approvals.where((a) => a.level == 'OPS').toList(), 'No OPS decision recorded yet.'),
        if (d.can('OPS_DECISION'))
          NpActionBox(
            title: 'Confirm each item',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final k in kNpOpsChecklistKeys)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(kNpOpsChecklistLabels[k]!, style: const TextStyle(fontSize: 13.5)),
                  value: _opsChecks[k] ?? false,
                  onChanged: (v) => setState(() => _opsChecks[k] = v ?? false),
                ),
              const NpFieldLabel('Send-back stage'),
              DropdownButtonFormField<String>(
                value: _opsSendBack,
                items: [for (final s in kNpCorrectionStages) DropdownMenuItem(value: s, child: Text(npTitle(s)))],
                onChanged: (v) => setState(() => _opsSendBack = v ?? 'KYC'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: (_busy || !kNpOpsChecklistKeys.every((k) => _opsChecks[k] == true)) ? null : _opsApprove,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve & generate NP ID'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _opsSendBackAction,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Send back'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: _busy ? null : _opsReject,
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Reject'),
              ),
            ]),
          ),
      ];

  // ── 10. NP ID ──
  List<Widget> _npIdPanel(NpCandidateDetail d) => [
        if (d.npId == null)
          const Text('Generated automatically on OPS approval.', style: TextStyle(fontSize: 12.5, color: AppColors.muted))
        else
          Column(children: [
            NpInfoRow('NP ID', d.npId),
            NpInfoRow('Generated at', npFmtDateTime(d.npIdGeneratedAt)),
          ]),
      ];

  // ── 11. App activation ──
  List<Widget> _activationPanel(NpCandidateDetail d) {
    final pending = d.activations.where((a) => a.verifiedAt == null).isNotEmpty;
    return [
      if (d.activations.isEmpty)
        const Text('The app has not been activated yet.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
      for (final a in d.activations)
        _historyCard(
          leading: StatusPill(
            label: a.verifiedAt != null ? 'Verified' : (a.exceptionReason != null ? 'Exception' : 'OTP sent'),
            color: a.verifiedAt != null ? AppColors.success : (a.exceptionReason != null ? AppColors.warning : AppColors.info),
          ),
          title: 'Attempt ${a.attemptNo} · ${a.mobileNumber}',
          lines: [
            if (a.otpSentAt != null) 'OTP sent ${npFmtDateTime(a.otpSentAt)} · expires ${npFmtDateTime(a.otpExpiresAt)}',
            if (a.verifiedAt != null) 'Verified ${npFmtDateTime(a.verifiedAt)}',
            if ([a.deviceModel, a.deviceOs, a.appVersion].any((x) => x != null))
              [a.deviceModel, a.deviceOs, a.appVersion].whereType<String>().join(' · '),
            if (a.exceptionReason != null) 'Exception: ${a.exceptionReason}',
          ],
          stamp: NpPersonStamp(person: a.performedBy, at: null),
        ),
      if (d.can('SEND_OTP'))
        NpActionBox(
          title: 'Send the activation OTP',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NpFieldLabel('Mobile number'),
            TextField(
              controller: _otpMobile,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _sendOtp,
              icon: const Icon(Icons.sms_rounded, size: 18),
              label: Text(_otpSent || pending ? 'Resend OTP' : 'Send OTP'),
            ),
          ]),
        ),
      if (d.can('VERIFY_OTP') && (_otpSent || pending))
        NpActionBox(
          title: 'Verify the OTP',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NpFieldLabel('OTP'),
            TextField(
              controller: _otpCode,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              style: const TextStyle(letterSpacing: 6, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: '6 digits'),
            ),
            const SizedBox(height: 6),
            Text('Device: ${[_deviceModel, _deviceOs, _appVersion].whereType<String>().join(' · ')}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _verifyOtp,
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: const Text('Verify & activate'),
            ),
          ]),
        ),
      if (d.can('ACTIVATION_EXCEPTION'))
        OutlinedButton.icon(
          onPressed: _busy ? null : _activationException,
          icon: const Icon(Icons.report_problem_rounded, size: 18),
          label: const Text('Record activation exception'),
        ),
    ];
  }

  // ── 12. ESAF ──
  List<Widget> _esafPanel(NpCandidateDetail d) => [
        Column(children: [
          NpInfoRow('ESAF ID', d.esafId),
          NpInfoRow('Created at', npFmtDateTime(d.esafIdCreatedAt)),
          if (d.esafIdBy != null) NpInfoRow('Created by', d.esafIdBy!.name),
        ]),
        if (d.can('CREATE_ESAF_ID'))
          NpActionBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const NpFieldLabel('ESAF ID', required: true),
              TextField(controller: _esaf, textCapitalization: TextCapitalization.characters),
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : _saveEsaf, child: const Text('Save ESAF ID')),
            ]),
          ),
      ];

  // ── 13. Final ──
  List<Widget> _finalPanel(NpCandidateDetail d) => [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NpCheckLine(ok: d.npId != null, label: 'NP ID${d.npId != null ? ' — ${d.npId}' : ''}'),
          NpCheckLine(ok: d.nava360ActivatedAt != null, label: 'App activation'),
          NpCheckLine(ok: d.esafId != null, label: 'ESAF ID${d.esafId != null ? ' — ${d.esafId}' : ''}'),
        ]),
        if (d.finalActivatedAt != null)
          Row(children: [
            const Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Active NP since ${npFmtDateTime(d.finalActivatedAt)}${d.finalActivatedBy != null ? ' · by ${d.finalActivatedBy!.name}' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ]),
        if (d.can('FINAL_ACTIVATE'))
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: _busy ? null : _finalActivate,
            icon: const Icon(Icons.rocket_launch_rounded, size: 18),
            label: const Text('Mark as Active NP'),
          ),
      ];

  Widget _auditCard() => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppSectionHeader(title: 'Audit trail'),
          const SizedBox(height: 8),
          if (_audit.isEmpty)
            const Text('No audit entries.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
          for (final a in _audit)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(npTitle(a.action), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink))),
                  Text(npFmtDateTime(a.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
                Text('${npStatusLabel(a.previousStatus)} → ${npStatusLabel(a.newStatus)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
                Text([a.performedBy ?? '—', if (a.roles != null && a.roles!.isNotEmpty) a.roles!].join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                if ((a.remarks ?? a.detail) != null)
                  Text((a.remarks ?? a.detail)!, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
              ]),
            ),
        ]),
      );

  // ── helpers ──

  Widget _approvalHistory(List<NpApproval> approvals, String emptyText) {
    if (approvals.isEmpty) return Text(emptyText, style: const TextStyle(fontSize: 12.5, color: AppColors.muted));
    return Column(children: [
      for (final a in approvals)
        _historyCard(
          leading: StatusPill(
            label: npTitle(a.action),
            color: a.action == 'APPROVE' ? AppColors.success : (a.action == 'REJECT' ? AppColors.danger : AppColors.warning),
          ),
          title: 'Attempt ${a.attemptNo}${a.sendBackStage != null ? ' · back to ${npTitle(a.sendBackStage)}' : ''}',
          lines: [
            '${npStatusLabel(a.fromStatus)} → ${npStatusLabel(a.toStatus)}',
            if (a.remarks != null && a.remarks!.isNotEmpty) a.remarks!,
          ],
          stamp: NpPersonStamp(person: a.actedBy, at: a.actedAt),
        ),
    ]);
  }

  Widget _historyCard({required Widget leading, required String title, List<String> lines = const [], Widget? stamp, Widget? trailing}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.hairline)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            leading,
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink))),
            if (trailing != null) trailing,
          ]),
          for (final l in lines) Padding(padding: const EdgeInsets.only(top: 3), child: Text(l, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft))),
          if (stamp != null) Padding(padding: const EdgeInsets.only(top: 3), child: stamp),
        ]),
      );

  Widget _dateField(DateTime value, ValueChanged<DateTime> onPicked) => InkWell(
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime(2035));
          if (d != null) onPicked(d);
        },
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InputDecorator(
          decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_rounded, size: 18)),
          child: Text(npFmtDate(value), style: const TextStyle(fontSize: 14, color: AppColors.ink)),
        ),
      );
}

/// Employee autocomplete backed by `/api/employees/lookup` (interviewer picker).
class _EmployeeField extends ConsumerStatefulWidget {
  const _EmployeeField({required this.value, required this.onChanged});
  final EmployeeLookup? value;
  final ValueChanged<EmployeeLookup?> onChanged;

  @override
  ConsumerState<_EmployeeField> createState() => _EmployeeFieldState();
}

class _EmployeeFieldState extends ConsumerState<_EmployeeField> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value != null) {
      return InputDecorator(
        decoration: InputDecoration(
          suffixIcon: IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => widget.onChanged(null)),
        ),
        child: Text(widget.value!.label, style: const TextStyle(fontSize: 14, color: AppColors.ink)),
      );
    }
    final results = ref.watch(employeeLookupProvider(_q));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        decoration: const InputDecoration(hintText: 'Search employee', prefixIcon: Icon(Icons.search_rounded, size: 20)),
        onChanged: (v) => setState(() => _q = v),
      ),
      if (_q.trim().length >= 2)
        results.when(
          data: (list) => list.isEmpty
              ? const Padding(padding: EdgeInsets.all(8), child: Text('No matches', style: TextStyle(fontSize: 12, color: AppColors.muted)))
              : Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: ListView(shrinkWrap: true, children: [
                    for (final e in list)
                      ListTile(
                        dense: true,
                        title: Text(e.label, style: const TextStyle(fontSize: 13)),
                        onTap: () {
                          _ctrl.clear();
                          setState(() => _q = '');
                          widget.onChanged(e);
                        },
                      ),
                  ]),
                ),
          loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2)),
          error: (e, _) => Padding(padding: const EdgeInsets.all(8), child: Text('$e', style: const TextStyle(fontSize: 12, color: AppColors.danger))),
        ),
    ]);
  }
}
